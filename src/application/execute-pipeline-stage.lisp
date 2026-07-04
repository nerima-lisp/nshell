(in-package #:nshell.application)

;;; Pipeline stage execution and command expansion.
;;; execute-ast-in-context (defined in execute-pipeline-control.lisp) is
;;; forward-referenced by %execute-pipeline-stage-in-context and
;;; execute-command-node-in-context for builtin/function dispatch.

;; -- Command name expansion (fixes unexpanded $VAR in command position) --------

(defun %expand-command-node-in-context (context command-node)
  "Expand the command name and all args in COMMAND-NODE under CONTEXT.
Returns (expanded-node nil) on success or (nil error-string) when the
command name expands to zero or multiple fields (ambiguous)."
  (let* ((alias-expanded (expand-command-alias-node
                          command-node
                          (shell-context-alias-table context)))
         (raw-command (nshell.domain.parsing:command-node-command alias-expanded))
         (command-style (nshell.domain.parsing:command-node-command-quote-style alias-expanded))
         (environment (shell-context-environment context)))
    (multiple-value-bind (command error)
        (nshell.domain.expansion:expand-command-name-by-quote-style
         raw-command command-style environment)
      (if error
          (values nil error)
          (values (nshell.domain.parsing:make-command-node
                   command
                   (%line-command-args-in-context context alias-expanded))
                  nil)))))

(defun %expand-command-nodes-in-context (context commands)
  "Expand all COMMANDS; return (expanded-list nil) or (nil error-string) on first error."
  (let ((expanded-commands nil))
    (dolist (command commands (values (nreverse expanded-commands) nil))
      (multiple-value-bind (expanded error)
          (%expand-command-node-in-context context command)
        (if error
            (return (values nil error))
            (push expanded expanded-commands))))))

;; -- External process execution -------------------------------------------------

(defun %execute-external-pipeline-stage (command-node input redirects)
  "Execute COMMAND-NODE as an external process with optional INPUT string.
Applies REDIRECTS and returns (output exit-code)."
  (let* ((command (nshell.domain.parsing:command-node-command command-node))
         (args (%line-command-args command-node))
         (input-target (nshell.domain.parsing:redirect-input-file-target redirects))
         (opened-input nil)
         (stdin (cond
                  (input-target
                   (setf opened-input
                         (open input-target :direction :input :if-does-not-exist :error)))
                  (input (make-string-input-stream input))
                  (t *standard-input*))))
    (multiple-value-bind (stdout-target stdout-mode stderr-target stderr-mode)
        (nshell.domain.parsing:redirect-output-destinations redirects)
      (let ((merge-stderr-p (or (and (null stdout-target) (null stderr-target))
                                (and stdout-target stderr-target
                                     (equal stdout-target stderr-target)))))
        (handler-case
            (unwind-protect
                 (let ((process
                         (sb-ext:run-program command args
                                             :input stdin
                                             :output :stream
                                             :error (if merge-stderr-p :output :stream)
                                             :wait nil
                                             :search t)))
                   (let ((output (%read-stream-to-string (sb-ext:process-output process)))
                         (errout (when (not merge-stderr-p)
                                   (%read-stream-to-string (sb-ext:process-error process)))))
                     (sb-ext:process-wait process)
                     (cond
                       (merge-stderr-p
                        (when stdout-target
                          (with-open-file (stream stdout-target
                                                  :direction :output
                                                  :if-exists stdout-mode
                                                  :if-does-not-exist :create)
                            (write-string output stream)))
                        (values (and (null stdout-target) output)
                                (nshell.infrastructure.acl:process-exit-status-code process)))
                       (stdout-target
                        (with-open-file (stream stdout-target
                                                :direction :output
                                                :if-exists stdout-mode
                                                :if-does-not-exist :create)
                          (write-string output stream))
                        (when stderr-target
                          (with-open-file (stream stderr-target
                                                  :direction :output
                                                  :if-exists stderr-mode
                                                  :if-does-not-exist :create)
                            (write-string (or errout "") stream)))
                        (values (and (null stderr-target) output)
                                (nshell.infrastructure.acl:process-exit-status-code process)))
                       (stderr-target
                        (with-open-file (stream stderr-target
                                                :direction :output
                                                :if-exists stderr-mode
                                                :if-does-not-exist :create)
                          (write-string (or errout "") stream))
                        (values output
                                (nshell.infrastructure.acl:process-exit-status-code process)))
                       (t
                        (values output
                                (nshell.infrastructure.acl:process-exit-status-code process))))))
              (when opened-input
                (close opened-input)))
          (error (condition)
            (values (format nil "nshell: ~a: ~a~%" command condition) 127)))))))

;; -- Internal vs external dispatch -------------------------------------------

(defun %shell-internal-command-p (context command-node)
  (let ((command (nshell.domain.parsing:command-node-command command-node)))
    (or (lookup-builtin command)
        (nth-value 1 (gethash command (shell-context-function-table context))))))

(defun %execute-pipeline-stage-in-context (context command-node input redirects)
  (if (%shell-internal-command-p context command-node)
      (if input
          (with-input-from-string (*standard-input* input)
            (%execute-clean-command-node-in-context context command-node redirects))
          (%execute-clean-command-node-in-context context command-node redirects))
      (%execute-external-pipeline-stage command-node input redirects)))

(defun %execute-source-pipeline-in-context (context commands redirects)
  (let ((input nil)
        (code 0))
    (loop for command in commands
          for command-redirects in redirects
          do (multiple-value-bind (output exit-code)
                 (%execute-pipeline-stage-in-context context command input command-redirects)
               (setf input output
                     code (or exit-code 0))))
    (values input code)))

;; -- Clean command node execution --------------------------------------------

(defun %execute-clean-command-node-in-context (context clean-command redirects)
  (let* ((command (nshell.domain.parsing:command-node-command clean-command))
         (args (%line-command-args clean-command))
         (redirect-output-p (nshell.domain.parsing:redirect-output-p redirects)))
    (unwind-protect
         (progn
           (when redirects
             (%apply-context-redirects context redirects))
           (multiple-value-bind (output code)
               (%execute-command-by-name-in-context context command args)
             (when (and redirect-output-p output)
               (write-string output))
             (values (and (not redirect-output-p) output) code)))
      (when redirects
        (%restore-context-redirects context)))))

(defun execute-command-node-in-context (context command-node)
  (multiple-value-bind (expanded error)
      (%expand-command-node-in-context context command-node)
    (when error
      (return-from execute-command-node-in-context (values error 127)))
    (let* ((redirect-split (%extract-command-redirects expanded))
           (clean-command
             (nshell.domain.parsing:command-redirect-split-result-clean-command
              redirect-split))
           (redirects
             (nshell.domain.parsing:command-redirect-split-result-redirects
              redirect-split)))
      (%execute-clean-command-node-in-context context clean-command redirects))))

;; -- Pipeline node execution --------------------------------------------------

(defun execute-pipeline-node-in-context (context pipeline-node)
  (let ((commands (nshell.domain.parsing:pipeline-node-commands pipeline-node)))
    (multiple-value-bind (expanded-commands error)
        (%expand-command-nodes-in-context context commands)
      (when error
        (return-from execute-pipeline-node-in-context (values error 127)))
      (let* ((redirect-split (%extract-pipeline-redirects expanded-commands))
             (clean-commands
               (nshell.domain.parsing:command-list-redirect-split-result-clean-commands
                redirect-split))
             (redirects
               (nshell.domain.parsing:command-list-redirect-split-result-redirects
                redirect-split)))
        (if (or (eq :cps (shell-context-execution-strategy context))
                (some (lambda (cmd) (%shell-internal-command-p context cmd))
                      clean-commands))
            (%execute-source-pipeline-in-context context clean-commands redirects)
            (let ((exit-code 0))
              (let ((output
                      (with-output-to-string (*standard-output*)
                        (setf exit-code
                              (or (nshell.infrastructure.acl:spawn-pipeline
                                   clean-commands :redirects redirects)
                                  0)))))
                (values output exit-code))))))))

;; -- Public pipeline API (OS-level) -------------------------------------------

(defun execute-pipeline (pipeline-ast)
  "Execute a pipeline AST using OS-level pipes. Returns the last process exit code."
  (let ((commands (if (nshell.domain.parsing:pipeline-node-p pipeline-ast)
                      (nshell.domain.parsing:pipeline-node-commands pipeline-ast)
                      (list pipeline-ast))))
    (multiple-value-bind (expanded-commands error)
        (%expand-command-nodes-in-context (%make-pipeline-shell-context) commands)
      (when error
        (write-string error *error-output*)
        (return-from execute-pipeline 127))
      (let* ((redirect-split (%extract-pipeline-redirects expanded-commands))
             (clean-commands
               (nshell.domain.parsing:command-list-redirect-split-result-clean-commands
                redirect-split))
             (redirects
               (nshell.domain.parsing:command-list-redirect-split-result-redirects
                redirect-split)))
        (nshell.infrastructure.acl:spawn-pipeline clean-commands :redirects redirects)))))

(defun execute-pipeline-use-case (pipeline dispatcher)
  (when dispatcher
    (publish-event dispatcher
                   (nshell.domain.events:make-pipeline-started-event pipeline nil)))
  (let ((exit-code (or (execute-pipeline pipeline) 0)))
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-pipeline-completed-event pipeline exit-code)))
    exit-code))
