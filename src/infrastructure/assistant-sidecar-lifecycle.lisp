(in-package #:nshell.feature.assistant)

(defun %assistant-sidecar-dead-p (state)
  (or (assistant-sidecar-state-dead-p state)
      (and (assistant-sidecar-state-handle state)
           (not (nshell.infrastructure.acl:sidecar-alive-p
                 (assistant-sidecar-state-handle state))))))

(defun %assistant-sidecar-mark-dead (state reason)
  (setf (assistant-sidecar-state-dead-p state) t
        (assistant-sidecar-state-dead-reason state) reason)
  t)
