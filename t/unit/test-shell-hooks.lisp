(in-package #:nshell/test)

(describe "shell-hooks"
  (it "runs callbacks in registration order and removes them by identity"
    (let* ((events nil)
           (first-hook (lambda (value) (push (list :first value) events)))
           (second-hook (lambda (value) (push (list :second value) events))))
      (unwind-protect
           (progn
             (nshell.application:clear-shell-hooks)
             (nshell.application:register-shell-hook "preexec" first-hook)
             (nshell.application:register-shell-hook :preexec first-hook)
             (nshell.application:register-shell-hook :preexec second-hook)
             (nshell.application:run-shell-hooks :preexec "echo hi")
             (expect '((:first "echo hi") (:second "echo hi"))
                     :to-equal (nreverse events))
             (expect t :to-be
                     (nshell.application:remove-shell-hook :preexec first-hook))
             (expect nil :to-be
                     (nshell.application:remove-shell-hook :preexec first-hook)))
        (nshell.application:clear-shell-hooks))))

  (it "reports a callback error and continues with later callbacks"
    (let* ((events nil)
          (failing-hook (lambda () (error "hook failure")))
          (later-hook (lambda () (push :later events))))
      (unwind-protect
           (with-output-to-string (errors)
             (let ((*error-output* errors))
               (nshell.application:clear-shell-hooks)
               (nshell.application:register-shell-hook :postexec failing-hook)
               (nshell.application:register-shell-hook :postexec later-hook)
               (nshell.application:run-shell-hooks :postexec)
               (expect '(:later) :to-equal events)
               (expect t :to-be
                       (not (null (search "postexec hook failed" (get-output-stream-string errors)))))))
        (nshell.application:clear-shell-hooks))))

  (it "rejects unknown hook names"
    (expect t :to-be
            (handler-case
                (progn
                  (nshell.application:register-shell-hook :unknown #'identity)
                  nil)
              (error () t)))))
