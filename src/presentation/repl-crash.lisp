;;; Recovering from unexpected errors and writing crash logs (task P0-4).
(in-package #:nshell.presentation)

(defvar *crash-streak* nil
  "Consecutive crashes at one place in this interactive session, as returned
by NSHELL.DOMAIN.CRASH:CRASH-STREAK-ADVANCE. A command that completes resets it.")

(defvar *safe-reexec-requested-p* nil
  "True once the user accepted a --safe restart; RUN-REPL performs it after
restoring the terminal.")

(defun call-with-crash-capture (thunk on-crash &key pass-through)
  "Call THUNK and return its values. When an ERROR or STORAGE-CONDITION
escapes THUNK, capture the backtrace while the frames still exist, unwind, and
return the values of ON-CRASH called with the crash record.

Conditions of type PASS-THROUGH propagate unchanged. Capturing happens in the
handler, before unwinding, and does as little as possible there because the
stack may be exhausted; ON-CRASH runs after unwinding, on the stack of the
caller."
  (let ((crash nil))
    (block captured
      (handler-bind
          (((or error storage-condition)
             (lambda (condition)
               (unless (and pass-through (typep condition pass-through))
                 (setf crash
                       (nshell.infrastructure.persistence:capture-crash condition))
                 (return-from captured)))))
        (return-from call-with-crash-capture (funcall thunk))))
    (funcall on-crash crash)))

(defun %crash-storage-p (crash)
  (typep (nshell.infrastructure.persistence:crash-record-condition crash)
         'storage-condition))

(defun %crash-message (crash)
  "Return the report of CRASH's condition, or a fixed text when reporting it
fails."
  (let ((condition (nshell.infrastructure.persistence:crash-record-condition crash)))
    (handler-case (princ-to-string condition)
      (serious-condition ()
        (format nil "#<~a>" (type-of condition))))))

(defun %crash-classified-diagnostic-p (crash)
  "True when CRASH's condition carries an nshell error code. Such conditions
are diagnostics nshell raises on purpose, not unexpected errors: they keep
their message and exit status but get no crash log and no streak count."
  (typep (nshell.infrastructure.persistence:crash-record-condition crash)
         'nshell.domain.error-codes:nshell-error-code-mixin))

(defun %crash-in-user-code-p (crash)
  "True when CRASH's condition was signalled by the user's own Lisp code: the
innermost nshell frame is %EVAL-HOST-FUNCTION-CALL, the evaluator's call into a
host function with the user's arguments. An nshell frame inside it, such as a
builtin the user code called, makes it a crash again. Errors the evaluator
signals itself, and forms SBCL compiles and runs, have a different innermost
frame and stay crashes. Storage exhaustion is always a crash."
  (let ((condition (nshell.infrastructure.persistence:crash-record-condition crash)))
    (and (not (typep condition 'storage-condition))
         (eq (find-if #'nshell.domain.crash:nshell-frame-name-p
                      (nshell.infrastructure.persistence:crash-record-frame-names
                       crash))
             'nshell.application::%eval-host-function-call))))

(defun %crash-expected-p (crash)
  "True for failures that are reported as usual but are not crashes: no crash
log, no streak count."
  (or (%crash-classified-diagnostic-p crash)
      (%crash-in-user-code-p crash)))

(defun %record-crash-log (crash stream)
  "Write CRASH's log and say on STREAM where it went. When writing fails, say
why instead; the failure never leaves this function, because the caller is
already recovering from one. Expected failures are not logged."
  (unless (%crash-expected-p crash)
    (%write-crash-log-and-report crash stream)))

(defun %write-crash-log-and-report (crash stream)
  (handler-case
      (format stream "nshell: crash log: ~a~%"
              (nshell.infrastructure.persistence:write-crash-report crash))
    (serious-condition (condition)
      (handler-case
          (format stream "nshell: crash log not written: ~a~%" condition)
        (serious-condition ()
          (ignore-errors
            (format stream "nshell: crash log not written~%")))))))

(defun %read-safe-reexec-answer ()
  "Read one key: :YES for y or Y, :EOF at end of input, otherwise :NO."
  (let ((event (nshell.infrastructure.terminal:read-key-event
                :interrupt-predicate
                (lambda ()
                  (when (nshell.infrastructure.acl:consume-sigint-received-p)
                    t)))))
    (cond
      ((null event) :eof)
      ((and (eq :char (nshell.domain.input:key-event-type event))
            (char-equal #\y (nshell.domain.input:key-event-char event)))
       :yes)
      (t :no))))

(defun %print-running-jobs ()
  (let ((listings (nshell.application:jobs)))
    (if listings
        (progn
          (format t "nshell: running jobs:~%")
          (dolist (listing listings)
            (nshell.application:format-job-listing listing t)))
        (format t "nshell: no running jobs~%"))))

(defun %offer-safe-reexec (place)
  "List the running jobs and ask whether to restart with --safe. Return :REEXEC
when the session should end for the restart, :END when no answer can be read,
and NIL to keep going."
  (format t "nshell: the same error occurred ~d times in a row (~a)~%"
          nshell.domain.crash:+crash-repeat-threshold+ place)
  (%print-running-jobs)
  (format t "Restart nshell with --safe? Running jobs are left behind. [y/N] ")
  (finish-output)
  (let ((answer (handler-case (%read-safe-reexec-answer)
                  (serious-condition () :eof))))
    (format t "~a~%" (if (eq answer :yes) "y" "n"))
    (case answer
      (:eof :end)
      (:yes
       (if (nshell.infrastructure.acl:current-executable-path)
           (progn
             (setf *safe-reexec-requested-p* t)
             :reexec)
           (progn
             (format t "nshell: cannot restart: not running from the nshell executable; start it with nshell --safe~%")
             nil)))
      (t nil))))

(defun %note-interactive-crash (crash)
  "Count CRASH toward the same-place streak of an interactive session and ask
about a --safe restart when the streak reaches the threshold. Return true when
the session should end."
  (when (and *interactive-terminal-installed-p*
             (not (%crash-expected-p crash)))
    (let* ((place (nshell.domain.crash:crash-place
                   (type-of (nshell.infrastructure.persistence:crash-record-condition
                             crash))
                   (nshell.infrastructure.persistence:crash-record-frame-names
                    crash)))
           (streak (nshell.domain.crash:crash-streak-advance *crash-streak* place)))
      (setf *crash-streak* streak)
      (when (nshell.domain.crash:crash-streak-repeated-p streak)
        (setf *crash-streak* nil)
        (not (null (%offer-safe-reexec place)))))))

(defun %end-session-after-crash ()
  (setf *running* nil
        *last-exit-code* 1)
  +repl-exit+)

(defun %guard-repl-continuation (step)
  "Return a continuation that runs STEP with crash recovery and guards the
continuation STEP returns in the same way, so every later trampoline step is
guarded without changing the trampoline."
  (lambda ()
    (let ((result (%call-repl-step-with-crash-recovery step)))
      (if (functionp result)
          (%guard-repl-continuation result)
          result))))

(defun %call-repl-step-with-crash-recovery (step)
  "Run one trampoline STEP. A crash that no inner handler recovered from is
logged and the prompt is drawn again from a clean state. Terminal mode failures
still end the session, as they did before steps were guarded."
  (call-with-crash-capture
   step
   (lambda (crash)
     (format t "~%nshell error: ~a~%"
             (if (%crash-storage-p crash) "storage exhausted" (%crash-message crash)))
     (%record-crash-log crash *standard-output*)
     (if (%note-interactive-crash crash)
         (%end-session-after-crash)
         (progn
           (reset-rendered-prompt-state)
           (lambda () (render-prompt-cont)))))
   :pass-through 'nshell.infrastructure.terminal:terminal-mode-operation-failed))

(defun %reexec-with-safe-mode ()
  "Replace this process with nshell --safe. Return an exit status only when
that fails."
  (handler-case
      (let ((program (nshell.infrastructure.acl:current-executable-path)))
        (unless program
          (error "not running from the nshell executable"))
        (format t "nshell: restarting with --safe~%")
        (finish-output)
        (nshell.infrastructure.acl:exec-program
         program
         (nshell.domain.crash:safe-reexec-arguments
          (nshell.infrastructure.acl:current-process-arguments))))
    (error (condition)
      (format *error-output* "nshell: --safe restart failed: ~a~%" condition)
      1)))
