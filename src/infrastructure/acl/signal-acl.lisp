(in-package #:nshell.infrastructure.acl)


(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defvar *shell-pgid* 0)
(defvar *foreground-pgid* 0)
(defvar *terminal-resized* nil)
(defvar *children-changed* nil)
(defvar *sigint-received* nil)

(defvar *pending-shell-termination-signal* nil)

(defun os-signal->domain (os-signal)
  (let ((sig-map `((:sigint . ,sb-unix:sigint)
                   (:sigterm . ,sb-unix:sigterm)
                   (:sigtstp . ,sb-unix:sigtstp)
                   (:sigcont . ,sb-unix:sigcont)
                   (:sigchld . ,sb-unix:sigchld)
                   (:sigwinch . ,sb-unix:sigwinch))))
    (let ((num (cdr (assoc os-signal sig-map))))
      (when num (nshell.domain.signals:make-signal os-signal num)))))

(defun domain-signal->os (domain-signal)
  (nshell.domain.signals:signal-name domain-signal))

(defun %signal-number (signal)
  (cond
    ((integerp signal) signal)
    ((keywordp signal)
     (ecase signal
       (:sighup sb-unix:sighup)
       (:sigint sb-unix:sigint)
       (:sigquit sb-unix:sigquit)
       (:sigill sb-unix:sigill)
       (:sigtrap sb-unix:sigtrap)
       (:sigbus sb-unix:sigbus)
       (:sigfpe sb-unix:sigfpe)
       (:sigkill sb-unix:sigkill)
       (:sigusr1 sb-unix:sigusr1)
       (:sigsegv sb-unix:sigsegv)
       (:sigusr2 sb-unix:sigusr2)
       (:sigpipe sb-unix:sigpipe)
       (:sigalrm sb-unix:sigalrm)
       (:sigterm sb-unix:sigterm)
       (:sigstop sb-unix:sigstop)
       (:sigtstp sb-unix:sigtstp)
       (:sigcont sb-unix:sigcont)
       (:sigchld sb-unix:sigchld)
       (:sigttin sb-unix:sigttin)
       (:sigttou sb-unix:sigttou)
       (:sigwinch sb-unix:sigwinch)))
    ((nshell.domain.signals:signal-p signal)
     (%signal-number (nshell.domain.signals:signal-name signal)))
    (t
     (error "Unsupported signal designator: ~s" signal))))

(defun kill-process (pid signal)
  "Send SIGNAL to PID. Negative PID values target process groups."
  (sb-posix:kill pid (%signal-number signal)))

(defun process-stop-signal-p (signal)
  "Return T when SIGNAL stops a process rather than terminating it."
  (let ((number (ignore-errors (%signal-number signal))))
    (and number
         (not (null (member number (list sb-unix:sigstop sb-unix:sigtstp)
                             :test #'=))))))

(defun process-continue-signal-p (signal)
  "Return T when SIGNAL continues a stopped process."
  (let ((number (ignore-errors (%signal-number signal))))
    (and number (= number sb-unix:sigcont))))

(defun %foreground-process-group-target ()
  (when (and (integerp *foreground-pgid*)
             (plusp *foreground-pgid*)
             (/= *foreground-pgid* *shell-pgid*))
    *foreground-pgid*))

(defun %send-process-group-signal (pgid signal)
  (kill-process (- pgid) signal))

(defun %signal-foreground-process-group (signal)
  (let ((pgid (%foreground-process-group-target)))
    (when pgid
      (handler-case
          (%send-process-group-signal pgid signal)
        (error ()
          (setf *foreground-pgid* 0)))
      pgid)))

(defun shell-sigint-handler (signal info context)
  "Forward SIGINT to the foreground process group without killing the shell."
  (declare (ignore signal info context))
  (%signal-foreground-process-group sb-unix:sigint)
  (setf *sigint-received* t))

(defun shell-sigtstp-handler (signal info context)
  "Ignore SIGTSTP while a foreground child runs, otherwise suspend the shell."
  (declare (ignore signal info context))
  (when (%foreground-process-group-target)
    ;; A foreground child is registered behind a wait that cannot observe a
    ;; stop. Forwarding SIGTSTP there would wedge that wait, so Ctrl-Z is
    ;; deliberately dropped on this synchronous fallback path.
    (return-from shell-sigtstp-handler))
  (unless (%signal-foreground-process-group sb-unix:sigtstp)
    ;; Swallowed deliberately, and -- unlike the REPL's cleanup path, which
    ;; reports -- silently. This runs asynchronously on top of whatever the
    ;; shell was doing, so writing a diagnostic could re-enter a stream this
    ;; same thread already holds, and a condition escaping a handler unwinds
    ;; arbitrary interrupted code. Both are worse than the failure itself:
    ;; stopping with the terminal still raw is recoverable, because the parent
    ;; shell reinstates its own settings and shell-sigcont-handler re-enables
    ;; raw mode on resume.
    (ignore-errors (nshell.infrastructure.terminal:restore-terminal-mode 0 :preserve-snapshot-p t))
    (sb-sys:enable-interrupt sb-unix:sigtstp :default)
    (kill-process (current-process-id) sb-unix:sigtstp)))

(defun %refresh-sbcl-process-statuses ()
  "Let SBCL update process objects before notifying the shell job monitor."
  (sb-impl::get-processes-status-changes))

(defun shell-sigchld-handler (signal info context)
  "Refresh SBCL process objects and record that child state changed."
  (declare (ignore signal info context))
  (%refresh-sbcl-process-statuses)
  (setf *children-changed* t))

(defun shell-sigwinch-handler (signal info context)
  "Record terminal resize events for the main loop."
  (declare (ignore signal info context))
  (setf *terminal-resized* t))

(defun consume-sigint-received-p ()
  "Return and clear the pending SIGINT notification."
  (prog1 *sigint-received*
    (setf *sigint-received* nil)))
(defun consume-terminal-resize-p ()
  "Return and clear the pending terminal resize notification."
  (prog1 *terminal-resized*
    (setf *terminal-resized* nil)))

(defun consume-children-changed-p ()
  "Return and clear the pending child-process notification."
  (prog1 *children-changed*
    (setf *children-changed* nil)))

(defun shell-sigcont-handler (signal info context)
  "Re-enable raw mode and reclaim the terminal after continuing."
  (declare (ignore signal info context))
  ;; Same async-context reasoning as shell-sigtstp-handler: no reporting and no
  ;; propagation out of a signal handler. This is therefore the one raw-mode
  ;; failure nshell cannot make visible, and it is a known gap rather than an
  ;; oversight -- the session entry point (install-interactive-terminal in
  ;; presentation/repl-session.lisp) is where an unusable terminal is caught and
  ;; reported. Making a failed resume visible needs a flag the main loop reads,
  ;; not a report from in here.
  (ignore-errors (nshell.infrastructure.terminal:enable-raw-mode))
  (ignore-errors (set-foreground-pgroup (current-process-id))))

(defun %request-shell-termination (signal)
  (sb-sys:without-interrupts
    (unless *pending-shell-termination-signal*
      (setf *pending-shell-termination-signal* signal)))
  (%signal-foreground-process-group signal))

(defun shell-sighup-handler (signal info context)
  (declare (ignore signal info context))
  (%request-shell-termination sb-unix:sighup))

(defun shell-sigterm-handler (signal info context)
  (declare (ignore signal info context))
  (%request-shell-termination sb-unix:sigterm))

(defun consume-shell-termination-status ()
  (let ((signal (prog1 *pending-shell-termination-signal*
                  (setf *pending-shell-termination-signal* nil))))
    (when signal (+ 128 signal))))

(defun install-signal-handlers ()
  "Install shell signal handlers for job-control aware interactive operation."
  (setf *shell-pgid* (current-process-id)
        *pending-shell-termination-signal* nil)
  (sb-sys:enable-interrupt sb-unix:sighup (function shell-sighup-handler))
  (sb-sys:enable-interrupt sb-unix:sigint (function shell-sigint-handler))
  (sb-sys:enable-interrupt sb-unix:sigterm (function shell-sigterm-handler))
  (sb-sys:enable-interrupt sb-unix:sigtstp (function shell-sigtstp-handler))
  (sb-sys:enable-interrupt sb-unix:sigchld (function shell-sigchld-handler))
  (sb-sys:enable-interrupt sb-unix:sigwinch (function shell-sigwinch-handler))
  (sb-sys:enable-interrupt sb-unix:sigcont (function shell-sigcont-handler))
  (sb-sys:enable-interrupt sb-unix:sigttou :ignore)
  (sb-sys:enable-interrupt sb-unix:sigttin :ignore)
  t)

;;; Noninteractive runs (batch, script files and --json): SIGINT, SIGTERM and
;;; SIGHUP end the whole run. Only the first stop reason counts, whether it is
;;; one of these signals or a reason the run records itself (the --json
;;; deadline, a full-screen program); a later signal is recorded nowhere and
;;; does nothing, so it cannot unwind the cleanup of the first one.

(defparameter +noninteractive-stop-signals+
  (list sb-unix:sighup sb-unix:sigint sb-unix:sigterm))

(defstruct (noninteractive-stop (:constructor make-noninteractive-stop ()))
  ;; The first stop reason: a signal number, or a keyword the run claimed.
  (reason nil)
  ;; The thread inside CALL-WITH-NONINTERACTIVE-SIGNALS and its catch tag.
  (thread nil)
  (tag nil)
  ;; True while the catch for TAG is live and no unwind to it has started.
  (armed-p nil)
  (before-unwind nil))

(defun claim-noninteractive-stop (stop reason)
  "Record REASON as why STOP's run ends unless a reason is recorded already.
Return true when REASON is the recorded one. Any thread may call it."
  (null (sb-ext:compare-and-swap (noninteractive-stop-reason stop) nil reason)))

(defun noninteractive-stop-signal (stop)
  "The signal number that ended STOP's run, or NIL."
  (let ((reason (noninteractive-stop-reason stop)))
    (and (integerp reason) reason)))

(defun stop-signal-name (signal)
  (cond ((= signal sb-unix:sighup) "SIGHUP")
        ((= signal sb-unix:sigint) "SIGINT")
        ((= signal sb-unix:sigterm) "SIGTERM")
        (t (format nil "signal ~D" signal))))

(defvar *interruptions-sealable-p* nil
  "True inside CALL-WITH-SEALABLE-INTERRUPTIONS, which has bound this thread's
interruption hook.")

(defun call-with-sealable-interruptions (thunk)
  "Call THUNK with this thread's SB-THREAD interruption hook bound, so that
SEAL-INTERRUPTIONS changes it for this thread only and only until THUNK
returns or is unwound."
  (let ((sb-thread::*interrupt-handler* sb-thread::*interrupt-handler*)
        (*interruptions-sealable-p* t))
    (funcall thunk)))

(defun seal-interruptions (&optional (admit (list nil)))
  "Drop every interruption (SB-THREAD:INTERRUPT-THREAD, and so every timer of
SB-EXT:WITH-TIMEOUT) that this thread would run from now until the
CALL-WITH-SEALABLE-INTERRUPTIONS around it returns, except while the car of
ADMIT is true. Does nothing outside such a call.

It is for an unwind that must reach its catch: an interruption that runs
while the unwind passes a frame can signal a condition a handler further out
catches, and that handler's transfer of control replaces the unwind. The
timer of a command substitution's deadline does exactly that."
  (when *interruptions-sealable-p*
    (setf sb-thread::*interrupt-handler*
          (lambda (interruption)
            (when (car admit) (funcall interruption))))))

(defun unwind-to-noninteractive-signal (stop)
  "In STOP's thread, unwind to its CALL-WITH-NONINTERACTIVE-SIGNALS after a
signal was recorded as the stop reason, calling its BEFORE-UNWIND first. Does
nothing once that unwind has started or the call is returning. From the start
of BEFORE-UNWIND until the call returns, no other interruption runs in this
thread (SEAL-INTERRUPTIONS), so nothing can take the unwind over."
  (sb-sys:without-interrupts
    (let ((signal (noninteractive-stop-signal stop)))
      (when (and signal (noninteractive-stop-armed-p stop))
        (setf (noninteractive-stop-armed-p stop) nil)
        (seal-interruptions)
        (let ((before-unwind (noninteractive-stop-before-unwind stop)))
          (when before-unwind (funcall before-unwind signal)))
        (throw (noninteractive-stop-tag stop) signal)))))

(defun %noninteractive-signal-received (stop signal)
  ;; Runs in whichever thread took the signal. The unwind happens in STOP's
  ;; thread, where the catch is; only the signal that becomes the stop reason
  ;; sends it, so it is sent at most once.
  (when (claim-noninteractive-stop stop signal)
    (handler-case
        (sb-thread:interrupt-thread
         (noninteractive-stop-thread stop)
         (lambda () (unwind-to-noninteractive-signal stop)))
      (error () nil))))

(sb-alien:define-alien-routine ("install_handler" %runtime-install-handler) sb-alien:void
  (signal sb-alien:int)
  (handler sb-alien:unsigned))

(defun signal-disposition (signal)
  "Return :IGNORE when SIGNAL is ignored (SIG_IGN), :DEFAULT for SIG_DFL, and
:HANDLER otherwise, as sigaction(2) reports it.

sa_handler is the first member of struct sigaction on Darwin and on Linux, so
only that word of the buffer is read; the buffer is larger than the structure
on both."
  (sb-alien:with-alien ((action (array (sb-alien:unsigned 8) 512)))
    (let ((sap (sb-alien:alien-sap action)))
      (dotimes (index 512) (setf (sb-sys:sap-ref-8 sap index) 0))
      (unless (zerop (sb-alien:alien-funcall
                      (sb-alien:extern-alien
                       "sigaction"
                       (function sb-alien:int sb-alien:int
                                 sb-sys:system-area-pointer sb-sys:system-area-pointer))
                      signal (sb-sys:int-sap 0) sap))
        (error "sigaction(~D) failed" signal))
      (case (sb-sys:sap-ref-word sap 0)
        (0 :default)
        (1 :ignore)
        (t :handler)))))

(defun lisp-signal-handler (signal)
  "Return the Lisp function the SBCL runtime calls for SIGNAL, or NIL.

SB-SYS:ENABLE-INTERRUPT does not return the handler it replaces (see
src/code/target-signal.lisp in SBCL); the runtime keeps it in
lisp_sig_handlers, where 0 stands for both SIG_DFL and SIG_IGN."
  (let ((handler (sb-sys:sap-ref-lispobj
                  (sb-sys:foreign-symbol-sap "lisp_sig_handlers" t)
                  (* signal sb-vm:n-word-bytes))))
    (and (functionp handler) handler)))

(defun reinstall-lisp-signal-handler (signal handler)
  "Make HANDLER, a value LISP-SIGNAL-HANDLER returned, SIGNAL's handler again,
or restore SIG_DFL when it is NIL. HANDLER is already the closure the runtime
calls, so it goes to the runtime directly: SB-SYS:ENABLE-INTERRUPT would wrap
it in another closure."
  (if handler
      (sb-sys:with-pinned-objects (handler)
        (%runtime-install-handler signal (sb-kernel:get-lisp-obj-address handler)))
      (sb-sys:enable-interrupt signal :default)))

(defun call-with-noninteractive-signals (stop thunk &key before-unwind after-signal)
  "Call THUNK with SIGINT, SIGTERM and SIGHUP ending the run STOP describes,
and restore the handlers it replaced on the way out.

The first of these signals that STOP records as its stop reason (see
CLAIM-NONINTERACTIVE-STOP) interrupts the calling thread, which calls
BEFORE-UNWIND with the signal number in the dynamic context it was
interrupted in, unwinds THUNK, and returns what AFTER-SIGNAL returns for the
signal number. AFTER-SIGNAL also runs when a signal is recorded after THUNK
has returned but before this call does. The handlers stay installed while
AFTER-SIGNAL runs, so another signal cannot end its cleanup.

A signal ignored on entry stays ignored, as POSIX requires of a
noninteractive shell (nohup). SBCL itself replaces the dispositions of
SIGINT and SIGTERM at startup, so only SIGHUP can arrive here ignored."
  (setf (noninteractive-stop-thread stop) sb-thread:*current-thread*
        (noninteractive-stop-tag stop) (list :noninteractive-stop)
        (noninteractive-stop-before-unwind stop) before-unwind)
  (let ((installed '()))
    (flet ((handler (signal info context)
             (declare (ignore info context))
             (%noninteractive-signal-received stop signal)))
      (unwind-protect
           (call-with-sealable-interruptions
            (lambda ()
              (let* ((results nil)
                     (signal
                       (catch (noninteractive-stop-tag stop)
                         (unwind-protect
                              (progn
                                (sb-sys:without-interrupts
                                  (dolist (signal +noninteractive-stop-signals+)
                                    (unless (eq (signal-disposition signal) :ignore)
                                      (push (cons signal (lisp-signal-handler signal))
                                            installed)
                                      (sb-sys:enable-interrupt signal #'handler)))
                                  (setf (noninteractive-stop-armed-p stop) t))
                                (setf results (multiple-value-list (funcall thunk))))
                           ;; However THUNK is left, no unwind to the tag may
                           ;; start once the catch is gone.
                           (sb-sys:without-interrupts
                             (setf (noninteractive-stop-armed-p stop) nil)))
                         nil)))
                (let ((signal (or signal (noninteractive-stop-signal stop))))
                  (if (and signal after-signal)
                      (funcall after-signal signal)
                      (values-list results))))))
        (sb-sys:without-interrupts
          (setf (noninteractive-stop-armed-p stop) nil)
          (dolist (entry installed)
            (reinstall-lisp-signal-handler (car entry) (cdr entry))))))))
