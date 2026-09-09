(in-package #:nshell.presentation)

(defun reset-ai-session ()
  (setf *assistant-turn-generation*
          (nshell.feature.assistant:next-assistant-turn-generation
           *assistant-turn-generation*)
        *assistant-turn-started-at* nil
        *last-assistant-model-event* nil
        *assistant-model-event-handler* nil
        *assistant-request-kind* nil
        *assistant-explain-candidates* nil
        *assistant-explain-candidate-index* 0
        *assistant-command-origin* :typed
        *assistant-command-confirmed-p* nil
        *agent-session* nil
        *input-state* (make-repl-input-state))
  (ignore-errors
    (nshell.feature.assistant:assistant-model-poll
     *assistant-turn-generation*))
  (nshell.feature.assistant:reset-assistant-usage)
  (clear-rendered-transient-panel)
  (reset-rendered-prompt-state)
  t)
