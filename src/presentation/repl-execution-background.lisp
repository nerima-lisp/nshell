(in-package #:nshell.presentation)

(defun %expand-command-args (cmd environment)
  (loop for arg in (nshell.domain.parsing:command-node-args cmd)
        for value = (nshell.domain.parsing:arg-value arg)
        for style = (nshell.domain.parsing:arg-quote-style arg)
        append (nshell.domain.expansion:expand-command-name-fields-by-quote-style
                value style environment)))

(defun %prepare-command-node (cmd)
  (let* ((environment (ensure-environment))
         (command (nshell.domain.parsing:command-node-command cmd))
         (style (nshell.domain.parsing:command-node-command-quote-style cmd))
         (expanded (nshell.domain.expansion:expand-command-name-fields-by-quote-style
                    command style environment))
         (non-empty (remove "" expanded :test #'string=)))
    (if (= 1 (length non-empty))
        (multiple-value-bind (args redirects)
            (extract-redirects
             (%expand-command-args cmd environment))
          (values (nshell.domain.parsing:make-command-node
                   (first non-empty)
                   args)
                  redirects
                  nil))
        (values nil
                nil
                (format nil "nshell: ~a: command name expansion produced ~d fields~%"
                        (nshell.domain.parsing:command-node-command cmd)
                        (length non-empty))))))

(defun %prepare-pipeline-node (pipeline)
  (let ((prepared '())
        (pipeline-redirects '()))
    (dolist (cmd (nshell.domain.parsing:pipeline-node-commands pipeline))
      (multiple-value-bind (clean-cmd redirects error)
          (%prepare-command-node cmd)
        (when error
          (return-from %prepare-pipeline-node
            (values nil nil error)))
        (push clean-cmd prepared)
        (push redirects pipeline-redirects)))
    (values (nreverse prepared)
            (nreverse pipeline-redirects)
            nil)))

(defun %background-job-node (ast)
  (cond
    ((or (nshell.domain.parsing:command-node-p ast)
         (nshell.domain.parsing:pipeline-node-p ast))
     ast)
    ((nshell.domain.parsing:sequence-node-p ast)
     (first (nshell.domain.parsing:sequence-node-commands ast)))
    (t nil)))

(defun %register-background-job (ast procs)
  (let* ((proc-list (if (listp procs) procs (list procs)))
         (pids (mapcar #'sb-ext:process-pid proc-list))
         (pgid (first pids))
         (node (%background-job-node ast))
         (cmds (if (nshell.domain.parsing:pipeline-node-p node)
                   (nshell.domain.parsing:pipeline-node-commands node)
                   (list node)))
         (dom-cmds
           (mapcar (lambda (cmd)
                     (nshell.domain.execution:make-command
                      (nshell.domain.parsing:command-node-command cmd)
                      (nshell.domain.parsing:command-node-arg-values cmd)))
                   cmds))
         (pipe (apply #'nshell.domain.execution:make-pipeline dom-cmds))
         (job (nshell.domain.execution:make-job 0 pipe))
         (jid (nshell.domain.job-control:monitor-add-job
               nshell.application:*job-monitor* job)))
    (setf (nshell.domain.execution:job-command-line job)
          (nshell.domain.parsing:ast-node->command-line ast))
    (setf (nshell.domain.execution:job-pids job) pids)
    (setf (nshell.domain.execution:job-pgid job) pgid)
    (setf (nshell.domain.execution:job-background-p job) t)
    (nshell.domain.job-control:monitor-update
     nshell.application:*job-monitor* jid :running)
    (setf (gethash jid nshell.presentation::*proc-registry*) procs)
    (format t "[~d] ~d~%" jid pgid)))
