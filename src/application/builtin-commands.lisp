(in-package #:nshell.application)


(define-builtin %builtin-echo (context args) (context)
  (values (format nil "~{~a~^ ~}~%" args) 0))


(defun %normalize-directory-path (path &optional base)
  (let* ((path (etypecase path
                 (string path)
                 (pathname (namestring path))))
         (absolute-p (and (plusp (length path))
                          (char= (char path 0) #\/)))
         (base (unless absolute-p
                 (or base (namestring (host-kit:getcwd)))))
         (combined (concatenate 'string
                                (if absolute-p
                                    path
                                    (concatenate 'string
                                                 (string-right-trim "/" base)
                                                 "/" path))
                                "/"))
         (components nil)
         (start 1))
    (loop for separator = (position #\/ combined :start start)
          while separator
          for component = (subseq combined start separator)
          do (cond
               ((or (string= component "") (string= component ".")))
               ((string= component "..")
                (when components (pop components)))
               (t (push component components)))
             (setf start (1+ separator)))
    (format nil "/~{~a~^/~}" (nreverse components))))

(defun %directory-paths-equivalent-p (left right)
  (let ((left (%normalize-directory-path left))
        (right (%normalize-directory-path right)))
    (or (string= left right)
        (let ((canonical-left
                (ignore-errors
                  (%normalize-directory-path (truename left))))
              (canonical-right
                (ignore-errors
                  (%normalize-directory-path (truename right)))))
          (and canonical-left
               canonical-right
               (string= canonical-left canonical-right))))))

(defun %logical-current-directory (environment physical-cwd)
  (let ((physical (and physical-cwd
                       (%normalize-directory-path physical-cwd)))
        (pwd (and environment
                  (nshell.domain.environment:env-get environment "PWD"))))
    (cond
      ((and pwd physical
            (%directory-paths-equivalent-p pwd physical))
       (%normalize-directory-path pwd))
      (physical physical)
      (pwd (%normalize-directory-path pwd))
      (t (error "The current directory is unavailable")))))

(define-builtin %builtin-pwd (context args) (args)
  (values
    (format nil "~a~%"
            (%logical-current-directory
             (shell-context-environment context)
             (ignore-errors (host-kit:getcwd))))
    0))

(defun %update-directory-environment (context environment old-cwd new-cwd)
  (when environment
    (let* ((old-cwd (%normalize-directory-path old-cwd))
           (new-cwd (%normalize-directory-path new-cwd))
           (environment
             (nshell.domain.environment:env-set
              environment
              "OLDPWD"
              old-cwd
              (if (nshell.domain.environment:env-defined-p environment "OLDPWD")
                  (nshell.domain.environment:env-exported-p environment "OLDPWD")
                  t)))
           (environment
             (nshell.domain.environment:env-set
              environment
              "PWD"
              new-cwd
              (if (nshell.domain.environment:env-defined-p environment "PWD")
                  (nshell.domain.environment:env-exported-p environment "PWD")
                  t))))
      (setf (shell-context-environment context) environment))))

(defun %cd-target (environment args)
  (cond
    ((null args)
     (or (and environment
              (nshell.domain.environment:env-get environment "HOME"))
         (error "HOME is not set")))
    ((string= (first args) "-")
     (if (and environment
              (nshell.domain.environment:env-defined-p environment "OLDPWD"))
         (nshell.domain.environment:env-get environment "OLDPWD")
         (error "OLDPWD is not set")))
    (t (first args))))

(defun %cd-output (args new-cwd)
  (when (and args (string= (first args) "-"))
    (format nil "~a~%" (%normalize-directory-path new-cwd))))

(define-builtin %builtin-cd (context args) ()
  (handler-case
      (if (> (length args) 1)
          (%builtin-usage "cd" "cd [directory]")
          (let* ((environment (shell-context-environment context))
                 (old-cwd
                   (%logical-current-directory
                    environment
                    (ignore-errors (host-kit:getcwd))))
                 (target (%cd-target environment args))
                 (new-cwd (%normalize-directory-path target old-cwd)))
            (host-kit:chdir new-cwd)
            (%update-directory-environment context environment old-cwd new-cwd)
            (run-shell-hooks :cd old-cwd new-cwd)
            (values (%cd-output args new-cwd) 0)))
    (error (condition)
      (values (format nil "cd: ~a~%" condition) 1))))

(defun %parse-exit-status (argument)
  (handler-case
      (values (mod (parse-integer argument :junk-allowed nil) 256) t)
    (error ()
      (values nil nil))))
(defvar *exit-warning-state* nil)
(defun %exit-warning-message-if-required (job-monitor)
  (let ((active-job-ids nil))
    (when job-monitor
      (nshell.domain.job-control:monitor-map-jobs
       job-monitor
       (lambda (job-id job)
         (unless (nshell.domain.execution:job-completed-p job)
           (push job-id active-job-ids)))))
    (setf active-job-ids (nreverse active-job-ids))
    (cond
      ((null active-job-ids)
       (setf *exit-warning-state* nil)
       nil)
      ((and *exit-warning-state*
            (eq job-monitor (first *exit-warning-state*))
            (equal active-job-ids (second *exit-warning-state*)))
       (setf *exit-warning-state* nil)
       nil)
      (t
       (setf *exit-warning-state* (list job-monitor active-job-ids))
       (format nil "exit: there are active jobs. Exit again to leave.~%")))))

(define-builtin %builtin-exit (context args) ()
  (cond
    ((> (length args) 1)
     (values "exit: too many arguments~%" 1))
    (t
     (multiple-value-bind (status valid-p)
         (if args
             (%parse-exit-status (first args))
             (values (shell-context-last-exit-code context) t))
       (if valid-p
           (progn
             (setf (shell-context-last-exit-code context) status)
             (let ((warning
                     (%exit-warning-message-if-required
                      (shell-context-job-monitor context))))
               (if warning
                   (values warning status)
                   (progn
                     (%stop-shell-context context)
                     (values nil status)))))
           (progn
             (setf (shell-context-last-exit-code context) 2)
             (values "exit: numeric argument required~%" 2)))))))

(define-status-builtin %builtin-true 0)

(define-status-builtin %builtin-false 1)

(defvar *exec-exit-function*
  (lambda (program) (sb-ext:quit :unix-status (funcall program)))
  "Function that exec calls with the exec'd program, a function of no
arguments that runs it and returns its exit status, to run it and end the
shell. The --json runner binds it so exec ends the run, not the process,
before the envelope is printed.")

(defvar *subshell-exit-function* nil
  "Inside a subshell-like context (a pipeline stage, a process substitution's
stage, or a command substitution), a function that takes the exec'd program as
*EXEC-EXIT-FUNCTION* does, runs it, and ends only that context: see
CALL-WITH-SUBSHELL-EXIT. NIL outside every such context.")

(defun call-with-subshell-exit (thunk on-exit)
  "Call THUNK as a subshell-like context and return its values. While THUNK
runs, *SUBSHELL-EXIT-FUNCTION* runs the program it is given through
RUN-DELIVERING-CAPTURED-OUTPUT, so no output the context produced stays
behind, unwinds THUNK, running its cleanup, and then returns the values of
ON-EXIT called with the program's status. The innermost context wins, so a
context nested in another one ends alone. *EXEC-EXIT-FUNCTION* decides whether
exec uses it; the default quits the process instead."
  (let* ((tag (list :subshell-exit))
         (status (catch tag
                   (return-from call-with-subshell-exit
                     (let ((*output-captures* (cons :subshell *output-captures*))
                           (*subshell-exit-function*
                             (lambda (program)
                               (throw tag (run-delivering-captured-output program)))))
                       (funcall thunk))))))
    (funcall on-exit status)))

(defun %exec-and-exit (command args)
  (funcall *exec-exit-function*
           (lambda () (nshell.infrastructure.acl:run-external-exec command args))))

(define-builtin %builtin-exec (context args) (context)
  (if args
      (let* ((node (%assistant-command-stage-node
                    (nshell.domain.parsing:make-command-node (first args) (rest args))))
             ;; %exec-and-exit runs the external program.
             (gate (%assistant-execution-gate
                    context node
                    :path :stage
                    :resolve (assistant-command-resolver
                              context :stage-kinds (list (cons node :external))))))
        (if gate
            (values (first gate) (second gate))
            (progn
              (ignore-errors
                (nshell.feature.assistant:assistant-model-stop))
              (%exec-and-exit (first args) (rest args)))))
      (%builtin-usage "exec" "exec command [args...]")))

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

(defun %find-builtin-help-entry (command)
  (find command
        (nshell.domain.completion:builtin-help-entries)
        :key (lambda (entry) (getf entry :command))
        :test #'string=))

(defun %builtin-help (context args)
  (declare (ignore context))
  (if args
      (let ((entry (%find-builtin-help-entry (first args))))
        (if entry
            (values (%builtin-help-entry-output entry) 0)
            (values (format nil "help: no help for ~a~%" (first args)) 1)))
      (values (%builtin-help-overview-output) 0)))

(defun context-current-directory (context)
  "Return the directory pwd prints in CONTEXT."
  (%logical-current-directory (shell-context-environment context)
                              (ignore-errors (host-kit:getcwd))))
