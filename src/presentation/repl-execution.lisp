(in-package #:nshell.presentation)

(defun %execute-background-node (node)
  (cond
    ((nshell.domain.parsing:command-node-p node)
     (multiple-value-bind (cmd redirects error)
         (%prepare-command-node node)
       (if error
           (format *error-output* "~a" error)
           (let ((proc (nshell.infrastructure.acl:spawn-async
                        (nshell.domain.parsing:command-node-command cmd)
                        (mapcar #'nshell.domain.parsing:arg-value
                                (nshell.domain.parsing:command-node-args cmd))
                        :redirects redirects)))
             (when proc
               (%register-background-job cmd proc))))))
    ((nshell.domain.parsing:pipeline-node-p node)
     (multiple-value-bind (cmds redirects error)
         (%prepare-pipeline-node node)
       (if error
           (format *error-output* "~a" error)
           (let ((procs (nshell.infrastructure.acl:spawn-pipeline-async
                         cmds
                         :redirects redirects)))
             (when procs
               (%register-background-job
                (nshell.domain.parsing:make-pipeline-node cmds)
                procs))))))
    (t
     (format *error-output* "nshell: cannot run construct in background~%"))))

(defun execute-ast (ast)
  (cond
    ((nshell.domain.parsing:sequence-node-p ast)
     (let ((code 0))
       (dolist (pair (nshell.domain.parsing:sequence-node-command-separator-pairs ast) code)
         (let ((cmd (car pair))
               (sep (cdr pair)))
           (cond
             ((eq :amp sep)
              (%execute-background-node cmd))
             (t
              (setf code (%update-status (or (execute-ast cmd) 0)))
              (when (or (and (eq :and sep) (/= code 0))
                        (and (eq :or sep) (= code 0)))
                (return code))))))))
    ((nshell.domain.parsing:command-node-p ast)
     (execute-command-node ast))
    ((or (nshell.domain.parsing:pipeline-node-p ast)
         (nshell.domain.parsing:if-node-p ast)
         (nshell.domain.parsing:for-node-p ast)
         (nshell.domain.parsing:while-node-p ast)
         (nshell.domain.parsing:case-node-p ast)
         (nshell.domain.parsing:begin-end-node-p ast))
     (nth-value 1
                (%execute-with-repl-shell-context
                 (lambda (context)
                   (nshell.application:execute-ast-in-context context ast)))))
    (t
     (format t "nshell: cannot execute~%")
     1)))
