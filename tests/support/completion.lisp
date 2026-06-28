(in-package #:nshell/test)

(defun make-empty-rule-kb ()
  (nshell.domain.completion::make-rule-knowledge-base))

(defun solution-binding (variable solution)
  (cdr (assoc variable solution)))

(defun completion-texts (candidates)
  (mapcar #'nshell.domain.completion:candidate-text candidates))

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

(defmacro with-path-command-adapters ((directory-files-fn executable-p-fn) &body body)
  `(let ((nshell.domain.completion:*path-command-directory-files-fn* ,directory-files-fn)
         (nshell.domain.completion:*path-command-executable-p-fn* ,executable-p-fn))
     ,@body))

(defmacro with-file-completion-adapters ((directory-files-fn subdirectories-fn) &body body)
  `(let ((nshell.domain.completion:*file-completion-directory-files-fn* ,directory-files-fn)
         (nshell.domain.completion:*file-completion-subdirectories-fn* ,subdirectories-fn))
     ,@body))
