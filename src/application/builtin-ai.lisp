(in-package #:nshell.application)

(defvar *ai-reset-handler* nil)

(defun %builtin-ai-usage ()
  (%builtin-usage "ai" "ai status|reset|log [N]|set [KEY VALUE]" 2))

(defun %ai-display-value (value)
  (if (or (null value) (equal "" value))
      "none"
      (princ-to-string value)))

(defun %ai-status-output ()
  (let* ((snapshot
           (nshell.feature.assistant:assistant-boundary-status-snapshot
            (nshell.feature.assistant:assistant-model-boundary)))
         (usage nshell.feature.assistant:*assistant-usage*)
         (state (getf snapshot :state)))
    (with-output-to-string (stream)
      (format stream "AI sidecar: ~a~%"
              (case state
                (:running "running")
                (:not-started "not started")
                (:unavailable "unavailable")
                (otherwise "unknown")))
      (when (getf snapshot :reason)
        (format stream "Reason: ~a~%" (getf snapshot :reason)))
      (format stream "Claude version: ~a~%"
              (%ai-display-value (getf snapshot :version)))
      (format stream "Turns: ~d~%"
              (nshell.feature.assistant:assistant-usage-turns usage))
      (format stream "Tokens: input ~d, output ~d~%"
              (nshell.feature.assistant:assistant-usage-input-tokens usage)
              (nshell.feature.assistant:assistant-usage-output-tokens usage))
      (format stream "Effort: ~a~%"
              (%ai-display-value
               (nshell.feature.assistant:assistant-setting-value :effort)))
      (format stream "Model: ~a~%"
              (%ai-display-value
               (nshell.feature.assistant:assistant-setting-value :model)))
      (format stream "Max steps: ~a~%"
              (%ai-display-value
               (nshell.feature.assistant:assistant-setting-value :max-steps)))
      (format stream "Budget: ~a~%"
              (%ai-display-value
               (nshell.feature.assistant:assistant-setting-value :budget)))
      (when (nshell.feature.assistant:assistant-usage-last-rate-limit-status
             usage)
        (format stream "Rate limit: ~a~%"
                (nshell.feature.assistant:assistant-usage-last-rate-limit-status
                 usage))))))

(defun %ai-settings-output ()
  (with-output-to-string (stream)
    (dolist (entry (nshell.feature.assistant:assistant-setting-list))
      (format stream "~a: ~a~%"
              (car entry)
              (%ai-display-value (cdr entry))))))

(defun %ai-log-count (value)
  (handler-case
      (let ((count (parse-integer value :junk-allowed nil)))
        (and (plusp count) count))
    (error () nil)))

(defun %ai-log-output (count)
  (multiple-value-bind (lines present-p)
      (nshell.feature.assistant:assistant-audit-tail count)
    (if present-p
        (if lines
            (format nil "~{~a~%~}" lines)
            "ai: audit log is empty~%")
        "ai: audit log does not exist yet~%")))

(define-builtin %builtin-ai (context args) (context)
  (cond
    ((null args)
     (%builtin-ai-usage))
    ((and (string-equal (first args) "status")
          (null (rest args)))
     (if (nshell.infrastructure.terminal:interactive-terminal-p)
         (values (%ai-status-output) 0)
         (values "AI is disabled in non-interactive sessions~%" 0)))
    ((string-equal (first args) "reset")
     (if (rest args)
         (%builtin-ai-usage)
         (progn
           (if (functionp *ai-reset-handler*)
               (funcall *ai-reset-handler*)
               (nshell.feature.assistant:reset-assistant-usage))
           (values "AI conversation reset~%" 0))))
    ((string-equal (first args) "log")
     (let ((count (cond
                    ((null (rest args)) 10)
                    ((and (null (cddr args))
                          (%ai-log-count (second args)))
                     (%ai-log-count (second args))))))
       (if count
           (values (%ai-log-output count) 0)
           (%builtin-ai-usage))))
    ((string-equal (first args) "set")
     (cond
       ((null (rest args))
        (values (%ai-settings-output) 0))
       ((and (second args) (third args) (null (cdddr args)))
        (multiple-value-bind (ok reason)
            (nshell.feature.assistant:set-assistant-setting
             (second args) (third args))
          (if ok
              (values (format nil "~a set to ~a~%"
                              (second args) (third args))
                      0)
              (values (format nil "ai: ~a~%" (or reason "invalid setting"))
                      2))))
       (t (%builtin-ai-usage))))
    (t (%builtin-ai-usage))))
