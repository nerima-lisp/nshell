(in-package #:nshell.application)

(declaim (notinline nshell.infrastructure.acl:process-substitution-resource-path
                    nshell.infrastructure.acl:process-substitution-resource-fd))

(declaim (special nshell.infrastructure.acl:*external-command-timeout*))

;;; Pipeline stage execution and command expansion.
;;; execute-ast-in-context (defined in execute-pipeline-control.lisp) is
;;; forward-referenced by %execute-pipeline-stage-in-context and
;;; execute-command-node-in-context for builtin/function dispatch.

(defun %process-substitution-spec-p (value)
  (and (stringp value)
       (>= (length value) 3)
       (or (char= (char value 0) #\<)
           (char= (char value 0) #\>))
       (char= (char value 1) #\()
       (char= (char value (1- (length value))) #\))))

(defun %process-substitution-direction (value)
  (if (char= (char value 0) #\<)
      :input
      :output))

(defun %process-substitution-error (message)
  (format nil "nshell: process substitution: ~a~%" message))

(defun %process-substitution-inner-commands (ast)
  (cond
    ((nshell.domain.parsing:command-node-p ast)
     (list ast))
    ((nshell.domain.parsing:pipeline-node-p ast)
     (nshell.domain.parsing:pipeline-node-commands ast))
    (t
     nil)))

(defun %release-process-substitution-resources (resources)
  (dolist (resource resources)
    (ignore-errors
      (nshell.infrastructure.acl:release-process-substitution-fd resource))))

(defun %finish-process-substitution-resources (resources)
  (dolist (resource resources)
    (ignore-errors
      (nshell.infrastructure.acl:wait-process-substitution resource))
    (ignore-errors
      (nshell.infrastructure.acl:release-process-substitution-fd resource))))

(defun %abort-process-substitution-resources (resources)
  (dolist (resource resources)
    (ignore-errors
      (nshell.infrastructure.acl:close-process-substitution resource))))

(defun %process-substitution-resource-fds (resources)
  (mapcar #'nshell.infrastructure.acl:process-substitution-resource-fd
          resources))

(defun %materialize-process-substitution-in-context (context value)
  (let* ((direction (%process-substitution-direction value))
         (body (subseq value 2 (1- (length value))))
         (parse-result (nshell.domain.parsing:parse-command-line body))
         (ast (nshell.domain.parsing:parse-result-ast parse-result)))
    (unless (nshell.domain.parsing:parse-complete-p parse-result)
      (return-from
       %materialize-process-substitution-in-context
       (values nil nil (%process-substitution-error "the command is incomplete"))))
    (let ((commands (%process-substitution-inner-commands ast)))
      (unless (and
               commands
               (every
                (lambda (command)
                  (nshell.domain.parsing:command-node-p command))
                commands))
        (return-from
         %materialize-process-substitution-in-context
         (values
          nil
          nil
          (%process-substitution-error "the command must be a command or pipeline"))))
      (multiple-value-bind (expanded-commands error nested-resources) (%expand-command-nodes-in-context
                                                                       context
                                                                       commands)
        (when nested-resources
          (%abort-process-substitution-resources nested-resources)
          (return-from
           %materialize-process-substitution-in-context
           (values
            nil
            nil
            (%process-substitution-error
             "nested process substitutions are not supported"))))
        (when error
          (return-from
           %materialize-process-substitution-in-context
           (values nil nil error)))
        (when (some
               (lambda (command)
                 (%shell-internal-command-p context command))
               expanded-commands)
          (return-from
           %materialize-process-substitution-in-context
           (values nil nil (%process-substitution-error "the command must be external"))))
        (let* ((redirect-split (%extract-pipeline-redirects expanded-commands))
               (clean-commands
                (nshell.domain.parsing:command-list-redirect-split-result-clean-commands
                 redirect-split))
               (redirects
                (nshell.domain.parsing:command-list-redirect-split-result-redirects
                 redirect-split)))
          (handler-case (let ((resource
                               (nshell.infrastructure.acl:spawn-process-substitution
                                direction
                                clean-commands
                                :redirects
                                redirects)))
                          (values
                           (nshell.infrastructure.acl:process-substitution-resource-path
                            resource)
                           resource
                           nil))
            (error (condition)
              (values nil nil (%process-substitution-error (princ-to-string condition))))))))))

(defun %expand-command-args-in-context (context command-node)
  (let ((args nil)
        (resources nil)
        (here-doc-target-p nil))
    (handler-case
        (progn
          (dolist (arg (nshell.domain.parsing:command-node-args command-node))
            (let* ((value (nshell.domain.parsing:arg-value arg))
                   (literal-p (nshell.domain.parsing:arg-here-doc-literal-p arg)))
              (cond
                ((and here-doc-target-p (not literal-p))
                 (setf args
                       (nconc
                        args
                        (list
                         (nshell.domain.parsing:make-command-arg
                          (%expand-here-doc-body-in-context context value))))))
                ((and (not literal-p)
                      (null (nshell.domain.parsing:arg-quote-style arg))
                      (%process-substitution-spec-p value))
                 (multiple-value-bind (path resource error)
                     (%materialize-process-substitution-in-context context value)
                   (when error
                     (%abort-process-substitution-resources resources)
                     (return-from %expand-command-args-in-context
                       (values nil nil error)))
                   (setf args
                         (nconc
                          args
                          (list (nshell.domain.parsing:make-command-arg path))))
                   (push resource resources)))
                (t
                 (setf args
                       (nconc
                        args
                        (mapcar #'nshell.domain.parsing:make-command-arg
                                (%expand-source-arg-in-context context arg))))))
              (setf here-doc-target-p
                    (not (null (member value '("<<" "<<-") :test #'string=))))))
          (values args (nreverse resources) nil))
      (nshell.domain.expansion:parameter-expansion-error (condition)
        (%abort-process-substitution-resources resources)
        (values nil nil
                (format nil "nshell: ~a~%" condition))))))

;; -- Command name expansion (fixes unexpanded $VAR in command position) --------

(defun %expand-command-node-in-context (context command-node)
  "Expand the command name and all args in COMMAND-NODE under CONTEXT.
Returns (expanded-node nil) on success or (nil error-string) when the
command name expands to zero or multiple fields (ambiguous)."
  (handler-case
      (let* ((alias-expanded (expand-command-alias-node
                              command-node
                              (shell-context-alias-table context)))
             (environment (shell-context-environment context)))
        (multiple-value-bind (command error)
            (%expand-command-name-from-fragments alias-expanded environment)
          (if error
              (values nil error)
              (multiple-value-bind (args resources arg-error)
                  (%expand-command-args-in-context context alias-expanded)
                (if arg-error
                    (values nil arg-error nil)
                    (values (nshell.domain.parsing:make-command-node
                             command
                             args)
                            nil
                            resources))))))
    (nshell.domain.expansion:parameter-expansion-error (condition)
      (values nil (format nil "nshell: ~a~%" condition) nil))))

(defun %expand-command-nodes-in-context (context commands)
  "Expand all COMMANDS; return (expanded-list nil) or (nil error-string) on first error."
  (let ((expanded-commands nil)
        (resources nil))
    (dolist (command commands)
      (multiple-value-bind (expanded error command-resources)
          (%expand-command-node-in-context context command)
        (if error
            (progn
              (%abort-process-substitution-resources resources)
              (return-from %expand-command-nodes-in-context
                (values nil error nil)))
            (progn
              (push expanded expanded-commands)
              (setf resources (nconc resources command-resources))))))
    (values (nreverse expanded-commands) nil resources)))

;; -- Internal vs external dispatch -------------------------------------------

(defun %shell-internal-command-p (context command-node)
  (let ((command (nshell.domain.parsing:command-node-command command-node)))
    (or (lookup-builtin command)
        (nth-value 1 (gethash command (shell-context-function-table context))))))

(progn
  (defun %record-pipeline-statuses (context statuses)
    "Expose per-stage exit codes through the non-exported pipestatus binding."
    (let ((statuses (or statuses (list 0)))
          (environment (shell-context-environment context)))
      (when environment
        (setf (shell-context-environment context)
              (nshell.domain.environment:env-set-values
               environment
               "pipestatus"
               (mapcar (lambda (status) (princ-to-string (or status 0)))
                       statuses)
               nil)))
      statuses))
  (defun %source-pipeline-exit-status (statuses pipefail-p)
    (if pipefail-p
        (or (find-if (lambda (status) (not (zerop status))) statuses) 0)
        (or (car (last statuses)) 0))))

(defun %execute-pipeline-stage-in-context (context command-node input redirects)
  (if (%shell-internal-command-p context command-node)
      (if input
          (with-input-from-string (*standard-input* input)
            (%execute-clean-command-node-in-context context command-node redirects))
          (%execute-clean-command-node-in-context context command-node redirects))
      (%execute-external-pipeline-stage command-node input redirects)))

(defun %execute-source-pipeline-in-context (context commands redirects)
  (let ((input nil)
        (statuses nil))
    (loop for command in commands
          for command-redirects in redirects
          do (multiple-value-bind (output exit-code)
                 (%execute-pipeline-stage-in-context context command input command-redirects)
               (setf input output)
               (push (or exit-code 0) statuses)))
    (let ((ordered-statuses (nreverse statuses)))
      (%record-pipeline-statuses context ordered-statuses)
      (values input
              (%source-pipeline-exit-status
               ordered-statuses
               (shell-context-pipefail-p context))))))

;; -- Clean command node execution --------------------------------------------

(defun %execute-clean-command-node-in-context (context clean-command redirects)
  (let* ((command (nshell.domain.parsing:command-node-command clean-command))
         (args (%line-command-args clean-command))
         (redirect-output-p (nshell.domain.parsing:redirect-output-p redirects)))
    (unwind-protect
         (let ((redirect-error
                 (when redirects
                   (handler-case
                       (progn
                         (%apply-context-redirects context redirects)
                         nil)
                     (error (condition)
                       condition)))))
           (if redirect-error
               (progn
                 (format *error-output* "nshell: ~a: ~a~%"
                         command redirect-error)
                 (values nil 1))
               (multiple-value-bind (output code)
                   (%execute-command-by-name-in-context context command args)
                 (when (and redirect-output-p output)
                   (write-string output))
                 (values (and (not redirect-output-p) output) code))))
      (when redirects
        (%restore-context-redirects context)))))

(defun %execute-os-pipeline-with-process-substitutions
    (clean-commands redirects resources &optional (pipefail-p nil))
  (let ((spawned-p nil))
    (unwind-protect
         (handler-case
             (let ((exit-code 0)
                   (pipeline-statuses nil))
               (values
                (with-output-to-string (*standard-output*)
                  (multiple-value-bind (status statuses)
                      (nshell.infrastructure.acl:spawn-pipeline
                       clean-commands
                       :redirects redirects
                       :pipefail-p pipefail-p
                       :preserve-fds
                       (%process-substitution-resource-fds resources)
                       :after-spawn
                       (lambda ()
                         (setf spawned-p t)
                         (%release-process-substitution-resources
                          resources)))
                    (setf exit-code (or status 0)
                          pipeline-statuses (or statuses
                                                (list exit-code)))))
                exit-code
                pipeline-statuses))
           (error (condition)
             (values (format nil "nshell: ~a~%" condition) 127 (list 127))))
      (if spawned-p
          (%finish-process-substitution-resources resources)
          (%abort-process-substitution-resources resources)))))

(defun execute-command-node-in-context (context command-node)
  (multiple-value-bind (expanded error resources)
      (%expand-command-node-in-context context command-node)
    (when error
      (%abort-process-substitution-resources resources)
      (return-from execute-command-node-in-context (values error 127)))
    (let* ((redirect-split (%extract-command-redirects expanded))
           (clean-command
             (nshell.domain.parsing:command-redirect-split-result-clean-command
              redirect-split))
           (redirects
             (nshell.domain.parsing:command-redirect-split-result-redirects
              redirect-split)))
      (if resources
          (if (%shell-internal-command-p context clean-command)
              (progn
                (%abort-process-substitution-resources resources)
                (values
                 (%process-substitution-error
                  "requires an external command")
                 127))
          (%execute-external-pipeline-stage
               clean-command nil redirects resources))
          (if (and (not (%shell-internal-command-p context clean-command))
                   (nshell.domain.parsing:redirects-require-shell-wrapper-p
                    redirects))
              (%execute-external-pipeline-stage
               clean-command nil redirects)
              (%execute-clean-command-node-in-context
               context clean-command redirects))))))

;; -- Pipeline node execution --------------------------------------------------

(defun execute-pipeline-node-in-context (context pipeline-node)
  (let ((commands (nshell.domain.parsing:pipeline-node-commands pipeline-node)))
    (multiple-value-bind (expanded-commands error resources)
        (%expand-command-nodes-in-context context commands)
      (when error
        (%abort-process-substitution-resources resources)
        (return-from execute-pipeline-node-in-context (values error 127)))
      (let* ((redirect-split (%extract-pipeline-redirects expanded-commands))
             (clean-commands
              (nshell.domain.parsing:command-list-redirect-split-result-clean-commands
               redirect-split))
             (redirects
              (nshell.domain.parsing:command-list-redirect-split-result-redirects
               redirect-split)))
        (if resources
            (if (or (eq :cps (shell-context-execution-strategy context))
                    (some (lambda (cmd) (%shell-internal-command-p context cmd))
                          clean-commands))
                (progn
                  (%abort-process-substitution-resources resources)
                  (values
                   (%process-substitution-error
                    "is not supported for internal or CPS pipelines")
                   127))
                (multiple-value-bind (output exit-code statuses)
                    (%execute-os-pipeline-with-process-substitutions
                     clean-commands redirects resources
                     (shell-context-pipefail-p context))
                  (%record-pipeline-statuses context statuses)
                  (values output exit-code)))
            (if (or (eq :cps (shell-context-execution-strategy context))
                    (some (lambda (cmd) (%shell-internal-command-p context cmd))
                          clean-commands))
                (%execute-source-pipeline-in-context
                 context clean-commands redirects)
                (let ((output nil)
                      (exit-code 0)
                      (pipeline-statuses nil))
                  (progn
                    (setf output
                          (with-output-to-string (*standard-output*)
                            (multiple-value-bind (status statuses)
                                (nshell.infrastructure.acl:spawn-pipeline
                                 clean-commands
                                 :redirects redirects
                                 :pipefail-p
                                 (shell-context-pipefail-p context))
                              (setf exit-code (or status 0)
                                    pipeline-statuses
                                    (or statuses (list exit-code))))))
                    (%record-pipeline-statuses context pipeline-statuses)
                    (values output exit-code)))))))))

;; -- Public pipeline API (OS-level) -------------------------------------------

(defun execute-pipeline (pipeline-ast)
  "Execute a pipeline AST using OS-level pipes. Returns the last process exit code."
  (let ((commands (if (nshell.domain.parsing:pipeline-node-p pipeline-ast)
                      (nshell.domain.parsing:pipeline-node-commands pipeline-ast)
                      (list pipeline-ast))))
    (let ((context (%make-pipeline-shell-context)))
      (multiple-value-bind (expanded-commands error resources)
          (%expand-command-nodes-in-context context commands)
        (when error
          (%abort-process-substitution-resources resources)
          (write-string error *error-output*)
          (return-from execute-pipeline 127))
        (let* ((redirect-split (%extract-pipeline-redirects expanded-commands))
               (clean-commands
                 (nshell.domain.parsing:command-list-redirect-split-result-clean-commands
                  redirect-split))
               (redirects
                 (nshell.domain.parsing:command-list-redirect-split-result-redirects
                  redirect-split)))
          (if (and resources
                   (some (lambda (cmd) (%shell-internal-command-p context cmd))
                         clean-commands))
              (progn
                (%abort-process-substitution-resources resources)
                (write-string
                 (%process-substitution-error
                  "is not supported for internal commands")
                 *error-output*)
                127)
              (if resources
                  (nth-value
                   1
                   (%execute-os-pipeline-with-process-substitutions
                    clean-commands redirects resources
                    (shell-context-pipefail-p context)))
                  (nshell.infrastructure.acl:spawn-pipeline
                   clean-commands
                   :redirects redirects
                   :pipefail-p (shell-context-pipefail-p context)))))))))

(defun execute-pipeline-use-case (pipeline dispatcher)
  (when dispatcher
    (publish-event dispatcher
                   (nshell.domain.events:make-pipeline-started-event pipeline nil)))
  (let ((exit-code (or (execute-pipeline pipeline) 0)))
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-pipeline-completed-event pipeline exit-code)))
    exit-code))
