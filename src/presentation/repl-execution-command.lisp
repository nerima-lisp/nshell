(in-package #:nshell.presentation)

(defun %reap-background-jobs-for-command (cmd)
  (when (member cmd '("fg" "bg" "jobs" "disown" "wait" "kill")
              :test #'string=)
    (reap-background-jobs)))

(defun execute-builtin (ast)
  (let* ((cmd (nshell.domain.parsing:command-node-command ast))
         (args (nshell.domain.parsing:command-node-arg-values ast))
         (handler (nshell.application:lookup-builtin cmd)))
    (if handler
        (progn
          (%reap-background-jobs-for-command cmd)
          (multiple-value-bind (output code)
              (%with-repl-shell-context (context)
                (funcall handler context args))
            (declare (ignore output))
            (values t code)))
        (values nil nil))))

(defun execute-command-node (ast)
  (let* ((expanded-ast (nshell.application:expand-command-alias-node
                        ast
                        *aliases*))
         (cmd (nshell.domain.parsing:command-node-command expanded-ast)))
    (%reap-background-jobs-for-command cmd)
    (nth-value 1
               (%with-repl-shell-context (context)
                 (nshell.application:execute-ast-in-context
                  context
                  expanded-ast)))))
