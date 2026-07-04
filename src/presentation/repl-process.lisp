;;; REPL process and background job helpers
(in-package #:nshell.presentation)

(defparameter *background-proc-alive-p* #'sb-ext:process-alive-p
  "Function used to determine whether a background process is still running.")

(defparameter *background-proc-exit-code*
  #'nshell.infrastructure.acl:process-exit-status-code
  "Function used to read the shell-compatible exit code from a completed background process.")

(defun reap-background-jobs ()
  (let ((completed-jobs nil))
    (maphash (lambda (jid entry)
               (let ((procs (cond
                              ((null entry) nil)
                              ((listp entry) entry)
                              (t (list entry)))))
                 (when (and entry
                            (not (some *background-proc-alive-p* procs)))
                   (nshell.domain.job-control:complete-job
                    nshell.application:*job-monitor* jid
                    (let ((proc (car (last procs))))
                      (or (and proc (funcall *background-proc-exit-code* proc))
                          0)))
                   (push jid completed-jobs))))
             *proc-registry*)
    (dolist (jid completed-jobs)
      (remhash jid *proc-registry*))))
