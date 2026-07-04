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
         (style (nshell.domain.parsing:command-node-command-quote-style cmd)))
    (multiple-value-bind (expanded error)
        (nshell.domain.expansion:expand-command-name-by-quote-style
         command style environment)
      (if error
          (values nil nil error)
          (multiple-value-bind (args redirects)
              (extract-redirects
               (%expand-command-args cmd environment))
            (values (nshell.domain.parsing:make-command-node
                     expanded
                     args)
                    redirects
                    nil))))))

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

(defun %register-background-job (ast procs)
  (let* ((proc-list (if (listp procs) procs (list procs)))
         (pids (mapcar #'sb-ext:process-pid proc-list))
         (pgid (first pids))
         (jid (nshell.domain.job-control:monitor-add-background-job
               nshell.application:*job-monitor*
               pids
               (nshell.domain.parsing:ast-node->command-line ast))))
    (when jid
      (setf (gethash jid nshell.presentation::*proc-registry*) procs)
      (format t "[~d] ~d~%" jid pgid))))
