
(in-package #:nshell.application)

;; -- Internal vs external dispatch -------------------------------------------

(defun %shell-internal-command-p (context command-node)
  (let ((command (nshell.domain.parsing:command-node-command command-node)))
    (or (lookup-builtin command)
        (nth-value 1 (gethash command (shell-context-function-table context))))))

(defun %source-pipeline-required-p (context commands)
  "Return true when COMMANDS must use the source/CPS execution path."
  (or (eq :cps (shell-context-execution-strategy context))
      (not (null
            (some (lambda (command)
                    (%shell-internal-command-p context command))
                  commands)))))

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
            (if (%source-pipeline-required-p context clean-commands)
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
            (if (%source-pipeline-required-p context clean-commands)
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

(defun execute-pipeline (pipeline-ast &key filesystem)
  "Execute a pipeline AST using OS-level pipes. Returns the last process exit code."
  (let ((commands (if (nshell.domain.parsing:pipeline-node-p pipeline-ast)
                      (nshell.domain.parsing:pipeline-node-commands pipeline-ast)
                      (list pipeline-ast))))
    (let ((context (%make-pipeline-shell-context :filesystem filesystem)))
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

(defun execute-pipeline-use-case (pipeline &key filesystem)
  (or (execute-pipeline pipeline :filesystem filesystem) 0))
