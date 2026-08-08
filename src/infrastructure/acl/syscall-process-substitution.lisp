;;; Process substitution infrastructure for the anti-corruption layer.

(in-package #:nshell.infrastructure.acl)

(defstruct (process-substitution-resource
             (:constructor %make-process-substitution-resource
                 (path fd processes)))
  path
  fd
  processes)

(defun %process-substitution-fd-directory ()
  (cond
    ((probe-file "/dev/fd/") "/dev/fd/")
    ((probe-file "/proc/self/fd/") "/proc/self/fd/")
    (t
     (error "process substitution requires /dev/fd or /proc/self/fd"))))

(defun %duplicate-process-substitution-fd (fd)
  (multiple-value-bind (duplicate errno)
      (sb-unix:unix-dup fd)
    (if (integerp duplicate)
        duplicate
        (error "could not duplicate process substitution fd ~D (errno ~D)"
               fd errno))))

(defun %process-substitution-stream (fd direction)
  (if (eq direction :input)
      (sb-sys:make-fd-stream fd
                             :output t
                             :buffering :line
                             :auto-close t)
      (sb-sys:make-fd-stream fd
                             :input t
                             :buffering :line
                             :auto-close t)))

(defun spawn-process-substitution (direction commands &key redirects)
  "Spawn COMMANDS behind an anonymous pipe and return its visible fd path.

DIRECTION :INPUT makes COMMANDS write to the returned path.  DIRECTION
:OUTPUT makes COMMANDS read from the returned path.  The returned resource
owns the parent-side fd and the child processes until it is closed."
  (unless (member direction '(:input :output))
    (error "invalid process substitution direction ~S" direction))
  (let ((directory (%process-substitution-fd-directory))
        (read-fd nil)
        (write-fd nil)
        (outer-fd nil)
        (child-fd nil)
        (child-stream nil)
        (processes nil)
        (success-p nil))
    (unwind-protect
         (progn
           (multiple-value-setq (read-fd write-fd) (sb-posix:pipe))
           (if (eq direction :input)
               (setf outer-fd (%duplicate-process-substitution-fd read-fd)
                     child-fd (%duplicate-process-substitution-fd write-fd))
               (setf outer-fd (%duplicate-process-substitution-fd write-fd)
                     child-fd (%duplicate-process-substitution-fd read-fd)))
           (setf child-stream (%process-substitution-stream child-fd direction))
           (setf processes
                 (spawn-pipeline-async
                  commands
                  :redirects redirects
                  :default-input (if (eq direction :output) child-stream t)
                  :default-output (if (eq direction :input) child-stream t)
                  :preserve-fds (list child-fd)
                  :after-spawn
                  (lambda ()
                    (when child-stream
                      (ignore-errors (close child-stream))
                      (setf child-stream nil
                            child-fd nil)))))
           (unless processes
             (error "process substitution command could not be started"))
           (let ((resource
                   (%make-process-substitution-resource
                    (format nil "~A~D" directory outer-fd)
                    outer-fd
                    processes)))
             (setf success-p t
                   outer-fd nil)
             resource))
      (unless success-p
        (when processes
          (ignore-errors (%terminate-pipeline-processes processes))))
      (when child-stream
        (ignore-errors (close child-stream))
        (setf child-stream nil
              child-fd nil))
      (when (integerp child-fd)
        (ignore-errors (sb-posix:close child-fd)))
      (when (integerp outer-fd)
        (ignore-errors (sb-posix:close outer-fd)))
      (when (integerp read-fd)
        (ignore-errors (sb-posix:close read-fd)))
      (when (integerp write-fd)
        (ignore-errors (sb-posix:close write-fd))))))

(defun release-process-substitution-fd (resource)
  "Close the parent-side fd while retaining RESOURCE's child processes."
  (let ((fd (process-substitution-resource-fd resource)))
    (setf (process-substitution-resource-fd resource) nil)
    (when (integerp fd)
      (ignore-errors (sb-posix:close fd))))
  resource)

(defun wait-process-substitution (resource)
  "Wait for RESOURCE's process substitution child processes."
  (let ((processes (process-substitution-resource-processes resource)))
    (unwind-protect
         (if processes
             (%wait-pipeline-processes processes)
             0)
      (setf (process-substitution-resource-processes resource) nil))))

(defun close-process-substitution (resource)
  "Release RESOURCE's fd and terminate/wait any remaining child processes."
  (release-process-substitution-fd resource)
  (let ((processes (process-substitution-resource-processes resource)))
    (when processes
      (unwind-protect
           (%terminate-pipeline-processes processes)
        (setf (process-substitution-resource-processes resource) nil))))
  resource)
