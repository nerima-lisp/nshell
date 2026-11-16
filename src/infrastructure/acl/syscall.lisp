(in-package #:nshell.infrastructure.acl)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix)
  (nshell.domain.completion:%configure-path-command-cache-locks
    (lambda ()
      (let ((mutex (sb-thread:make-mutex :name "PATH command directory cache")))
        (cl-boundary-kit:make-lock
          :acquire-fn
          (lambda ()
            (sb-thread:grab-mutex mutex))
          :release-fn
          (lambda ()
            (sb-thread:release-mutex mutex)))))))

(defconstant +path-command-parallel-directory-threshold+ 4)
(defconstant +path-command-parallel-batch-limit+ 4)

(defun map-path-command-directories (function directories)
  (let ((directory-count (length directories)))
    (if (< directory-count +path-command-parallel-directory-threshold+)
        (mapcar function directories)
        (let* ((batch-count (min directory-count +path-command-parallel-batch-limit+))
               (base-batch-size (floor directory-count batch-count))
               (larger-batch-count (mod directory-count batch-count))
               (batches
                 (loop with start = 0
                       for batch-index below batch-count
                       for batch-size = (+ base-batch-size
                                           (if (< batch-index larger-batch-count) 1 0))
                       collect (prog1 (subseq directories start (+ start batch-size))
                                 (incf start batch-size)))))
          (cl-concurrent-kit:with-task-scope (scope)
            (let ((promises
                    (mapcar
                     (lambda (batch)
                       (cl-concurrent-kit:spawn
                        scope
                        (lambda ()
                          (mapcar function batch))))
                     batches)))
              (mapcan
               (lambda (promise)
                 (cl-concurrent-kit:await promise))
               promises)))))))

;;; Syscall integration is split by responsibility:
;;; - syscall-foreign.lisp: alien declarations and platform constants
;;; - syscall-environment.lisp: subprocess environment state
;;; - syscall-redirection.lisp: redirect data helpers
;;; - syscall-process.lisp: single process execution
;;; - syscall-pipeline.lisp: OS pipe execution
;;; - syscall-job-control.lisp: process groups and wait status
;;; - syscall-terminal.lisp: terminal ioctl helpers
