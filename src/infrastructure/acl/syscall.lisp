(in-package #:nshell.infrastructure.acl)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix)
  (nshell.domain.completion::%configure-path-command-cache-locks
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

(defun %map-path-command-directories-with-cck (function directories)
  (if (< (length directories) +path-command-parallel-directory-threshold+)
      (mapcar function directories)
      (cl-concurrent-kit:with-task-scope (scope)
        (mapcar
          (lambda (promise)
            (cl-concurrent-kit:await promise))
          (mapcar
            (lambda (directory)
              (cl-concurrent-kit:spawn
                scope
                (lambda ()
                  (funcall function directory))))
            directories)))))

(eval-when (:load-toplevel :execute)
  (setf nshell.domain.completion::*path-command-directory-map-fn*
        #'%map-path-command-directories-with-cck))

;;; Syscall integration is split by responsibility:
;;; - syscall-foreign.lisp: alien declarations and platform constants
;;; - syscall-environment.lisp: subprocess environment state
;;; - syscall-redirection.lisp: redirect data helpers
;;; - syscall-process.lisp: single process execution
;;; - syscall-pipeline.lisp: OS pipe execution
;;; - syscall-job-control.lisp: process groups and wait status
;;; - syscall-terminal.lisp: terminal ioctl helpers
