(in-package #:nshell.presentation)

(defun execute-ast (ast)
  (cond
    ((nshell.domain.parsing:sequence-node-p ast)
     (nth-value 1
                (%with-repl-shell-context (context)
                  (nshell.application:execute-ast-in-context context ast))))
    ((nshell.domain.parsing:command-node-p ast)
     (execute-command-node ast))
    ((or (nshell.domain.parsing:pipeline-node-p ast)
         (nshell.domain.parsing:if-node-p ast)
         (nshell.domain.parsing:for-node-p ast)
         (nshell.domain.parsing:while-node-p ast)
         (nshell.domain.parsing:case-node-p ast)
         (nshell.domain.parsing:begin-end-node-p ast))
     (nth-value 1
                (%with-repl-shell-context (context)
                  (nshell.application:execute-ast-in-context context ast))))
    (t
     (format t "nshell: cannot execute~%")
     1)))
