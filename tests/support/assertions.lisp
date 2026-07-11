(in-package #:nshell/test)

(defmacro assert-symbol-boundaries (&key present absent)
  `(progn
     ,@(loop for symbol in present
             collect `(is (fboundp ',symbol)))
     ,@(loop for symbol in absent
             collect `(is (not (fboundp ',symbol))))))

(defmacro assert-package-function-boundaries (&key package present absent)
  `(progn
     ,@(loop for symbol in present
             collect `(multiple-value-bind (found-symbol status)
                          (find-symbol ,(symbol-name symbol) ,package)
                        (is (and status (fboundp found-symbol)))))
     ,@(loop for symbol in absent
             collect `(is (not (nth-value 1
                                          (find-symbol ,(symbol-name symbol)
                                                       ,package)))))))

(defmacro assert-package-symbol-boundaries (&key package present absent)
  `(progn
     ,@(loop for symbol in present
             collect `(is (nth-value 1
                                     (find-symbol ,(symbol-name symbol)
                                                  ,package))))
     ,@(loop for symbol in absent
             collect `(is (not (nth-value 1
                                          (find-symbol ,(symbol-name symbol)
                                                       ,package)))))))

(defmacro %assert-after-name-expansion-cases ((builder) &body cases)
  "Assert CASES against a multiple-value expander whose first argument is INPUT.

Each case is ((EXPECTED-EXPANSION EXPECTED-NEXT) &rest ARGS)."
  (let ((expander (gensym "EXPANDER-")))
    `(let ((,expander ,builder))
       ,@(mapcar (lambda (case)
                   (destructuring-bind ((expected-expansion expected-next)
                                        &rest args)
                       case
                     `(multiple-value-bind (expansion next)
                          (funcall ,expander ,@args)
                        (is (equal ,expected-expansion expansion))
                        (is (equal ,expected-next next)))))
                 cases))))

(defmacro assert-control-flow-stack-transition (transition-form
                                                &key
                                                  transition-p
                                                  copy-absent
                                                  stack-eq
                                                  stack-null
                                                  ((:unexpected unexpected) nil unexpected-p)
                                                  ((:frame-keyword frame-keyword) nil frame-keyword-p)
                                                  ((:frame-else-seen frame-else-seen)
                                                   nil frame-else-seen-p))
  (let ((transition (gensym "TRANSITION-"))
        (stack (gensym "STACK-"))
        (frame (gensym "FRAME-"))
        (forms '())
        (need-stack-p (or stack-eq
                          stack-null
                          frame-keyword-p
                          frame-else-seen-p))
        (need-frame-p (or frame-keyword-p
                          frame-else-seen-p)))
    (when transition-p
      (push `(is (nshell.domain.parsing::%control-flow-stack-transition-p
                  ,transition))
            forms))
    (when copy-absent
      (push `(is (not (fboundp
                       'nshell.domain.parsing::copy-%control-flow-stack-transition)))
            forms))
    (when stack-eq
      (push `(is (eq ,stack-eq ,stack)) forms))
    (when stack-null
      (push `(is (null ,stack)) forms))
    (when unexpected-p
      (push `(is (string= ,unexpected
                          (nshell.domain.parsing::%control-flow-stack-transition-unexpected-keyword
                           ,transition)))
            forms))
    (when (or frame-keyword-p frame-else-seen-p)
      (push `(is (not (null ,frame))) forms))
    (when frame-keyword-p
      (push `(is (string= ,frame-keyword
                          (nshell.domain.parsing::control-flow-frame-keyword
                           ,frame)))
            forms))
    (when frame-else-seen-p
      (push `(is (eql ,frame-else-seen
                      (nshell.domain.parsing::control-flow-frame-else-seen
                       ,frame)))
            forms))
    `(let* ((,transition ,transition-form)
            ,@(when need-stack-p
                `((,stack (nshell.domain.parsing::%control-flow-stack-transition-stack
                           ,transition))))
            ,@(when need-frame-p
                `((,frame (and ,stack (first ,stack))))))
       ,@(nreverse forms))))
