;;; REPL polling bridge for assistant model events
(in-package #:nshell.presentation)

(defun %assistant-response-deadline-expired-p (now)
  (and *assistant-last-event-at*
       (>= (- now *assistant-last-event-at*)
           (* nshell.feature.assistant:+assistant-sidecar-response-timeout-seconds+
              internal-time-units-per-second))))

(defun %poll-assistant-model-event ()
  (let* ((now (boundary-monotonic))
         (result
           (if (%assistant-response-deadline-expired-p now)
               (progn
                 (nshell.feature.assistant:assistant-model-stop)
                 (list :status :event
                       :value
                       (nshell.feature.assistant:make-assistant-model-error-event
                        *assistant-turn-generation*
                        (format nil
                                "AI 応答がタイムアウトしました（~D 秒）"
                                nshell.feature.assistant:+assistant-sidecar-response-timeout-seconds+))))
               (nshell.feature.assistant:assistant-model-poll
                *assistant-turn-generation*))))
    (when (eq :event
              (nshell.feature.assistant:assistant-boundary-status result))
      (let ((event (nshell.feature.assistant:assistant-boundary-value result)))
        (when (and (nshell.feature.assistant:assistant-model-event-p event)
                   (eql *assistant-turn-generation*
                        (nshell.feature.assistant:assistant-model-event-generation
                         event)))
          (setf *assistant-last-event-at* now)
          event)))))
