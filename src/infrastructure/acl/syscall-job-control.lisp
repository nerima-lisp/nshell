(in-package #:nshell.infrastructure.acl)

(declaim (special *shell-pgid* *foreground-pgid*))

(defun current-process-id ()
  "Return the process id of the current Lisp process."
  (sb-posix:getpid))

(defun set-process-group (pid pgid)
  "Set PID's process group to PGID."
  (sb-posix:setpgid pid pgid))

(defun set-foreground-pgroup (pgid)
  "Make PGID the foreground process group for the controlling terminal."
  (let ((result (%tcsetpgrp 0 pgid)))
    (when (%syscall-failed-p result)
      (error "tcsetpgrp failed (result=~s, errno=~s)"
             result (sb-unix::get-errno)))
    result))

(defun get-foreground-pgroup ()
  "Return the foreground process group of the controlling terminal."
  (let ((result (%tcgetpgrp 0)))
    (when (%syscall-failed-p result)
      (error "tcgetpgrp failed (result=~s, errno=~s)"
             result (sb-unix::get-errno)))
    result))

(defun %current-shell-pgid ()
  (let ((pgid (and (boundp '*shell-pgid*) *shell-pgid*)))
    (if (and (integerp pgid) (plusp pgid))
        pgid
        (current-process-id))))

(defun %assign-process-group (pid pgid)
  (when (and (integerp pid)
             (plusp pid)
             (integerp pgid)
             (plusp pgid))
    (ignore-errors
        (progn
          (set-process-group pid pgid)
          pgid))))

(defun %with-foreground-process-group (pgid thunk)
  (if (not (and (integerp pgid) (plusp pgid)))
      (funcall thunk)
      (let ((shell-pgid (%current-shell-pgid))
            (previous-pgid (ignore-errors (get-foreground-pgroup))))
        (unwind-protect
             (progn
               (setf *foreground-pgid* pgid)
               (ignore-errors (set-foreground-pgroup pgid))
               (funcall thunk))
          (setf *foreground-pgid* 0)
          (let ((restore-pgid (or previous-pgid shell-pgid)))
            (when (and (integerp restore-pgid) (plusp restore-pgid))
              (ignore-errors (set-foreground-pgroup restore-pgid))))))))

(define-value-struct child-status
    ((pid 0 :type integer)
     (status 0 :type integer)))

(defun reap-children ()
  "Reap all changed child processes without blocking. Returns CHILD-STATUS values."
  (let ((children nil))
    (loop
      (handler-case
          (multiple-value-bind (pid status) (sb-posix:waitpid -1 sb-posix:wnohang)
            (cond
              ((plusp pid)
               (push (%make-child-status pid status) children))
              (t
               (return (nreverse children)))))
        (sb-posix:syscall-error (condition)
          (if (= (sb-posix:syscall-errno condition) sb-posix:echild)
              (return (nreverse children))
              (error condition)))))))

(defun %decode-wait-status (pid status)
  (cond
    ((or (null pid) (zerop pid))
     (values pid :running nil))
    ((sb-posix:wifstopped status)
     (values pid :stopped (sb-posix:wstopsig status)))
    ((sb-posix:wifexited status)
     (values pid :exited (sb-posix:wexitstatus status)))
    ((sb-posix:wifsignaled status)
     (values pid :signaled (sb-posix:wtermsig status)))
    ((sb-posix:wifcontinued status)
     (values pid :continued nil))
    (t
     (values pid :unknown status))))

(defun %waitpid-flags (&key nohang untraced continued)
  (let ((flags 0))
    (when nohang
      (setf flags (logior flags sb-posix:wnohang)))
    (when untraced
      (setf flags (logior flags sb-posix:wuntraced)))
    (when continued
      (let ((wcontinued-symbol (find-symbol "WCONTINUED" "SB-POSIX")))
        (when (and wcontinued-symbol (boundp wcontinued-symbol))
          (setf flags (logior flags (symbol-value wcontinued-symbol))))))
    flags))

(defun wait-job (pid &key nohang untraced continued)
  "Wait for PID or process group PID and return (values child-pid state detail)."
  (handler-case
      (multiple-value-bind (child-pid status)
          (sb-posix:waitpid pid (%waitpid-flags
                                  :nohang nohang
                                  :untraced untraced
                                  :continued continued))
        (%decode-wait-status child-pid status))
    (sb-posix:syscall-error (condition)
      (let ((errno (sb-posix:syscall-errno condition)))
        (cond
          ((= errno sb-posix:echild)
           (values nil :no-child nil))
          ((= errno sb-posix:eintr)
           (values nil :interrupted nil))
          (t
           (error condition)))))))
