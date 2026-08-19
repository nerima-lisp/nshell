(in-package #:nshell.application)

(defun %job-spec (args)
  (first args))

(defun %resolve-job-id (job-monitor args &key active-only-p)
  (let ((job-id
         (nshell.domain.job-control:monitor-resolve-job-spec
          job-monitor
          (%job-spec args))))
    (when (and job-id
               (or (not active-only-p)
                   (let ((job (nshell.domain.job-control:monitor-find-job
                               job-monitor job-id)))
                     (and job
                          (not (nshell.domain.execution:job-completed-p job))))))
      job-id)))

(defun %job-spec-label (args)
  (or (%job-spec args) "current"))

(defun %missing-job-output (command job-spec)
  (format nil "~a: no such job: ~a~%" command job-spec))

(defun %builtin-fg (context args)
  (let* ((job-monitor (shell-context-job-monitor context))
         (job-id (%resolve-job-id job-monitor args :active-only-p t))
         (job (fg job-id
                  (shell-context-dispatcher context)
                  (shell-context-process-registry context)
                  (shell-context-terminal-fns context)
                  job-monitor
                  (shell-context-process-fns context))))
    (if job
        (values nil 0)
        (values (%missing-job-output "fg" (%job-spec-label args)) 1))))

(defun %builtin-bg (context args)
  (let* ((job-monitor (shell-context-job-monitor context))
         (job-id (%resolve-job-id job-monitor args :active-only-p t))
         (job (bg job-id
                  (shell-context-dispatcher context)
                  job-monitor
                  (shell-context-process-fns context))))
    (if job
        (values nil 0)
        (values (%missing-job-output "bg" (%job-spec-label args)) 1))))

(defun %select-job-listings (job-monitor args)
  (let ((listings (jobs job-monitor)))
    (if (null args)
        (values listings nil)
        (let (selected missing)
          (dolist (job-spec args)
            (let* ((job-id
                     (nshell.domain.job-control:monitor-resolve-job-spec
                      job-monitor job-spec))
                   (listing (and job-id
                                 (find job-id listings
                                       :key #'job-listing-id
                                       :test #'=))))
              (if listing
                  (push listing selected)
                  (push job-spec missing))))
          (values (nreverse selected) (nreverse missing))))))

(defun %builtin-jobs (context args)
  (let ((job-monitor (shell-context-job-monitor context)))
    (multiple-value-bind (listings missing)
        (%select-job-listings job-monitor args)
      (values
       (with-output-to-string (out)
         (dolist (listing listings)
           (format-job-listing listing out))
         (dolist (job-spec missing)
           (write-string (%missing-job-output "jobs"
                                               (or job-spec "current"))
                         out)))
       (if missing 1 0)))))

(defun %builtin-disown (context args)
  (let ((job-monitor (shell-context-job-monitor context)))
    (if args
        (let* ((job-spec (%job-spec args))
               (job-id (%resolve-job-id job-monitor args)))
          (if job-id
              (progn
                (disown job-id job-monitor)
                (values nil 0))
              (values (format nil "disown: job [~a] not found~%"
                              (or job-spec "current"))
                      1)))
        (%builtin-usage "disown" "disown job-id"))))
(defun %parse-integer-designator (text)
  (when (stringp text)
    (handler-case
        (parse-integer text :junk-allowed nil)
      (parse-error () nil)
      (type-error () nil))))
(defun %parse-positive-integer (text)
  (let ((value (%parse-integer-designator text)))
    (when (and value (plusp value))
      value)))
(defun %find-job-id-by-pid (job-monitor pid)
  (let ((found nil))
    (nshell.domain.job-control:monitor-map-jobs
     job-monitor
     (lambda (job-id job)
       (when (and (null found)
                  (member pid
                          (nshell.domain.execution:job-pids job)
                          :test #'=))
         (setf found job-id))))
    found))
(defun %resolve-wait-job-id (job-monitor job-spec)
  (cond
    ((null job-spec)
     (nshell.domain.job-control:monitor-resolve-job-spec
      job-monitor nil))
    ((and (stringp job-spec)
          (plusp (length job-spec))
          (or (char= (char job-spec 0) #\%)
              (string= job-spec "+")
              (string= job-spec "-")))
     (nshell.domain.job-control:monitor-resolve-job-spec
      job-monitor job-spec))
    (t
     (or (let ((pid (%parse-positive-integer job-spec)))
           (and pid (%find-job-id-by-pid job-monitor pid)))
         (nshell.domain.job-control:monitor-resolve-job-spec
          job-monitor job-spec)))))
(defun %builtin-wait (context args)
  (let* ((job-monitor (shell-context-job-monitor context))
         (process-registry (shell-context-process-registry context))
         (specs
           (if args
               args
               (let (active-job-ids)
                 (nshell.domain.job-control:monitor-map-jobs
                  job-monitor
                  (lambda (job-id job)
                    (unless
                        (nshell.domain.execution:job-completed-p job)
                      (push job-id active-job-ids))))
                 (nreverse active-job-ids))))
         (last-code 0)
         (missing nil))
    (dolist (job-spec specs)
      (let ((job-id (%resolve-wait-job-id job-monitor job-spec)))
        (multiple-value-bind (job exit-code)
            (if job-id
                (wait-for-job job-id
                              process-registry
                              job-monitor
                              (shell-context-process-fns context))
                (values nil nil))
          (if job
              (setf last-code exit-code)
              (push (or job-spec "current") missing)))))
    (if missing
        (values
         (with-output-to-string (out)
           (dolist (job-spec (nreverse missing))
             (format out "wait: no such job: ~a~%" job-spec)))
         1)
        (values nil last-code))))
(defun %parse-signal-designator (text)
  (or
   (%parse-integer-designator text)
   (when (stringp text)
     (let* ((raw (string-upcase text))
            (name (if (and (>= (length raw) 3)
                           (string= "SIG" (subseq raw 0 3)))
                      (subseq raw 3)
                      raw)))
       (cdr (assoc name
                   '(("HUP" . :sighup)
                     ("INT" . :sigint)
                     ("QUIT" . :sigquit)
                     ("ILL" . :sigill)
                     ("TRAP" . :sigtrap)
                     ("BUS" . :sigbus)
                     ("FPE" . :sigfpe)
                     ("KILL" . :sigkill)
                     ("USR1" . :sigusr1)
                     ("SEGV" . :sigsegv)
                     ("USR2" . :sigusr2)
                     ("PIPE" . :sigpipe)
                     ("ALRM" . :sigalrm)
                     ("TERM" . :sigterm)
                     ("STOP" . :sigstop)
                     ("TSTP" . :sigtstp)
                     ("CONT" . :sigcont)
                     ("CHLD" . :sigchld)
                     ("TTIN" . :sigttin)
                     ("TTOU" . :sigttou)
                     ("WINCH" . :sigwinch))
                   :test #'string=))))))
(defun %parse-kill-arguments (args)
  (let ((remaining (copy-list args))
        (signal-designator :sigterm)
        (targets nil)
        (options-p t)
        (list-signals-p nil))
    (loop while remaining
          do (let ((arg (pop remaining)))
               (cond
                 ((and options-p (string= arg "--"))
                  (setf options-p nil))
                 ((and options-p (string= arg "-l"))
                  (setf list-signals-p t))
                 ((and options-p
                       (or (string= arg "-s")
                           (string= arg "--signal")))
                  (if (null remaining)
                      (return-from %parse-kill-arguments
                        (values nil nil nil
                                "kill: option requires an argument -- signal~%"))
                      (let ((parsed (%parse-signal-designator
                                     (pop remaining))))
                        (if (null parsed)
                            (return-from %parse-kill-arguments
                              (values nil nil nil
                                      "kill: invalid signal~%"))
                            (setf signal-designator parsed)))))
                 ((and options-p
                       (string-prefix-p "--signal=" arg))
                  (let ((parsed
                          (%parse-signal-designator
                           (subseq arg (length "--signal=")))))
                    (if (null parsed)
                        (return-from %parse-kill-arguments
                          (values nil nil nil
                                  "kill: invalid signal~%"))
                        (setf signal-designator parsed))))
                 ((and options-p (string= arg "-"))
                  (push arg targets))
                 ((and options-p
                       (plusp (length arg))
                       (char= (char arg 0) #\-))
                  (if (integerp (%parse-integer-designator arg))
                      (push arg targets)
                      (let ((parsed
                              (%parse-signal-designator (subseq arg 1))))
                        (if (null parsed)
                            (return-from %parse-kill-arguments
                              (values nil nil nil
                                      (format nil "kill: unknown option: ~a~%"
                                              arg)))
                            (setf signal-designator parsed)))))
                 (t
                  (push arg targets)))))
    (values signal-designator (nreverse targets) list-signals-p nil)))
(defun %resolve-kill-job-id (job-monitor target)
  (when (and (stringp target)
             (plusp (length target))
             (or (char= (char target 0) #\%)
                 (string= target "+")
                 (string= target "-")))
    (nshell.domain.job-control:monitor-resolve-job-spec
     job-monitor target)))
(defun %kill-one-target (context job-monitor target signal)
  (let ((job-id (%resolve-kill-job-id job-monitor target)))
    (cond
      ((and job-id
            (signal-job job-id
                        signal
                        job-monitor
                        (shell-context-process-fns context)))
       t)
      ((let ((pid (%parse-integer-designator target)))
         (when pid
           (funcall (%process-fn context :kill-process) pid signal)
           t)))
      (t nil))))
(defun %kill-list-output ()
  (format nil "~{~a~^ ~}~%"
          '("HUP" "INT" "QUIT" "ILL" "TRAP" "BUS" "FPE"
            "KILL" "USR1" "SEGV" "USR2" "PIPE" "ALRM" "TERM"
            "STOP" "TSTP" "CONT" "CHLD" "TTIN" "TTOU" "WINCH")))
(defun %builtin-kill (context args)
  (multiple-value-bind (signal-designator targets list-signals-p parse-error)
      (%parse-kill-arguments args)
    (cond
      (parse-error
       (values parse-error 1))
      (list-signals-p
       (values (%kill-list-output) 0))
      ((null targets)
       (%builtin-usage "kill" "kill [-signal] pid|%job"))
      (t
       (let ((job-monitor (shell-context-job-monitor context))
             (code 0))
         (values
          (with-output-to-string (out)
            (dolist (target targets)
              (handler-case
                  (unless (%kill-one-target
                           context
                           job-monitor target signal-designator)
                    (setf code 1)
                    (format out "kill: no such process or job: ~a~%"
                            target))
                (error (condition)
                  (setf code 1)
                  (format out "kill: ~a: ~a~%"
                          target condition))))
          code)))))))
