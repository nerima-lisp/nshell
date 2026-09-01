(in-package #:nshell.application)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro define-builtin (name lambda-list ignore-variables &body body)
    `(defun ,name ,lambda-list
       ,@(when ignore-variables
           `((declare (ignore ,@ignore-variables))))
       ,@body))

  (defmacro define-status-builtin (name status)
    `(define-builtin ,name (context args) (context args)
       (values nil ,status)))

  (defmacro define-job-selection-builtin (name operation)
    (let ((command (string-downcase (symbol-name operation)))
          (job-monitor (gensym "JOB-MONITOR-"))
          (job-id (gensym "JOB-ID-"))
          (job (gensym "JOB-")))
      `(defun ,name (context args)
         (let* ((,job-monitor (shell-context-job-monitor context))
                (,job-id (%resolve-job-id ,job-monitor args :active-only-p t))
                (,job (,operation ,job-id ,job-monitor)))
           (if ,job
               (values nil 0)
               (values (%missing-job-output ,command (%job-spec-label args))
                       1)))))))
