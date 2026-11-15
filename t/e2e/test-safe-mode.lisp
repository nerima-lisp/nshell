;;; Real-process acceptance for --safe (task P0-5): a broken init.lisp must not
;;; keep safe mode from reaching an interactive prompt.
(in-package #:nshell/test)

(defun %assert-safe-mode-pty-startup (arguments extra-environment broken-init-line)
  #-(or darwin linux)
  (skip "PTY tests are only supported on Darwin and Linux")
  #+(or darwin linux)
  (skip-when-pty-unavailable "launches real nshell under a PTY"
    (let ((program (%absolute-sbcl-executable))
          (pty nil))
      (unless program
        (skip "requires an absolute SBCL runtime path"))
      (host-kit:with-temporary-directory (config-home)
        (let ((init-path (merge-pathnames
                          #P"nshell/init.lisp"
                          (uiop:ensure-directory-pathname config-home))))
          (ensure-directories-exist init-path)
          (with-open-file (stream init-path :direction :output
                                            :if-exists :supersede
                                            :if-does-not-exist :create)
            (write-line broken-init-line stream)))
        (unwind-protect
             (progn
               (setf pty
                     (%e2e-pty-spawn
                      program
                      (append (list "--noinform" "--disable-debugger")
                              (%asdf-bootstrap-forms
                               (namestring (asdf:system-source-directory :nshell)))
                              (list "--eval" (%nshell-main-form arguments)))
                      :rows 24 :cols 100
                      :environment
                      (append (list (format nil "XDG_CONFIG_HOME=~a"
                                            (namestring config-home)))
                              extra-environment
                              (%e2e-child-environment))))
               (let ((fd (nshell.infrastructure.acl:pty-process-master-fd pty))
                     (pid (nshell.infrastructure.acl:pty-process-pid pty)))
                 ;; The first prompt can arrive in the same read as the startup
                 ;; marker, so search both outputs.
                 (let ((startup (%e2e-pty-await-startup fd pid)))
                   (expect (or (search "[safe] " startup)
                               (search "[safe] "
                                       (%e2e-pty-read-until fd "[safe] " :process-id pid)))
                           :to-be-truthy))
                 (%e2e-pty-write-line fd "exit")
                 (expect (search "Goodbye!" (%e2e-pty-read-until fd "Goodbye!"))
                         :to-be-truthy)
                 (%assert-pty-child-exit pty 0)))
          (%terminate-pty-process pty))))))

(describe "safe-mode-e2e"
  (it "safe-flag-starts-despite-an-init-lisp-infinite-loop"
    (%assert-safe-mode-pty-startup '("--safe" "--no-history") nil "(loop)"))

  (it "nshell-safe-starts-despite-an-init-lisp-syntax-error"
    (%assert-safe-mode-pty-startup '() '("NSHELL_SAFE=1") "(defun broken-p0-5-init ("))

  (it "safe-flag-starts-despite-an-init-lisp-undefined-function-call"
    (%assert-safe-mode-pty-startup '("--safe" "--no-history") nil
                                   "(nshell-p0-5-undefined-function-probe)")))
