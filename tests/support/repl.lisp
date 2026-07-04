(in-package #:nshell/test)

(defun current-sbcl-executable ()
  (or (uiop:getenv "SBCL")
      #+sbcl (when sb-ext:*runtime-pathname*
               (namestring sb-ext:*runtime-pathname*))
      #-sbcl nil
      "sbcl"))

(defmacro with-repl-test-state (&body body)
  `(let ((nshell.presentation::*running* t)
         (nshell.presentation::*last-exit-code* 0)
         (nshell.presentation::*history* (nshell.domain.history:make-command-history))
         (nshell.presentation::*config* (nshell.domain.configuration:default-config))
         (nshell.presentation::*kb* (nshell.domain.completion:make-empty-knowledge-base))
         (nshell.presentation::*input-state* nil)
         (nshell.presentation::*completion-rendered-lines* 0)
         (nshell.presentation::*prompt-rendered-lines* 0)
         (nshell.presentation::*prompt-rendered-cursor-row* 0)
         (nshell.presentation::*environment* (nshell.domain.environment:make-environment)))
     (nshell.presentation::with-fresh-repl-state-tables
       ,@body)))

(defun repl-test-set-env (name value &optional exported)
  (setf nshell.presentation::*environment*
        (nshell.domain.environment:env-set
         nshell.presentation::*environment* name value exported)))

(defun repl-test-env (name)
  (nshell.domain.environment:env-get nshell.presentation::*environment* name))

(defun repl-test-define-alias (name expansion)
  (setf (gethash name nshell.presentation::*aliases*) expansion))

(defun repl-test-alias (name)
  (gethash name nshell.presentation::*aliases*))

(defun repl-test-abbreviation (name)
  (gethash name nshell.presentation::*abbreviations*))

(defun repl-test-define-function (name body-lines)
  (setf (gethash name nshell.presentation::*functions*) body-lines))

(defun repl-test-function (name)
  (gethash name nshell.presentation::*functions*))

(defun repl-test-register-process-entry (job-id entry)
  (setf (gethash job-id nshell.presentation::*proc-registry*) entry))

(defun repl-test-process-entry (job-id)
  (gethash job-id nshell.presentation::*proc-registry*))

(defun repl-test-running-p ()
  nshell.presentation::*running*)

(defmacro with-temporary-function ((symbol function) &body body)
  `(with-temporary-functions ((,symbol ,function))
     ,@body))

(defmacro with-temporary-functions (bindings &body body)
  (let ((saved-bindings nil)
        (setup-forms nil)
        (restore-forms nil))
    (dolist (binding bindings)
      (destructuring-bind (symbol function) binding
        (let ((original (gensym "ORIGINAL-FUNCTION-")))
          (push `(,original (symbol-function ,symbol)) saved-bindings)
          (push `(setf (symbol-function ,symbol) ,function) setup-forms)
          (push `(setf (symbol-function ,symbol) ,original) restore-forms))))
    `(let ,(nreverse saved-bindings)
       (unwind-protect
            (progn
              ,@(nreverse setup-forms)
              ,@body)
         ,@(nreverse restore-forms)))))

(defmacro with-stable-repl-prompt ((&key (width 4) (text "ns> ")) &body body)
  `(with-temporary-function
       ('nshell.presentation::render-prompt
        (lambda (config last-exit &key last-command-duration-ms terminal-width)
          (declare (ignore config last-exit last-command-duration-ms terminal-width))
          (format t "~a" ,text)
          ,width))
     ,@body))

(defmacro with-fixed-terminal-size ((rows columns) &body body)
  `(with-temporary-function
       ('nshell.infrastructure.acl:get-terminal-size
        (lambda () (values ,rows ,columns)))
     ,@body))

(defmacro with-repl-input-state (initargs &body body)
  `(let ((nshell.presentation::*input-state* (input-state ,@initargs)))
     ,@body))

(defmacro with-repl-render-state (input-initargs &body body)
  `(let ((nshell.presentation::*config*
           (nshell.domain.configuration:default-config))
         (nshell.domain.prompting:*git-status-resolver*
           (lambda (dir)
             (declare (ignore dir))
             (values nil nil))))
     (with-repl-input-state ,input-initargs
       ,@body)))

(defmacro capture-process-output-event (event)
  `(capture-standard-output
     (let ((continuation (nshell.presentation::process-output-event ,event)))
       (when continuation
         (funcall continuation)))))

(defmacro capture-standard-output (&body body)
  `(with-output-to-string (*standard-output*)
     ,@body))

(defmacro with-temporary-output-file ((name &key (prefix "nshell-repl-output")) &body body)
  `(let ((,name (namestring
                 (merge-pathnames
                  (make-pathname :name (format nil "~a~d" ,prefix (get-internal-real-time))
                                 :type "txt")
                  (uiop:temporary-directory)))))
     (unwind-protect
          (progn ,@body)
       (ignore-errors
         (when (probe-file ,name)
           (delete-file ,name))))))

(defun wait-for-file-content (path expected &key (attempts 50) (delay 0.02))
  "Wait for PATH to exist and contain EXPECTED."
  (loop repeat attempts
        when (and (probe-file path)
                  (string= expected (uiop:read-file-string path)))
        do (return t)
        do (sleep delay)
        finally (return (and (probe-file path)
                             (string= expected (uiop:read-file-string path))))))

(defun call-repl-builtin (command args)
  (let ((builtin-p nil)
        (code nil))
    (let ((output (capture-standard-output
                    (multiple-value-setq (builtin-p code)
                      (nshell.presentation::execute-builtin
                       (nshell.domain.parsing:make-command-node command args))))))
      (values output builtin-p code))))

(defun call-repl-execute-ast (ast)
  (let ((code nil))
    (let ((output (capture-standard-output
                    (setf code (nshell.presentation::execute-ast ast)))))
      (values output code))))
