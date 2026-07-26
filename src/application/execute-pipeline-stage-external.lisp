(in-package #:nshell.application)

;; Keep the timeout variable special in this compilation unit as well so
;; SBCL does not warn when referencing the shared ACL configuration.
(declaim (special nshell.infrastructure.acl:*external-command-timeout*))

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
                 merge-stderr-p))
            (:conc-name %external-process-redirect-plan-))
  stdout-target
  stdout-mode
  stderr-target
  stderr-mode
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
         (merge-stderr-p
           (or (and (null stdout-target) (null stderr-target))
               (and stdout-target stderr-target
                    (equal stdout-target stderr-target)))))
    (%make-external-process-redirect-plan stdout-target
                                          stdout-mode
                                          stderr-target
                                          stderr-mode
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

(defun %start-external-process-copiers (process stdout-buffer stderr-buffer)
  (let ((stdout-thread
          (nshell.infrastructure.acl::%start-stream-copier
           (sb-ext:process-output process)
           stdout-buffer
           "nshell process stdout copier"))
        (stderr-thread nil))
    (when stderr-buffer
      (setf stderr-thread
            (nshell.infrastructure.acl::%start-stream-copier
             (sb-ext:process-error process)
             stderr-buffer
             "nshell process stderr copier")))
    (remove nil (list stdout-thread stderr-thread))))

(defun %finish-external-process-output
    (stdout-buffer stderr-buffer redirect-plan exit-code)
  (let ((output (get-output-stream-string stdout-buffer))
        (errout (and stderr-buffer
                     (get-output-stream-string stderr-buffer))))
    (%write-process-output-target
     (%external-process-redirect-plan-stdout-target redirect-plan)
     (%external-process-redirect-plan-stdout-mode redirect-plan)
     output)
    (%write-process-output-target
     (%external-process-redirect-plan-stderr-target redirect-plan)
     (%external-process-redirect-plan-stderr-mode redirect-plan)
     (or errout ""))
    (values (and (null (%external-process-redirect-plan-stdout-target redirect-plan))
                 output)
              exit-code)))

(defun %execute-external-pipeline-stage (command-node input redirects)
  "Execute COMMAND-NODE as an external process with optional INPUT string.
  Applies REDIRECTS and returns (output exit-code)."
  (let* ((command (nshell.domain.parsing:command-node-command command-node))
         (args (%line-command-args command-node))
         (input-target (nshell.domain.parsing:redirect-input-file-target redirects))
         (redirect-plan (%external-process-redirect-plan-from redirects)))
    (multiple-value-bind (stdin opened-input)
        (%external-process-input-stream input-target input)
      (handler-case
          (unwind-protect
               (let* ((stdout-buffer (make-string-output-stream))
                      ;; Asked once and reused: 2>&1 decides both whether a
                      ;; separate stderr buffer exists and what :error is.
                      (merge-stderr-p
                        (%external-process-redirect-plan-merge-stderr-p
                         redirect-plan))
                      (stderr-buffer
                        (unless merge-stderr-p (make-string-output-stream)))
                      (process (sb-ext:run-program command args
                                                   :input stdin
                                                   :output :stream
                                                   :error (if merge-stderr-p
                                                              :output
                                                              :stream)
                                                   :wait nil
                                                   :search t)))
                 (unwind-protect
                      (nshell.infrastructure.acl::%wait-process-with-copiers
                       process
                       (%start-external-process-copiers process
                                                        stdout-buffer
                                                        stderr-buffer)
                       nshell.infrastructure.acl:*external-command-timeout*
                       (lambda ()
                         (%finish-external-process-output
                          stdout-buffer
                          stderr-buffer
                          redirect-plan
                          (nshell.infrastructure.acl:process-exit-status-code
                           process)))
                       (lambda ()
                         (format *error-output*
                                 "nshell: ~a: timed out after ~a seconds~%"
                                 command
                                 nshell.infrastructure.acl:*external-command-timeout*)
                         (%finish-external-process-output
                          stdout-buffer
                          stderr-buffer
                          redirect-plan
                          124)))
                    (when (and process (sb-ext:process-alive-p process))
                      (ignore-errors (sb-ext:process-wait process)))))
              (when opened-input
                (close opened-input)))
        (error (condition)
          (values (format nil "nshell: ~a: ~a~%" command condition) 127))))))
