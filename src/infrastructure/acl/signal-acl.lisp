(in-package #:nshell.infrastructure.acl)


(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defvar *shell-pgid* 0)
(defvar *foreground-pgid* 0)
(defvar *terminal-resized* nil)
(defvar *children-changed* nil)
(defvar *sigint-received* nil)

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
    ;; A foreground child is registered, which today means a wait that cannot
    ;; observe a stop is running (RUN-EXTERNAL-CAPTURE's COMMUNICATE treats a
    ;; stopped child as still running). Forwarding SIGTSTP there would wedge
    ;; the shell forever behind a process nothing will resume, and suspending
    ;; the shell itself mid-command is worse; dropping the Ctrl-Z is the only
    ;; safe response. Waits that DO support stops (fg, the pipeline-stage
    ;; wait) hand the terminal to the child's process group, so the kernel
    ;; delivers their Ctrl-Z directly and this handler never sees it.
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
    (ignore-errors (nshell.infrastructure.terminal:restore-terminal-mode))
    (sb-sys:enable-interrupt sb-unix:sigtstp :default)
    (kill-process (current-process-id) sb-unix:sigtstp)))

(defun shell-sigchld-handler (signal info context)
  "Record that child process state changed; reaping is done outside the handler."
  (declare (ignore signal info context))
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

(defun install-signal-handlers ()
  "Install shell signal handlers for job-control aware interactive operation."
  (setf *shell-pgid* (current-process-id))
  (sb-sys:enable-interrupt sb-unix:sigint #'shell-sigint-handler)
  (sb-sys:enable-interrupt sb-unix:sigtstp #'shell-sigtstp-handler)
  (sb-sys:enable-interrupt sb-unix:sigchld #'shell-sigchld-handler)
  (sb-sys:enable-interrupt sb-unix:sigwinch #'shell-sigwinch-handler)
  (sb-sys:enable-interrupt sb-unix:sigcont #'shell-sigcont-handler)
  (sb-sys:enable-interrupt sb-unix:sigttou :ignore)
  (sb-sys:enable-interrupt sb-unix:sigttin :ignore)
  t)
