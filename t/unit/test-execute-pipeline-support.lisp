(in-package #:nshell/test)

(defmacro with-os-environment-variable ((name value) &body body)
  `(let* ((var ,name)
          (old (host-kit:getenv var))
          (had-old old))
     (unwind-protect
          (progn
            (sb-posix:setenv var ,value 1)
            ,@body)
       (if had-old
           (sb-posix:setenv var old 1)
           (sb-posix:unsetenv var)))))

(defun %execute-pipeline-sbcl-command-node (form &optional extra-args)
  (nshell.domain.parsing:make-command-node
   (current-sbcl-executable)
   (append (list "--noinform"
                 "--non-interactive"
                 "--disable-debugger"
                 "--eval"
                 (nshell.domain.parsing:make-command-arg form :single))
           extra-args)))
