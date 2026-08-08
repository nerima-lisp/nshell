(in-package #:nshell.application)


(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro define-builtin (name lambda-list ignore-variables &body body)
    `(defun ,name ,lambda-list
       ,@(when ignore-variables
           `((declare (ignore ,@ignore-variables))))
       ,@body)))

(define-builtin %builtin-echo (context args) (context)
  (values (format nil "~{~a~^ ~}~%" args) 0))

(define-builtin %builtin-pwd (context args) (args)
  (values (format nil "~a~%" (namestring (funcall (%filesystem-fn context :cwd)))) 0))

(define-builtin %builtin-ls (context args) (args)
  (handler-case
      (values
       (with-output-to-string (out)
         (dolist (file (funcall (%filesystem-fn context :list-dir)
                                (funcall (%filesystem-fn context :cwd))))
           (format out "~a~%" (file-namestring file))))
       0)
    (error (condition)
      (values (format nil "ls: ~a~%" condition) 1))))

(defun %builtin-cd (context args)
  (handler-case
      (let* ((environment (shell-context-environment context))
             (directory
               (or (first args)
                   (and environment
                        (nshell.domain.environment:env-get environment "HOME")))))
        (unless directory
          (error "HOME is not set"))
        (funcall (%filesystem-fn context :chdir) directory)
        (values nil 0))
    (error (condition)
      (values (format nil "cd: ~a~%" condition) 1))))

(define-builtin %builtin-exit (context args) (args)
  (%stop-shell-context context)
  (values nil 0))

(define-builtin %builtin-true (context args) (context args)
  (values nil 0))

(define-builtin %builtin-false (context args) (context args)
  (values nil 1))

(defun %invert-status-code (code)
  (if (zerop (or code 0)) 1 0))

(defun %builtin-not (context args)
  (if (null args)
      (%builtin-usage "not" "not command [args...]" 2)
      (let* ((command (first args))
             (command-args (rest args)))
        (multiple-value-bind (output code)
            (%execute-command-by-name-in-context context command command-args)
          (values output (%invert-status-code code))))))

(defun %builtin-exec (context args) (declare (ignore context)) (if args (sb-ext:quit :unix-status (nshell.infrastructure.acl:run-external-exec (first args) (rest args))) (%builtin-usage "exec" "exec command [args...]")))

(defun %contains-usage ()
  (%builtin-usage
   "contains"
   (%builtin-usage-clauses-summary +builtin-contains-usage-clauses+)))

(defun %parse-contains-args (args)
  (let ((index-p nil)
        (remaining args))
    (%with-option-arguments (remaining option)
        (return)
        (return-from %parse-contains-args
          (values nil nil
                  (format nil "contains: unknown option ~a~%" option)))
        (return)
      ((cdr (assoc option +contains-option-specs+ :test #'string=))
       (setf index-p t
             remaining (rest remaining))))
    (values index-p remaining nil)))

(defun %contains-match-indexes (needle values)
  (loop for value in values
        for index from 1
        when (string= needle value)
          collect index))

(defun %builtin-help-entry-output (entry &optional (prefix ""))
  (format nil "~a~a - ~a~%"
          prefix
          (getf entry :synopsis)
          (getf entry :description)))

(defun %builtin-help-overview-output ()
  (with-output-to-string (out)
    (format out "nshell builtin commands:~%")
    (dolist (entry (nshell.domain.completion:builtin-help-entries))
      (write-string (%builtin-help-entry-output entry "  ") out))))

(defun %builtin-contains (context args)
  (declare (ignore context))
  (multiple-value-bind (index-p operands error-output)
      (%parse-contains-args args)
    (cond
      (error-output
       (values error-output 2))
      ((null operands)
      (values (%contains-usage) 2))
      (t
       (let* ((needle (first operands))
              (values (rest operands))
              (indexes (%contains-match-indexes needle values)))
         (values (when index-p
                   (with-output-to-string (out)
                     (dolist (index indexes)
                       (format out "~d~%" index))))
                 (if indexes 0 1)))))))

(defun %builtin-count (context args)
  "Print the number of ARGS (like fish's count). Exit status is 0 when there is
at least one argument, otherwise 1 -- which makes `count $argv` usable in tests."
  (declare (ignore context))
  (let ((n (length args)))
    (values (format nil "~d~%" n) (if (plusp n) 0 1))))

(defun %seq-parse-args (args)
  "Parse seq ARGS into (values FIRST STEP LAST) integers, or NIL on bad input.
Forms: seq LAST | seq FIRST LAST | seq FIRST STEP LAST."
  (handler-case
      (let ((nums (mapcar (lambda (a) (parse-integer a :junk-allowed nil)) args)))
        (case (length nums)
          (1 (values 1 1 (first nums)))
          (2 (values (first nums) 1 (second nums)))
          (3 (values (first nums) (second nums) (third nums)))
          (t nil)))
    (error () nil)))

(defun %seq-values (first step last)
  (cond
    ((zerop step) nil)
    ((plusp step) (loop for i from first to last by step collect i))
    (t (loop for i from first downto last by (- step) collect i))))

(defun %builtin-seq (context args)
  "Print a sequence of integers, one per line (like seq / fish's seq).
Usage: seq LAST | seq FIRST LAST | seq FIRST STEP LAST. Useful with for loops:
`for i in (seq 1 10)`."
  (declare (ignore context))
  (if (or (null args) (> (length args) 3))
      (values (format nil "seq: usage: seq [FIRST [STEP]] LAST~%") 2)
      (multiple-value-bind (first step last) (%seq-parse-args args)
        (cond
          ((null first)
           (values (format nil "seq: arguments must be integers~%") 2))
          ((zerop step)
           (values (format nil "seq: STEP must not be zero~%") 2))
          (t
           (let ((vals (%seq-values first step last)))
             (values (when vals (format nil "~{~d~%~}" vals)) 0)))))))

(defun %builtin-help (context args)
  (declare (ignore context))
  (if args
      (let ((entry (find (first args)
                         (nshell.domain.completion:builtin-help-entries)
                         :key (lambda (entry) (getf entry :command))
                         :test #'string=)))
        (if entry
            (values (%builtin-help-entry-output entry) 0)
            (values (format nil "help: no help for ~a~%" (first args)) 1)))
      (values (%builtin-help-overview-output) 0)))
