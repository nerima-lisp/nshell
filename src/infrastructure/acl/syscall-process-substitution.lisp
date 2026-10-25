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
         (multiple-value-prog1
             (if processes
                 (%wait-pipeline-processes processes)
                 0)
           (setf (process-substitution-resource-processes resource) nil))
      (when (process-substitution-resource-processes resource)
        (close-process-substitution resource)))))

(defun close-process-substitution (resource)
  "Release RESOURCE's fd and terminate/wait any remaining child processes."
  (release-process-substitution-fd resource)
  (let ((processes (process-substitution-resource-processes resource)))
    (when processes
      (unwind-protect
           (%terminate-pipeline-processes processes)
        (setf (process-substitution-resource-processes resource) nil))))
  resource)

(defstruct (reader-process-substitution-resource
             (:constructor %make-reader-process-substitution-resource
                 (direction parent-fd inner-fd)))
  direction
  parent-fd
  inner-fd)

(defun reader-process-substitution-fd-path (fd)
  (unless (and (integerp fd) (<= 0 fd))
    (error "process substitution fd must be a non-negative integer: ~S" fd))
  (format nil "~A~D" (%process-substitution-fd-directory) fd))

(defun %close-reader-process-substitution-fds (fds)
  (let ((first-error nil))
    (dolist (fd (remove-duplicates fds :test #'eql))
      (when (integerp fd)
        (handler-case
            (sb-posix:close fd)
          (error (condition)
            (unless first-error
              (setf first-error condition))))))
    (when first-error
      (error first-error))))

(defun make-reader-pipeline-pipe (&key avoid-descriptors)
  (unless (and (listp avoid-descriptors)
               (every (lambda (fd)
                        (and (integerp fd) (<= 0 fd)))
                      avoid-descriptors))
    (error "reader pipeline avoid-descriptors must be non-negative integers: ~S"
           avoid-descriptors))
  (let ((read-fd nil)
        (write-fd nil)
        (owned-fds nil)
        (complete-p nil)
        (primary-error nil))
    (unwind-protect
         (handler-bind
             ((error (lambda (condition)
                       (setf primary-error condition))))
           (multiple-value-setq (read-fd write-fd)
             (%spawn-pipe))
           (setf owned-fds (list read-fd write-fd))
           (%spawn-set-close-on-exec read-fd)
           (%spawn-set-close-on-exec write-fd)
           (labels
               ((relocate-endpoint (fd)
                  (if (not (member fd avoid-descriptors :test #'eql))
                      (values fd nil)
                      (loop with minimum = 3
                            for duplicate =
                              (sb-posix:fcntl fd +spawn-f-dupfd+ minimum)
                            do (push duplicate owned-fds)
                               (%spawn-set-close-on-exec duplicate)
                               (if (member duplicate avoid-descriptors
                                           :test #'eql)
                                   (progn
                                     (sb-posix:close duplicate)
                                     (setf owned-fds
                                           (delete duplicate owned-fds
                                                   :test #'eql))
                                     (setf minimum (1+ duplicate)))
                                   (return (values duplicate fd))))))
                (close-owned-fd (fd)
                  (sb-posix:close fd)
                  (setf owned-fds (delete fd owned-fds :test #'eql))))
             (multiple-value-bind (reserved-fd old-fd)
                 (relocate-endpoint read-fd)
               (when old-fd
                 (close-owned-fd old-fd))
               (setf read-fd reserved-fd))
             (multiple-value-bind (reserved-fd old-fd)
                 (relocate-endpoint write-fd)
               (when old-fd
                 (close-owned-fd old-fd))
               (setf write-fd reserved-fd)))
           (setf complete-p t)
           (values read-fd write-fd))
      (unless complete-p
        (handler-case
            (%close-reader-process-substitution-fds owned-fds)
          (error (condition)
            (unless primary-error
              (error condition))))))))

(defun %spawn-clear-close-on-exec (fd)
  (let ((flags (sb-posix:fcntl fd +spawn-f-getfd+)))
    (sb-posix:fcntl fd +spawn-f-setfd+
                    (logand flags (lognot +spawn-fd-cloexec+))))
  fd)

(defun close-reader-descriptor (fd)
  (when (integerp fd)
    (sb-posix:close fd)))

(defun make-reader-process-substitution-resource
    (direction &key avoid-descriptors)
  (unless (member direction '(:input :output))
    (error "invalid process substitution direction ~S" direction))
  (%process-substitution-fd-directory)
  (let ((read-fd nil)
        (write-fd nil)
        (complete-p nil))
    (unwind-protect
         (progn
           (multiple-value-setq (read-fd write-fd)
             (make-reader-pipeline-pipe :avoid-descriptors avoid-descriptors))
           (let* ((parent-fd
                    (if (eq direction :input) read-fd write-fd))
                  (inner-fd
                    (if (eq direction :input) write-fd read-fd)))
             (%spawn-clear-close-on-exec parent-fd)
             (let ((resource
                     (%make-reader-process-substitution-resource
                      direction parent-fd inner-fd)))
               (setf complete-p t)
               resource)))
      (unless complete-p
        (%close-reader-process-substitution-fds
         (list read-fd write-fd))))))

(defun close-reader-process-substitution-resource (resource)
  (unless (reader-process-substitution-resource-p resource)
    (error "not a reader process-substitution resource: ~S" resource))
  (let ((fds (list
              (reader-process-substitution-resource-parent-fd resource)
              (reader-process-substitution-resource-inner-fd resource))))
    (setf (reader-process-substitution-resource-parent-fd resource) nil
          (reader-process-substitution-resource-inner-fd resource) nil)
    (%close-reader-process-substitution-fds fds))
  resource)
