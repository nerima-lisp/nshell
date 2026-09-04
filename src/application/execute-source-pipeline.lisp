(in-package #:nshell.application)

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
      (or (car (last statuses)) 0)))

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
