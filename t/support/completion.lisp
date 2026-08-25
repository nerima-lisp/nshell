(in-package #:nshell/test)

(defun make-empty-rule-kb ()
  (nshell.domain.completion::make-empty-rule-knowledge-base))

(defun solution-binding (variable solution)
  (cdr (assoc variable solution)))

(defun completion-texts (candidates)
  (mapcar #'nshell.domain.completion:candidate-text candidates))

(defvar *completion-test-filesystem* nil)

(defun make-test-filesystem
    (&key
      (directory-files (constantly nil))
      (subdirectories (constantly nil))
      (executable-p (constantly nil))
      (directory-map #'mapcar))
  (nshell.domain.filesystem:make-filesystem
   :directory-files directory-files
   :subdirectories subdirectories
   :executable-p executable-p
   :directory-map directory-map))

(defun completion-texts-for (kb input)
  (completion-texts
   (nshell.domain.completion:complete
    kb input :filesystem *completion-test-filesystem*)))

(defmacro assert-completion-texts (expected candidates)
  `(expect ,expected :to-equal (completion-texts ,candidates)))

(defmacro assert-completion-texts-for (expected kb input)
  `(assert-completion-texts ,expected
     (nshell.domain.completion:complete
      ,kb ,input :filesystem *completion-test-filesystem*)))

(defmacro assert-completion-texts-cases (kb &rest cases)
  `(progn
     ,@(loop for case in cases
             for input = (getf case :input)
             for expected = (getf case :expected)
             collect `(assert-completion-texts-for ',expected ,kb ,input))))

(defmacro assert-completion-texts-include (candidates &rest texts)
  `(let ((actual-texts (completion-texts ,candidates)))
     ,@(loop for text in texts
             collect `(expect (member ,text actual-texts :test #'string=) :to-be-truthy))))

(defmacro assert-completion-texts-exclude (candidates &rest texts)
  `(let ((actual-texts (completion-texts ,candidates)))
     ,@(loop for text in texts
             collect `(expect (member ,text actual-texts :test #'string=) :to-be-falsy))))

(defmacro assert-texts-include (texts &rest expected-texts)
  `(progn
     ,@(loop for text in expected-texts
             collect `(expect (member ,text ,texts :test #'string=) :to-be-truthy))))

(defmacro assert-texts-exclude (texts &rest unexpected-texts)
  `(progn
     ,@(loop for text in unexpected-texts
             collect `(expect (member ,text ,texts :test #'string=) :to-be-falsy))))

(defmacro assert-completion-help-command-facts (facts &key subcommands flags option-values)
  `(progn
     (expect (nshell.domain.completion::%completion-help-command-facts-p ,facts) :to-be-truthy)
     (expect (listp ,facts) :to-be-falsy)
     ,(when subcommands
        `(expect ,subcommands :to-equal (nshell.domain.completion::%completion-help-command-facts-subcommands
                     ,facts)))
     ,(when flags
        `(expect ,flags :to-equal (nshell.domain.completion::%completion-help-command-facts-flags
                     ,facts)))
     ,(when option-values
        `(expect ,option-values :to-equal (nshell.domain.completion::%completion-help-command-facts-option-values
                     ,facts)))))

(defun completion-candidate-by-text (text candidates)
  (find text candidates
        :key #'nshell.domain.completion:candidate-text
        :test #'string=))

(defun completion-prefix-p (prefix text)
  (and (>= (length text) (length prefix))
       (string-equal prefix text :end2 (length prefix))))

(defun gen-command-prefix (&key (min-length 0) (max-length 4))
  (%pbt-sampled-string "abcdefghijklmnopqrstuvwxyz"
                       :min-length min-length
                       :max-length max-length))

(defmacro with-empty-completion-knowledge-base ((kb) &body body)
  `(let ((,kb (nshell.domain.completion:make-empty-knowledge-base)))
     ,@body))

(defmacro with-seeded-completion-knowledge-base ((kb) &body body)
  `(with-empty-completion-knowledge-base (,kb)
     (nshell.presentation::seed-repl-completion-knowledge-base ,kb)
     ,@body))

(defmacro with-test-path-filesystem ((directory-files-fn executable-p-fn) &body body)
  `(let ((*completion-test-filesystem*
           (make-test-filesystem
            :directory-files ,directory-files-fn
            :executable-p ,executable-p-fn)))
     ,@body))

(defmacro with-test-file-filesystem ((directory-files-fn subdirectories-fn) &body body)
  `(let ((*completion-test-filesystem*
           (make-test-filesystem
            :directory-files ,directory-files-fn
            :subdirectories ,subdirectories-fn
            :executable-p (constantly t))))
     ,@body))

(defmacro with-repl-completion-help-fetcher
    ((fetch-count-var help-text
      &key
        (exit-code 0)
        (command-available-p
         '(function
           (lambda (command)
             (declare (ignore command))
             t))))
     &body body)
  `(let ((,fetch-count-var 0))
     (with-repl-test-state
       (let ((nshell.presentation::*completion-help-fetcher*
               (lambda (command)
                 (declare (ignore command))
                 (incf ,fetch-count-var)
                 (values ,help-text ,exit-code)))
             (nshell.presentation::*completion-help-command-available-p*
               ,command-available-p))
         ,@body))))

(defmacro with-repl-completion-refresh ((state candidates input
                                               &key
                                                 (cursor-pos `(length ,input)))
                                        &body body)
  `(with-repl-input-state (:buffer ,input :cursor-pos ,cursor-pos)
     (multiple-value-bind (,state ,candidates)
         (nshell.presentation::%refresh-completion-session-state
          nshell.presentation::*input-state*)
       ,@body)))

(defmacro assert-completion-candidate (text candidates &key kind description)
  `(let ((candidate (completion-candidate-by-text ,text ,candidates)))
     (expect (null candidate) :to-be-falsy)
     ,(when kind
        `(expect ,kind :to-be (nshell.domain.completion:candidate-kind candidate)))
     ,(when description
        `(expect ,description :to-equal (nshell.domain.completion:candidate-description candidate)))))
