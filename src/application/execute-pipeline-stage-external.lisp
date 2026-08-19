(in-package #:nshell.application)

(defun %wait-external-process-for-cleanup (context process)
  (handler-case
      (values (funcall (%process-fn context :process-wait) process) nil)
    (error (condition)
      (values nil condition))))

;;; External process execution helpers for pipeline stages.

(defun %write-process-output-target (target mode output)
  (when target
    (with-open-file (stream target
                            :direction :output
                            :if-exists mode
                            :if-does-not-exist :create)
      (write-string output stream))))

(defstruct (%external-process-redirect-plan
            (:constructor %make-external-process-redirect-plan
                (stdout-target stdout-mode stderr-target stderr-mode
                 stdout-endpoint stderr-endpoint merge-stderr-p))
            (:conc-name %external-process-redirect-plan-))
  stdout-target
  stdout-mode
  stderr-target
  stderr-mode
  stdout-endpoint
  stderr-endpoint
  merge-stderr-p)

(defun %external-process-redirect-plan-from (redirects)
  (let* ((destinations
           (nshell.domain.parsing:redirect-output-destinations redirects))
         (stdout-target
           (nshell.domain.parsing:redirect-output-destinations-stdout-target
            destinations))
         (stdout-mode
           (nshell.domain.parsing:redirect-output-destinations-stdout-mode
            destinations))
         (stderr-target
           (nshell.domain.parsing:redirect-output-destinations-stderr-target
            destinations))
         (stderr-mode
           (nshell.domain.parsing:redirect-output-destinations-stderr-mode
            destinations))
         (stdout-endpoint
           (nshell.domain.parsing:redirect-output-destinations-stdout-endpoint
            destinations))
         (stderr-endpoint
           (nshell.domain.parsing:redirect-output-destinations-stderr-endpoint
            destinations))
         (merge-stderr-p
           (or (and (null stdout-target) (null stderr-target))
               (eq stdout-endpoint stderr-endpoint))))
    (%make-external-process-redirect-plan stdout-target
                                          stdout-mode
                                          stderr-target
                                          stderr-mode
                                          stdout-endpoint
                                          stderr-endpoint
                                          merge-stderr-p)))

(defun %external-process-input-stream (input-target input)
  (let ((opened-input nil))
    (values (cond
              (input-target
               (setf opened-input
                     (open input-target :direction :input :if-does-not-exist :error)))
              (input (make-string-input-stream input))
              (t *standard-input*))
            opened-input)))

(defstruct (%external-process-stage-plan
            (:constructor %make-external-process-stage-plan
                (command args input-target redirect-plan preserve-fds))
            (:conc-name %external-process-stage-plan-))
  command
  args
  input-target
  redirect-plan
  preserve-fds)

(defun %external-process-stage-plan-from
    (context command-node redirects process-substitution-resources)
  (let* ((command (nshell.domain.parsing:command-node-command command-node))
         (args (%line-command-args command-node))
         (wrapper-p
           (and command
                (nshell.domain.parsing:redirects-require-shell-wrapper-p
                 redirects)))
         (input-target
           (unless wrapper-p
             (nshell.domain.parsing:redirect-input-file-target redirects)))
         (source-redirect-plan (%external-process-redirect-plan-from redirects))
         (redirect-plan
           (if wrapper-p
               (%make-external-process-redirect-plan
                nil
                :supersede
                nil
                :supersede
                :stdout
                :stderr
                (%external-process-redirect-plan-merge-stderr-p
                 source-redirect-plan))
               source-redirect-plan))
         (effective-command (if wrapper-p "sh" command))
         (effective-args
           (if wrapper-p
               (list* "-c"
                      (nshell.domain.parsing:shell-redirect-script redirects)
                      "nshell-fd-wrapper"
                      command
                      args)
               args))
         (preserve-fds
           (%process-substitution-resource-fds
            context
            process-substitution-resources)))
    (%make-external-process-stage-plan effective-command
                                       effective-args
                                       input-target
                                       redirect-plan
                                       preserve-fds)))

(defun %start-external-process-copiers
    (context process stdout-buffer stderr-buffer)
  (let ((stdout-thread
          (funcall (%process-fn context :start-stream-copier)
           (funcall (%process-fn context :process-output) process)
           stdout-buffer
           "nshell process stdout copier"))
        (stderr-thread nil))
    (when stderr-buffer
      (setf stderr-thread
            (funcall (%process-fn context :start-stream-copier)
             (funcall (%process-fn context :process-error) process)
             stderr-buffer
             "nshell process stderr copier")))
    (remove nil (list stdout-thread stderr-thread))))

(defun %route-external-process-output
    (endpoint target mode output return-output-p)
  (cond
    ((eq endpoint :stdout)
     (if return-output-p
         output
         (write-string output *standard-output*)))
    ((eq endpoint :stderr)
     (write-string output *error-output*)
     nil)
    (target
     (%write-process-output-target target mode output)
     nil)
    (return-output-p
     output)
    (t
     nil)))

(defun %finish-external-process-output
    (stdout-buffer stderr-buffer redirect-plan exit-code)
  (let* ((output (get-output-stream-string stdout-buffer))
         (errout (and stderr-buffer
                      (get-output-stream-string stderr-buffer)))
         (stdout-target
           (%external-process-redirect-plan-stdout-target redirect-plan))
         (stdout-mode
           (%external-process-redirect-plan-stdout-mode redirect-plan))
         (stderr-target
           (%external-process-redirect-plan-stderr-target redirect-plan))
         (stderr-mode
           (%external-process-redirect-plan-stderr-mode redirect-plan))
         (stdout-endpoint
           (%external-process-redirect-plan-stdout-endpoint redirect-plan))
         (stderr-endpoint
           (%external-process-redirect-plan-stderr-endpoint redirect-plan)))
    (if (%external-process-redirect-plan-merge-stderr-p redirect-plan)
        (values (%route-external-process-output
                 stdout-endpoint
                 stdout-target
                 stdout-mode
                 output
                 t)
                exit-code)
        (let ((returned-output
                (%route-external-process-output
                 stdout-endpoint
                 stdout-target
                 stdout-mode
                 output
                 t)))
          (%route-external-process-output
           stderr-endpoint
           stderr-target
           stderr-mode
           (or errout "")
           nil)
          (values returned-output exit-code)))))

(defun %wait-for-external-process
    (context process stdout-buffer stderr-buffer redirect-plan command)
  (let ((timeout-seconds
          (funcall (%process-fn context :external-command-timeout))))
    (unwind-protect
         (funcall
          (%process-fn context :wait-process-with-copiers)
          process
          (%start-external-process-copiers
           context
           process
           stdout-buffer
           stderr-buffer)
          timeout-seconds
          (lambda ()
            (%finish-external-process-output
             stdout-buffer
             stderr-buffer
             redirect-plan
             (funcall (%process-fn context :process-exit-status-code)
                      process)))
          (lambda ()
            (format *error-output*
                    "nshell: ~a: timed out after ~a seconds~%"
                    command
                    timeout-seconds)
            (%finish-external-process-output
             stdout-buffer
             stderr-buffer
             redirect-plan
             124)))
      (when (and process
                 (funcall (%process-fn context :process-alive-p) process))
        (%wait-external-process-for-cleanup context process)))))

(defmacro %with-process-substitution-lifecycle
    ((context resources process-started) &body body)
  `(unwind-protect
       (progn ,@body)
     (if ,process-started
         (%finish-process-substitution-resources ,context ,resources)
         (%abort-process-substitution-resources ,context ,resources))))

(defun %execute-external-process
    (context stage-plan stdin command &optional process-substitution-resources)
  (let ((process-started nil))
    (%with-process-substitution-lifecycle
        (context process-substitution-resources process-started)
      (let* ((stdout-buffer (make-string-output-stream))
             ;; Asked once and reused: 2>&1 decides both whether a separate
             ;; stderr buffer exists and what :error is.
             (redirect-plan
               (%external-process-stage-plan-redirect-plan stage-plan))
             (merge-stderr-p
               (%external-process-redirect-plan-merge-stderr-p
                redirect-plan))
             (stderr-buffer
               (unless merge-stderr-p
                 (make-string-output-stream)))
             (process
               (funcall (%process-fn context :run-program)
                (%external-process-stage-plan-command stage-plan)
                (%external-process-stage-plan-args stage-plan)
                :input stdin
                :output :stream
                :error (if merge-stderr-p :output :stream)
                :wait nil
                :search t
                :preserve-fds
                (%external-process-stage-plan-preserve-fds stage-plan))))
        (setf process-started t)
        (%release-process-substitution-resources
         context
         process-substitution-resources)
        (%wait-for-external-process
         context
         process
         stdout-buffer
         stderr-buffer
         redirect-plan
         command)))))

(defun %execute-external-pipeline-stage
    (context command-node input redirects &optional process-substitution-resources)
  "Execute COMMAND-NODE as an external process with optional INPUT string.
  Applies REDIRECTS and returns (output exit-code)."
  (let* ((command (nshell.domain.parsing:command-node-command command-node))
         (stage-plan
           (%external-process-stage-plan-from
            context
            command-node
            redirects
            process-substitution-resources)))
    (handler-case
        (multiple-value-bind (stdin opened-input)
            (%external-process-input-stream
             (%external-process-stage-plan-input-target stage-plan)
             input)
          (unwind-protect
               (%execute-external-process
                context
                stage-plan
                stdin
                command
                process-substitution-resources)
            (when opened-input
              (close opened-input))))
      (error (condition)
        (%abort-process-substitution-resources
         context
         process-substitution-resources)
        (values (format nil "nshell: ~a: ~a~%" command condition) 127)))))
