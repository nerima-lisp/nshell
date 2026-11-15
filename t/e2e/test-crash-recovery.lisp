;;; Real-process acceptance for crash recovery (task P0-4): a builtin that
;;; fails on purpose must leave the terminal usable and the history intact.
(in-package #:nshell/test)

(defparameter +crash-e2e-builtin-forms+
  (list
   ;; Test-only builtins, registered in the child before MAIN runs; production
   ;; code has no way to define them. P04-DEEP recurses until the control
   ;; stack is exhausted.
   "(funcall (find-symbol \"REGISTER-BUILTIN\" \"NSHELL.APPLICATION\")
             \"p04-crash\"
             (funcall (find-symbol \"MAKE-BUILTIN-BINDING\" \"NSHELL.APPLICATION\")
                      (lambda (context arguments)
                        (declare (ignore context arguments))
                        (error \"p04 deliberate failure\"))
                      :argv))"
   "(funcall (find-symbol \"REGISTER-BUILTIN\" \"NSHELL.APPLICATION\")
             \"p04-deep\"
             (funcall (find-symbol \"MAKE-BUILTIN-BINDING\" \"NSHELL.APPLICATION\")
                      (lambda (context arguments)
                        (declare (ignore context arguments))
                        (labels ((deep (n) (1+ (deep (1+ n)))))
                          (deep 0)))
                      :argv))"))

(defun %crash-e2e-arguments (main-arguments &key history-path)
  (append (list "--noinform" "--disable-debugger")
          (%asdf-bootstrap-forms
           (namestring (asdf:system-source-directory :nshell)))
          (list "--eval"
                "(let ((*error-output* (make-broadcast-stream))
                       (*standard-output* (make-broadcast-stream)))
                   (asdf:load-system :nshell))")
          (loop for form in +crash-e2e-builtin-forms+
                collect "--eval" collect form)
          (when history-path
            (list "--eval"
                  (format nil "(set (find-symbol ~S ~S) ~S)"
                          "*HISTORY-FILE-PATH-OVERRIDE*"
                          "NSHELL.INFRASTRUCTURE.PERSISTENCE" history-path)))
          (list "--eval" (%nshell-main-form main-arguments))))

(defun %crash-e2e-logs (state-home)
  (directory (merge-pathnames "nshell/crash/*.log"
                              (uiop:ensure-directory-pathname state-home))))

(defun %crash-e2e-run-pty (state-home history-path action)
  "Run nshell under a PTY with the test builtins and XDG_STATE_HOME set to
STATE-HOME, call ACTION with the master fd and the child pid, and return the
child's exit code."
  (let ((program (%absolute-sbcl-executable))
        (pty nil))
    (unless program
      (skip "requires an absolute SBCL runtime path"))
    (unwind-protect
         (progn
           (setf pty (%e2e-pty-spawn
                      program
                      (%crash-e2e-arguments '("--no-config")
                                            :history-path history-path)
                      :rows 24 :cols 100
                      :environment
                      (cons (format nil "XDG_STATE_HOME=~a" state-home)
                            (%e2e-child-environment))))
           (let ((fd (nshell.infrastructure.acl:pty-process-master-fd pty))
                 (pid (nshell.infrastructure.acl:pty-process-pid pty)))
             (%e2e-pty-await-startup fd pid)
             (funcall action fd pid)
             (%assert-pty-child-exit pty 0)))
      (%terminate-pty-process pty))))

(describe "crash-recovery-e2e"
  (it "a-failing-builtin-leaves-the-terminal-cooked-for-commands-and-keeps-history"
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "launches real nshell under a PTY"
      (host-kit:with-temporary-directory (root)
        (let ((state-home (namestring (merge-pathnames "state/" root)))
              (history-path (namestring (merge-pathnames "history" root)))
              (stty-check
                (concatenate
                 'string
                 "sh -c 'stty -a | grep -Eq \"(^|[[:space:];])icanon([[:space:];]|$)\""
                 " && printf \"%s%s\\n\" P04_CANON_ OK;"
                 " stty -a | grep -Eq \"(^|[[:space:];])echo([[:space:];]|$)\""
                 " && printf \"%s%s\\n\" P04_ECHO_ OK;"
                 " printf \"%s%s\\n\" P04_CHECK_ DONE'")))
          (ensure-directories-exist state-home)
          (%crash-e2e-run-pty
           state-home history-path
           (lambda (fd pid)
             (%e2e-pty-write-line fd "printf 'p04-before:<%s>\\n' ok")
             (%e2e-pty-read-until fd "p04-before:<ok>" :process-id pid)
             (%e2e-pty-write-line fd "p04-crash")
             (let ((crash-output (%e2e-pty-read-until fd "nshell: crash log: "
                                                      :process-id pid)))
               (expect (search "nshell error: p04 deliberate failure" crash-output)
                       :to-be-truthy))
             ;; The joined marker appears only in the command's output, not in
             ;; the echoed input line.
             (%e2e-pty-write-line fd stty-check)
             (let ((check-output (%e2e-pty-read-until fd "P04_CHECK_DONE"
                                                      :process-id pid)))
               (expect (search "P04_CANON_OK" check-output) :to-be-truthy)
               (expect (search "P04_ECHO_OK" check-output) :to-be-truthy))
             (%e2e-pty-write-line fd "printf 'p04-after:<%s>\\n' ok")
             (%e2e-pty-read-until fd "p04-after:<ok>" :process-id pid)
             (%e2e-pty-write-line fd "exit")
             (expect (search "Goodbye!" (%e2e-pty-read-until fd "Goodbye!"
                                                             :process-id pid))
                     :to-be-truthy)))
          (let ((nshell.infrastructure.persistence::*history-file-path-override*
                  history-path))
            (expect '("printf 'p04-before:<%s>\\n' ok" "p04-crash")
                    :to-equal
                    (subseq (mapcar #'nshell.infrastructure.persistence:history-record-text
                                    (nshell.infrastructure.persistence:load-history-file))
                            0 2))
            (expect (find "printf 'p04-after:<%s>\\n' ok"
                          (mapcar #'nshell.infrastructure.persistence:history-record-text
                                  (nshell.infrastructure.persistence:load-history-file))
                          :test #'string=)
                    :to-be-truthy))
          (let ((logs (%crash-e2e-logs state-home)))
            (expect 1 :to-equal (length logs))
            (expect #o600 :to-equal (logand #o777 (sb-posix:stat-mode
                                                   (sb-posix:stat (namestring (first logs))))))
            (expect (search "p04 deliberate failure" (uiop:read-file-string (first logs)))
                    :to-be-truthy))))))

  (it "three-crashes-at-one-place-list-jobs-and-ask-about-safe-mode"
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "launches real nshell under a PTY"
      (host-kit:with-temporary-directory (root)
        (let ((state-home (namestring (merge-pathnames "state/" root))))
          (ensure-directories-exist state-home)
          (%crash-e2e-run-pty
           state-home nil
           (lambda (fd pid)
             (%e2e-pty-write-line fd "/bin/sleep 30 &")
             (%e2e-pty-write-line fd "printf 'p04-job:<%s>\\n' started")
             (%e2e-pty-read-until fd "p04-job:<started>" :process-id pid)
             (dotimes (i 2)
               (%e2e-pty-write-line fd "p04-crash")
               (expect (search "Restart nshell"
                               (%e2e-pty-read-until fd "nshell: crash log: "
                                                    :process-id pid))
                       :to-be-null))
             (%e2e-pty-write-line fd "p04-crash")
             (let* ((output (%e2e-pty-read-until fd "[y/N]" :process-id pid))
                    (job (search "sleep 30" output))
                    (question (search "Restart nshell with --safe?" output)))
               (expect (search "the same error occurred 3 times in a row" output)
                       :to-be-truthy)
               (expect (search "nshell: running jobs:" output) :to-be-truthy)
               (expect (and job question (< job question)) :to-be-truthy))
             (nshell.infrastructure.acl:pty-write fd "n")
             (%e2e-pty-write-line fd "printf 'p04-continued:<%s>\\n' yes")
             (%e2e-pty-read-until fd "p04-continued:<yes>" :process-id pid)
             (%e2e-pty-write-line fd "kill %1")
             (%e2e-pty-write-line fd "wait")
             (%e2e-pty-write-line fd "printf 'p04-reaped:<%s>\\n' yes")
             (%e2e-pty-read-until fd "p04-reaped:<yes>" :process-id pid)
             (%e2e-pty-write-line fd "exit")
             (%e2e-pty-read-until fd "Goodbye!" :process-id pid)))
          (expect 3 :to-equal (length (%crash-e2e-logs state-home)))))))

  (it "batch-stack-exhaustion-is-reported-logged-and-exits-with-status-one"
    (host-kit:with-temporary-directory (root)
      (let* ((state-home (namestring (merge-pathnames "state/" root)))
             ;; Not --script: it implies --lose-on-corruption, which turns
             ;; control stack exhaustion into a fatal runtime error.
             (program (cons (current-sbcl-executable)
                            (%crash-e2e-arguments '("--command" "p04-deep"))))
             (result (host-kit:run-program
                      (first program) (rest program)
                      :directory (asdf:system-source-directory :nshell)
                      :input ""
                      :environment
                      (cons (format nil "XDG_STATE_HOME=~a" state-home)
                            (%e2e-child-environment))
                      :timeout 120))
             (stderr (host-kit:process-result-stderr result)))
        (expect 1 :to-equal (host-kit:process-result-exit-code result))
        (expect (search "nshell error: storage exhausted" stderr) :to-be-truthy)
        (expect (search "nshell: crash log: " stderr) :to-be-truthy)
        (expect (search "fatal error" stderr) :to-be-null)
        (let ((logs (%crash-e2e-logs state-home)))
          (expect 1 :to-equal (length logs))
          (expect (search "condition: SB-KERNEL::CONTROL-STACK-EXHAUSTED"
                          (uiop:read-file-string (first logs)))
                  :to-be-truthy))))))
