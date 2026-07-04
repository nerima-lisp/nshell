; Builtin registry, path resolution, and command dispatch.
(in-package #:nshell.application)


(defvar *builtin-registry* (make-hash-table :test #'equal)
  "Registry mapping builtin command names to handler functions.")

(defun lookup-builtin (name)
  "Return the builtin handler registered for NAME, or NIL."
  (and name (gethash name *builtin-registry*)))

(defun %required-argument-error (builtin option requirement)
  (format nil "~a: ~a requires ~a~%" builtin option requirement))

(defun %builtin-option-p (arg names)
  (member arg names :test #'string=))

(defun %builtin-option-like-p (arg)
  (and arg
       (> (length arg) 1)
       (char= (char arg 0) #\-)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro %with-option-arguments ((remaining option)
                                    on-sentinel
                                    on-unknown
                                    on-operand
                                    &body clauses)
    `(block nil
       (loop while ,remaining
             for ,option = (first ,remaining)
             do (cond
                  ((string= ,option "--")
                   (setf ,remaining (rest ,remaining))
                   ,on-sentinel)
                  ,@clauses
                  ((%builtin-option-like-p ,option)
                   ,on-unknown)
                  (t ,on-operand)))))

  (defmacro %with-required-argument ((return-target remaining builtin option requirement status) &body body)
    `(if (rest ,remaining)
         (progn ,@body)
         (return-from ,return-target
           (values (%required-argument-error ,builtin ,option ,requirement)
                    ,status)))))

(defun %builtin-usage-clauses-summary (clauses)
  (format nil "~{~A~^; ~}" clauses))

(defun %builtin-usage (command usage &optional (code 1))
  (values (format nil "~a: usage: ~a~%" command usage) code))

(defun %string-join (items separator)
  (with-output-to-string (out)
    (loop for item in items
          for first = t then nil
          do (unless first
               (write-string separator out))
             (write-string (princ-to-string item) out))))

(defun %filesystem-fn (context key)
  (or (getf (shell-context-filesystem-fns context) key)
      (error "Missing filesystem adapter ~s" key)))

(defun %optional-filesystem-fn (context key)
  (getf (shell-context-filesystem-fns context) key))

(defun %process-fn (context key)
  (or (getf (shell-context-process-fns context) key)
      (error "Missing process adapter ~s" key)))

(defun %optional-process-fn (context key)
  (getf (shell-context-process-fns context) key))

(defun %run-external-command-in-context (context command args)
  (let ((capture-runner (%optional-process-fn context :run-external-capture)))
    (if capture-runner
        (funcall capture-runner command args)
        (values nil
                (funcall (%process-fn context :run-external) command args)))))

(defun %resolve-command-path-candidates (context command)
  (nshell.domain.completion:command-path-candidates
   command
   (or (and (shell-context-environment context)
            (nshell.domain.environment:env-get
             (shell-context-environment context) "PATH"))
       "")
   (lambda (path)
     (%stat-path context path))
   :empty-directory ""))

(defun %stat-path (context path)
  (handler-case
      (funcall (%filesystem-fn context :stat) path)
    (error () nil)))

(defun %path-file-p (context path)
  (let ((fn (%optional-filesystem-fn context :file-exists-p)))
    (cond
      (fn (funcall fn path))
      ((%stat-path context path)
       (let ((pathname (probe-file path)))
         (and pathname (not (uiop:directory-pathname-p pathname)))))
      (t nil))))

(defun %path-directory-p (context path)
  (let ((fn (%optional-filesystem-fn context :directory-exists-p)))
    (cond
      (fn (funcall fn path))
      (t (not (null (uiop:directory-exists-p path)))))))

(defun resolve-command-path (context command)
  "Return COMMAND's executable path from builtins or PATH, or NIL."
  (cond
    ((lookup-builtin command) (values :builtin command))
    (t
     (let ((candidates (%resolve-command-path-candidates context command)))
       (when candidates
         (values :path (first candidates)))))))

(defun %command-path-spec (command)
  (cdr (assoc command nshell.domain.completion:+command-path-builtin-specs+
              :test #'string=)))

(defun %execute-function-command-in-context (context function-body args)
  ;; Expose the call arguments to the function body as $argv / $argv[N].
  (let ((nshell.domain.expansion:*positional-args* args))
    (%source-lines context function-body)))

(defun %execute-command-by-name-in-context (context command args)
  (multiple-value-bind (function-body function-present-p)
      (gethash command (shell-context-function-table context))
    (let ((handler (lookup-builtin command)))
      (cond
        (function-present-p
         (%execute-function-command-in-context context function-body args))
        (handler
         (funcall handler context args))
        (t
         (%run-external-command-in-context context command args))))))
