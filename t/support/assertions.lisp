(in-package #:nshell/test)

(defmacro with-rebound-function ((name replacement) &body body)
  `(let ((original-function (symbol-function ',name)))
     (unwind-protect
          (progn
            (setf (symbol-function ',name) ,replacement)
            ,@body)
       (setf (symbol-function ',name) original-function))))

(defun %package-name-has-no-definition-p (name package)
  "True when NAME names no function, variable, setf-function, or class in
PACKAGE.  Writing a package-qualified symbol (e.g. in an :absent boundary list)
interns it, so a plain presence check would spuriously fail; the boundary these
tests care about is the absence of a *definition*, which is what this checks."
  (multiple-value-bind (symbol status) (find-symbol name package)
    (or (null status)
        (not (or (fboundp symbol)
                 (boundp symbol)
                 (fboundp `(setf ,symbol))
                 (find-class symbol nil))))))

(defmacro assert-symbol-boundaries (&key present absent)
  `(progn
     ,@(loop for symbol in present
             collect `(expect (fboundp ',symbol) :to-be-truthy))
     ,@(loop for symbol in absent
             collect `(expect (fboundp ',symbol) :to-be-falsy))))

(defmacro assert-package-function-boundaries (&key package present absent)
  `(progn
     ,@(loop for symbol in present
             collect `(multiple-value-bind (found-symbol status)
                          (find-symbol ,(symbol-name symbol) ,package)
                        (expect (and status (fboundp found-symbol)) :to-be-truthy)))
     ,@(loop for symbol in absent
             collect `(expect (%package-name-has-no-definition-p
                               ,(symbol-name symbol) ,package)
                              :to-be-truthy))))

(defmacro assert-package-symbol-boundaries (&key package present absent)
  `(progn
     ,@(loop for symbol in present
             collect `(expect (nth-value 1
                                     (find-symbol ,(symbol-name symbol)
                                                  ,package)) :to-be-truthy))
     ,@(loop for symbol in absent
             collect `(expect (%package-name-has-no-definition-p
                               ,(symbol-name symbol) ,package)
                              :to-be-truthy))))

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
                        (expect ,expected-expansion :to-equal expansion)
                        (expect ,expected-next :to-equal next))))
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
      (push `(expect (nshell.domain.parsing::%control-flow-stack-transition-p
                  ,transition) :to-be-truthy)
            forms))
    (when copy-absent
      (push `(expect (fboundp
                       'nshell.domain.parsing::copy-%control-flow-stack-transition) :to-be-falsy)
            forms))
    (when stack-eq
      (push `(expect ,stack-eq :to-be ,stack) forms))
    (when stack-null
      (push `(expect ,stack :to-be-null) forms))
    (when unexpected-p
      (push `(expect ,unexpected :to-equal (nshell.domain.parsing::%control-flow-stack-transition-unexpected-keyword
                           ,transition))
            forms))
    (when (or frame-keyword-p frame-else-seen-p)
      (push `(expect (null ,frame) :to-be-falsy) forms))
    (when frame-keyword-p
      (push `(expect ,frame-keyword :to-equal (nshell.domain.parsing::control-flow-frame-keyword
                           ,frame))
            forms))
    (when frame-else-seen-p
      (push `(expect ,frame-else-seen :to-be (nshell.domain.parsing::control-flow-frame-else-seen
                       ,frame))
            forms))
    `(let* ((,transition ,transition-form)
            ,@(when need-stack-p
                `((,stack (nshell.domain.parsing::%control-flow-stack-transition-stack
                           ,transition))))
            ,@(when need-frame-p
                `((,frame (and ,stack (first ,stack))))))
       ,@(nreverse forms))))
