(in-package #:nshell.application)

;;; Background pipeline stage helpers.

(defun %background-process-pid (process)
  "Return the OS PID of a background PROCESS object, or NIL if unavailable."
  (ignore-errors (sb-ext:process-pid process)))

(defun %register-background-job (context processes command-line)
  "Register PROCESSES as a background job in CONTEXT's monitor and process registry.
PROCESSES is a single process object (command) or a list (pipeline).
Returns the job ID, or NIL when PIDs cannot be obtained."
  (let* ((proc-list (if (listp processes) processes (list processes)))
         (pids (delete nil (mapcar #'%background-process-pid proc-list))))
    (when pids
      (let ((job-id (nshell.domain.job-control:monitor-add-background-job
                     (shell-context-job-monitor context)
                     pids
                     command-line
                     :pipefail-p (shell-context-pipefail-p context))))
        (%store-shell-process-registry-entry context job-id processes)
        (when (shell-context-environment context)
          (setf (shell-context-environment context)
                (nshell.domain.environment:env-set
                 (shell-context-environment context)
                 "!"
                 (princ-to-string (car (last pids)))
                 nil)))
        job-id))))

(defun %spawn-background-pipeline-in-context (context command)
  (multiple-value-bind (expanded-commands error resources)
      (%expand-command-nodes-in-context
       context
       (nshell.domain.parsing:pipeline-node-commands command))
    (cond
      (error
       (%abort-process-substitution-resources resources)
       (values error 127))
      (resources
       (%abort-process-substitution-resources resources)
       (values
        (%process-substitution-error
         "is not supported in background jobs")
        127))
      (t
       (let* ((redirect-split (%extract-pipeline-redirects expanded-commands))
              (clean-commands
                (nshell.domain.parsing:command-list-redirect-split-result-clean-commands
                 redirect-split))
              (redirects
                (nshell.domain.parsing:command-list-redirect-split-result-redirects
                 redirect-split))
              (clean-pipeline (nshell.domain.parsing:make-pipeline-node
                               clean-commands))
              (processes (nshell.infrastructure.acl:spawn-pipeline-async
                          clean-commands :redirects redirects))
              (command-line (nshell.domain.parsing:ast-node->command-line
                             clean-pipeline)))
         (when processes
           (%register-background-job context processes command-line))
         (values nil 0))))))

(defun %spawn-background-command-in-context (context command)
  (multiple-value-bind (expanded-command error resources)
      (%expand-command-node-in-context context command)
    (cond
      (error
       (%abort-process-substitution-resources resources)
       (values error 127))
      (resources
       (%abort-process-substitution-resources resources)
       (values
        (%process-substitution-error
         "is not supported in background jobs")
        127))
      (t
       (let* ((redirect-split (%extract-command-redirects expanded-command))
              (clean-command
                (nshell.domain.parsing:command-redirect-split-result-clean-command
                 redirect-split))
              (redirects
                (nshell.domain.parsing:command-redirect-split-result-redirects
                 redirect-split))
              (cmd (nshell.domain.parsing:command-node-command clean-command))
              (args (nshell.domain.parsing:command-node-arg-values clean-command))
              (command-line (nshell.domain.parsing:ast-node->command-line
                             clean-command))
              (process (nshell.infrastructure.acl:spawn-async
                        cmd args :redirects redirects)))
         (when process
           (%register-background-job context process command-line))
         (values nil 0))))))

(defun %spawn-background-node-in-context (context command)
  "Spawn COMMAND (command-node or pipeline-node) asynchronously and register a job."
  (cond
    ((nshell.domain.parsing:pipeline-node-p command)
     (%spawn-background-pipeline-in-context context command))
    ((nshell.domain.parsing:command-node-p command)
     (%spawn-background-command-in-context context command))
    (t
     (values "nshell: cannot run construct in background~%" 1))))
