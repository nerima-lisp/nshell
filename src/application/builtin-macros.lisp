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

  (defmacro %with-option-terminator-removed ((arguments args) &body body)
    (let ((source (gensym "ARGS-")))
      `(let* ((,source ,args)
              (,arguments (if (and ,source
                                   (string= (first ,source) "--"))
                              (rest ,source)
                              ,source)))
         ,@body)))

  (defmacro define-job-selection-builtin (name operation)
    (let ((command (string-downcase (symbol-name operation)))
          (job-monitor (gensym "JOB-MONITOR-"))
          (job-id (gensym "JOB-ID-"))
          (job (gensym "JOB-")))
      `(define-builtin ,name (context args) ()
         (let* ((,job-monitor (shell-context-job-monitor context))
                (,job-id (%resolve-job-id ,job-monitor args :active-only-p t))
                (,job ,(if (eq operation 'fg)
                           `(flet ((resume-job ()
                                     (fg ,job-id ,job-monitor
                                         (shell-context-process-registry context))))
                              (if *foreground-terminal-runner*
                                  (funcall *foreground-terminal-runner* #'resume-job)
                                  (resume-job)))
                           `(,operation ,job-id ,job-monitor))))
           (if ,job
               (values nil ,(if (eq operation 'fg)
                                `(if (nshell.domain.execution:job-stopped-p ,job)
                                     (+ 128 sb-unix:sigtstp)
                                     (or (nshell.domain.execution:job-exit-code ,job) 0))
                                0))
               (values (%missing-job-output ,command (%job-spec-label args))
                       1)))))))
