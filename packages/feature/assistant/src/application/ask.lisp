(in-package #:nshell.feature.assistant)

(defun next-assistant-turn-generation (generation)
  (1+ (or generation 0)))

(defun make-assistant-user-payload (message &key context)
  (append
   (list (cons "type" "user")
         (cons "message"
               (list (cons "role" "user")
                     (cons "content" message))))
   (when context
     (list (cons "context"
                 (assistant-context-payload context))))))
