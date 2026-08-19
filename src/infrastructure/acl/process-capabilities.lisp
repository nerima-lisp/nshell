(in-package #:nshell.infrastructure.acl)

;;; The application receives this table at the composition boundary.  Keeping
;;; the SBCL and ACL details here lets execution depend on operations, not on
;;; a particular process implementation.

(defun make-process-fns ()
  "Return the concrete process capability table for a live nshell session."
  (list
   :spawn-pipeline
   (lambda (&rest args)
     (apply #'spawn-pipeline args))
   :spawn-pipeline-async
   (lambda (&rest args)
     (apply #'spawn-pipeline-async args))
   :spawn-process-substitution
   (lambda (&rest args)
     (apply #'spawn-process-substitution args))
   ;; NOTINLINE: these two are defstruct accessors, which SBCL inlines by
   ;; default. An inlined call bypasses the function cell entirely, so a
   ;; test's WITH-TEMPORARY-FUNCTION mock on the accessor's symbol would be
   ;; silently ignored without this declaration.
   :process-substitution-resource-path
   (lambda (resource)
     (locally (declare (notinline process-substitution-resource-path))
       (process-substitution-resource-path resource)))
   :process-substitution-resource-fd
   (lambda (resource)
     (locally (declare (notinline process-substitution-resource-fd))
       (process-substitution-resource-fd resource)))
   :release-process-substitution-fd
   (lambda (resource)
     (release-process-substitution-fd resource))
   :wait-process-substitution
   (lambda (resource)
     (wait-process-substitution resource))
   :close-process-substitution
   (lambda (resource)
     (close-process-substitution resource))
   :spawn-async
   (lambda (&rest args)
     (apply #'spawn-async args))
   :run-program
   (lambda (program args &rest options)
     (apply #'sb-ext:run-program program args options))
   :process-output
   (lambda (process)
     (sb-ext:process-output process))
   :process-error
   (lambda (process)
     (sb-ext:process-error process))
   :process-alive-p
   (lambda (process)
     (sb-ext:process-alive-p process))
   :process-wait
   (lambda (process)
     (sb-ext:process-wait process))
   :process-pid
   (lambda (process)
     (sb-ext:process-pid process))
   :start-stream-copier
   (lambda (&rest args)
     (apply #'start-stream-copier args))
   :wait-process-with-copiers
   (lambda (&rest args)
     (apply #'wait-process-with-copiers args))
   :process-exit-status-code
   (lambda (process)
     (process-exit-status-code process))
   :external-command-timeout
   (lambda ()
     *external-command-timeout*)
   :run-external
   (lambda (&rest args)
     (apply #'run-external args))
   :run-external-capture
   (lambda (&rest args)
     (apply #'run-external-capture args))
   :run-external-exec
   (lambda (&rest args)
     (apply #'run-external-exec args))
   :exit-process
   (lambda (status)
     (sb-ext:quit :unix-status status))
   :kill-process
   (lambda (&rest args)
     (apply #'kill-process args))
   :continue-process-group
   (lambda (pgid)
     (kill-process (- pgid) :sigcont))
   :get-foreground-pgroup
   (lambda ()
     (get-foreground-pgroup))
   :set-foreground-pgroup
   (lambda (pgid)
     (set-foreground-pgroup pgid))
   :set-foreground-pgid-state
   (lambda (pgid)
     (setf *foreground-pgid* (or pgid 0)))
   :wait-job
   (lambda (&rest args)
     (apply #'wait-job args))
   :current-process-id
   #'sb-posix:getpid))
