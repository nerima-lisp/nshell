(in-package #:nshell/test)

(describe "e2e-signal-tests"
  (it "e2e-main-interactive-pty-ctrl-c-discards-pending-input"
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "launches real nshell under a PTY"
      (let ((program (%absolute-sbcl-executable))
            (pty nil))
        (unless program
          (skip "requires an absolute SBCL runtime path"))
        (unwind-protect
             (progn
               (setf pty
                     (nshell.infrastructure.acl:pty-spawn
                      program (%nshell-main-pty-arguments) :rows 24 :cols 100))
               (let ((fd (nshell.infrastructure.acl:pty-process-master-fd pty)))
                 (%e2e-pty-await-ready fd)
                 (nshell.infrastructure.acl:pty-write fd "exit 91")
                 (expect (search "91" (%e2e-pty-read-until fd "91")) :to-be-truthy)
                 (nshell.infrastructure.acl:pty-write fd (string (code-char 3)))
                 (%e2e-pty-write-line fd "printf 'prompt-recovered:<%s>\\n' yes")
                 (expect (search "prompt-recovered:<yes>"
                                 (%e2e-pty-read-until fd "prompt-recovered:<yes>"))
                         :to-be-truthy)
                 (%e2e-pty-write-line fd "exit")
                 (expect (search "Goodbye!" (%e2e-pty-read-until fd "Goodbye!")) :to-be-truthy)
                 (%assert-pty-child-exit pty)))
          (%terminate-pty-process pty))))))
