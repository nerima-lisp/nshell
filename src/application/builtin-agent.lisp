(in-package #:nshell.application)

(defun %builtin-agent-usage ()
  (%builtin-usage "agent" "agent TASK" 2))

(define-builtin %builtin-agent (context args) ()
  (cond
    ((null args) (%builtin-agent-usage))
    ((not (nshell.infrastructure.terminal:interactive-terminal-p))
     (values (format nil "agent: interactive terminal required~%") 2))
    ((not (functionp *agent-start-handler*))
     (values (format nil "agent: interactive mode is unavailable~%") 2))
    (t
     (handler-case
         (progn
           (funcall *agent-start-handler*
                    context
                    (%string-join args " ")
                    :max-steps (agent-max-steps-from-context context))
           (values nil 0))
       (error (condition)
         (values (format nil "agent: ~a~%" condition) 2))))))
