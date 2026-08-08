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
       (:sigint sb-unix:sigint)
       (:sigterm sb-unix:sigterm)
       (:sigtstp sb-unix:sigtstp)
       (:sigcont sb-unix:sigcont)
       (:sigchld sb-unix:sigchld)
       (:sigwinch sb-unix:sigwinch)))
    ((nshell.domain.signals:signal-p signal)
     (%signal-number (nshell.domain.signals:signal-name signal)))
    (t
     (error "Unsupported signal designator: ~s" signal))))

(defun kill-process (pid signal)
  "Send SIGNAL to PID. Negative PID values target process groups."
  (sb-posix:kill pid (%signal-number signal)))

(defun %foreground-process-group-target ()
  (when (and (integerp *foreground-pgid*)
             (plusp *foreground-pgid*)
             (/= *foreground-pgid* *shell-pgid*))
    *foreground-pgid*))

(defun %send-process-group-signal (pgid signal)
  (sb-posix:kill (- pgid) signal))

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
  "Forward SIGTSTP to the foreground process group, or suspend the shell."
  (declare (ignore signal info context))
  (unless (%signal-foreground-process-group sb-unix:sigtstp)
    (ignore-errors (nshell.infrastructure.terminal:restore-terminal-mode))
    (sb-sys:enable-interrupt sb-unix:sigtstp :default)
    (sb-posix:kill (sb-posix:getpid) sb-unix:sigtstp)))

(defun shell-sigchld-handler (signal info context)
  "Record that child process state changed; reaping is done outside the handler."
  (declare (ignore signal info context))
  (setf *children-changed* t))

(defun shell-sigwinch-handler (signal info context)
  "Record terminal resize events for the main loop."
  (declare (ignore signal info context))
  (setf *terminal-resized* t))

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
  (ignore-errors (nshell.infrastructure.terminal:enable-raw-mode))
  (ignore-errors (set-foreground-pgroup (sb-posix:getpid))))

(defun install-signal-handlers ()
  "Install shell signal handlers for job-control aware interactive operation."
  (setf *shell-pgid* (sb-posix:getpid))
  (sb-sys:enable-interrupt sb-unix:sigint #'shell-sigint-handler)
  (sb-sys:enable-interrupt sb-unix:sigtstp #'shell-sigtstp-handler)
  (sb-sys:enable-interrupt sb-unix:sigchld #'shell-sigchld-handler)
  (sb-sys:enable-interrupt sb-unix:sigwinch #'shell-sigwinch-handler)
  (sb-sys:enable-interrupt sb-unix:sigcont #'shell-sigcont-handler)
  (sb-sys:enable-interrupt sb-unix:sigttou :ignore)
  (sb-sys:enable-interrupt sb-unix:sigttin :ignore)
  t)
