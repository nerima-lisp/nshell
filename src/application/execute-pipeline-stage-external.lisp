(in-package #:nshell.application)

;; Keep the timeout variable special in this compilation unit as well so
;; SBCL does not warn when referencing the shared ACL configuration.
(declaim (special nshell.infrastructure.acl:*external-command-timeout*))

;;; External process execution helpers for pipeline stages.

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

(defun %external-process-wrapper-redirect-plan (source-plan)
  "The wrapper owns file redirects; retain only the parent's pipe topology."
  (%make-external-process-redirect-plan
    nil
    :supersede
    nil
    :supersede
    :stdout
    :stderr
    (%external-process-redirect-plan-merge-stderr-p source-plan)))

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

(defun %continue-stopped-external-process (pgid)
  "PGID's process stopped (SIGTSTP, typically Ctrl-Z reaching it once its own
process group owns the terminal) while this synchronous wait holds its output
buffers and copier threads on the call stack. Suspending here cannot work:
this frame has no continuation for a later fg to resume, so registering a
stopped job would strand the buffers and silently lose everything the process
writes after resuming. Refuse the suspension instead -- continue the process
and keep waiting -- matching RUN-EXTERNAL-CAPTURE's documented policy of
dropping Ctrl-Z for waits that cannot observe a stop."
  (ignore-errors
   (nshell.infrastructure.acl:kill-process (- pgid) :sigcont))
  :continue-wait)

(defun %execute-external-pipeline-stage
    (command-node input redirects &optional process-substitution-resources)
  "Execute COMMAND-NODE as an external process with optional INPUT string.
  Applies REDIRECTS and returns (output exit-code)."
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
         ;; The child wrapper applies file redirects itself.  Keep only the
         ;; stream topology needed to route data that remains on the parent's
         ;; captured stdout/stderr pipes.
         (redirect-plan
           (if wrapper-p
               (%external-process-wrapper-redirect-plan source-redirect-plan)
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
            process-substitution-resources))
         (process-started nil))
    (handler-case
        (multiple-value-bind (stdin opened-input)
            (%external-process-input-stream input-target input)
          (unwind-protect
               (unwind-protect
                    (let* ((stdout-buffer (make-string-output-stream))
                           ;; Asked once and reused: 2>&1 decides both whether a
                           ;; separate stderr buffer exists and what :error is.
                           (merge-stderr-p
                             (%external-process-redirect-plan-merge-stderr-p
                              redirect-plan))
                           (stderr-buffer
                             (unless merge-stderr-p
                               (make-string-output-stream)))
                           (process (sb-ext:run-program
                                     effective-command
                                     effective-args
                                     :input stdin
                                     :output :stream
                                     :error (if merge-stderr-p
                                                :output
                                                :stream)
                                     :wait nil
                                     :search t
                                     :preserve-fds preserve-fds)))
                      (setf process-started t)
                      (%release-process-substitution-resources
                       process-substitution-resources)
                      (let* ((pid (sb-ext:process-pid process))
                             (pgid (and (integerp pid) (plusp pid) pid)))
                        ;; Isolate the child in its own process group and hand
                        ;; the terminal to it for the duration of the wait, so
                        ;; a terminal-generated Ctrl-C/Ctrl-Z reaches the child
                        ;; instead of nshell itself -- the same pattern
                        ;; RUN-EXTERNAL already uses. Unconditional like there:
                        ;; %WITH-FOREGROUND-PROCESS-GROUP's TCSETPGRP calls are
                        ;; wrapped in IGNORE-ERRORS, so this is a no-op when
                        ;; there is no controlling terminal (batch mode, a
                        ;; redirected pipeline stage, `-c`/script execution).
                        (when pgid
                          (nshell.infrastructure.acl::%assign-process-group
                           pid pgid))
                        (flet ((finish-process ()
                                 (%finish-external-pipeline-process
                                  process stdout-buffer stderr-buffer
                                  redirect-plan command pgid)))
                          (if pgid
                              (nshell.infrastructure.acl::%call-with-foreground-process-group
                               pgid #'finish-process)
                              (finish-process)))))
                 (when opened-input
                   (close opened-input)))
            (if process-started
                (%finish-process-substitution-resources
                 process-substitution-resources)
                (%abort-process-substitution-resources
                 process-substitution-resources))))
      (error (condition)
        (%abort-process-substitution-resources process-substitution-resources)
        (values (format nil "nshell: ~a: ~a~%" command condition) 127)))))
