;;; REPL polling bridge for assistant model events
(in-package #:nshell.presentation)

(defun %poll-assistant-model-event ()
  (let ((result
          (nshell.feature.assistant:assistant-model-poll
           *assistant-turn-generation*)))
    (when (eq :event
              (nshell.feature.assistant:assistant-boundary-status result))
      (let ((event (nshell.feature.assistant:assistant-boundary-value result)))
        (when (and (nshell.feature.assistant:assistant-model-event-p event)
                   (eql *assistant-turn-generation*
                        (nshell.feature.assistant:assistant-model-event-generation
                         event)))
          event)))))
