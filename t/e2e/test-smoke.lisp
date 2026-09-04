(in-package #:nshell/test)

(defparameter +main-usage-line+
  "Usage: nshell [OPTIONS] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]")

(defun %expected-substrings (expected)
  (cond ((null expected) nil)
        ((listp expected) expected)
        (t (list expected))))

(defun %nshell-main-form (arguments)
  "Build the subprocess form used by the command-line integration tests."
  (format nil
          "(progn
             (let ((*error-output* (make-broadcast-stream)))
               (asdf:load-system :nshell))
             (let ((sb-ext:*posix-argv* (list ~{~S~^ ~})))
               (funcall (symbol-function (find-symbol \"MAIN\" \"NSHELL\")))))"
          (cons "nshell" arguments)))

(defun %nshell-main-form-with-timeout (arguments timeout-seconds)
  "Build a subprocess form with an explicit external-command timeout."
  (format nil
          "(progn
             (let ((*error-output* (make-broadcast-stream)))
               (asdf:load-system :nshell))
             (set (find-symbol \"*EXTERNAL-COMMAND-TIMEOUT*\" \"NSHELL.INFRASTRUCTURE.ACL\") ~a)
             (let ((sb-ext:*posix-argv* (list ~{~S~^ ~})))
               (funcall (symbol-function (find-symbol \"MAIN\" \"NSHELL\")))))"
          timeout-seconds
          (cons "nshell" arguments)))

(defun %asdf-bootstrap-forms (root)
  "Return ASDF setup forms for ROOT and its loaded dependencies."
  (let ((dependency-roots
          (loop for system in +nshell-runtime-dependencies+
                collect (namestring (asdf:system-source-directory system)))))
    (list* "--eval" "(require :asdf)"
           "--eval" (format nil "(pushnew (truename ~S) asdf:*central-registry* :test #'equal)" root)
           (loop for dependency-root in dependency-roots
                 collect "--eval"
                 collect (format nil "(pushnew (truename ~S) asdf:*central-registry* :test #'equal)"
                                 dependency-root)))))

(defun %executable-on-path-p (path)
  (ignore-errors
   (not (zerop (logand (sb-posix:stat-mode (sb-posix:stat path)) #o111)))))

(defun %resolve-real-external-executable (name)
  "Resolve NAME to an executable path, bypassing nshell builtins."
  (or (first (nshell.domain.completion:command-path-candidates
              name
              (or (sb-ext:posix-getenv "PATH") "")
              #'%executable-on-path-p))
      (error "e2e test setup: ~a not found on PATH" name)))

(defun %run-nshell-main (arguments &key input)
  (let* ((root (asdf:system-source-directory :nshell))
         (program (append (list (current-sbcl-executable)
                                "--noinform")
                          (%asdf-bootstrap-forms (namestring root))
                          (list "--eval" (%nshell-main-form arguments))))
         (result (host-kit:run-program (first program) (rest program)
                                       :directory root
                                       :input input
                                       :timeout 120)))
    (values (host-kit:process-result-stdout result)
            (host-kit:process-result-stderr result)
            (host-kit:process-result-exit-code result))))

(defun %assert-nshell-main-result (arguments expected-output expected-code
                                 &key expected-error input)
  (multiple-value-bind (stdout stderr exit-code)
      (%run-nshell-main arguments :input input)
    (expect expected-code :to-equal exit-code)
    (when expected-output
      (dolist (expected-substring (%expected-substrings expected-output))
        (expect (search expected-substring stdout) :to-be-truthy)))
    (when expected-error
      (dolist (expected-substring (%expected-substrings expected-error))
        (expect (search expected-substring stderr) :to-be-truthy)))
    (unless expected-error
      (expect "" :to-equal stderr))
    (values stdout stderr exit-code)))

(defun %existing-program-path (program)
  (when program
    (ignore-errors
      (let ((pathname (probe-file program)))
        (when pathname
          (namestring (truename pathname)))))))

(defun %absolute-sbcl-executable ()
  (or (%existing-program-path (current-sbcl-executable))
      #+sbcl
      (%existing-program-path sb-ext:*runtime-pathname*)
      #-sbcl nil))

(defun %nshell-main-pty-arguments ()
  (let ((root (namestring (asdf:system-source-directory :nshell))))
    (append (list "--noinform"
                  "--disable-debugger")
            (%asdf-bootstrap-forms root)
            (list "--eval" (%nshell-main-form nil)))))

(defun %nshell-main-pty-arguments-with-timeout (timeout-seconds)
  "Like %NSHELL-MAIN-PTY-ARGUMENTS, but overrides
*EXTERNAL-COMMAND-TIMEOUT* before MAIN runs, so a real-PTY test can prove the
timeout is skipped for a foreground command connected to an interactive
terminal without waiting out the real (30s) default."
  (let ((root (namestring (asdf:system-source-directory :nshell))))
    (append (list "--noinform"
                  "--disable-debugger")
            (%asdf-bootstrap-forms root)
            (list "--eval" (%nshell-main-form-with-timeout nil timeout-seconds)))))

(defun %e2e-pty-read-available (fd &key (timeout-usec 100000) (limit 8192))
  (let ((buffer (make-array limit :element-type '(unsigned-byte 8))))
    (sb-alien:with-alien ((read-fds (sb-alien:struct sb-unix:fd-set)))
      (sb-unix:fd-zero (sb-alien:addr read-fds))
      (sb-unix:fd-set fd (sb-alien:addr read-fds))
      (multiple-value-bind (ready errno)
          (sb-unix:unix-fast-select (1+ fd) (sb-alien:addr read-fds) nil nil 0 timeout-usec)
        (declare (ignore errno))
        (when (and ready (plusp ready) (sb-unix:fd-isset fd (sb-alien:addr read-fds)))
          (let ((count (ignore-errors
                         (nshell.infrastructure.acl:pty-read fd buffer limit))))
            (when (and count (plusp count))
              (octets->string buffer count))))))))

(defun %e2e-pty-read-until (fd needle &key (timeout 15.0) attempts (delay 0.05))
  (let ((output ""))
    (flet ((check-output ()
             (when (search needle output :test #'char-equal)
               (return-from %e2e-pty-read-until output))))
      (if attempts
          (loop repeat attempts
                do (let ((chunk (%e2e-pty-read-available fd)))
                     (when chunk
                       (setf output (concatenate 'string output chunk))
                       (check-output)))
                   (sleep delay))
          (let ((deadline (+ (get-internal-real-time)
                             (round (* timeout internal-time-units-per-second)))))
            (loop while (< (get-internal-real-time) deadline)
                  do (let ((chunk (%e2e-pty-read-available fd)))
                       (when chunk
                         (setf output (concatenate 'string output chunk))
                         (check-output)))))))
    output))

(defun %e2e-pty-write-line (fd line)
  (nshell.infrastructure.acl:pty-write fd (format nil "~A~%" line)))

(defun %wait-pty-child-exit (pty &key (attempts 40) (delay 0.05))
  (loop repeat attempts
        for status = (multiple-value-list
                      (nshell.infrastructure.acl:wait-job
                       (nshell.infrastructure.acl:pty-process-pid pty)
                       :nohang t))
        when (member (second status) '(:exited :signaled :no-child))
          do (return status)
        do (sleep delay)
        finally (return nil)))

(defun %terminate-pty-process (pty)
  (when pty
    (unless (%wait-pty-child-exit pty :attempts 1 :delay 0)
      (ignore-errors
        (nshell.infrastructure.acl:kill-process
         (- (nshell.infrastructure.acl:pty-process-pgid pty)) :sigterm))
      (unless (%wait-pty-child-exit pty :attempts 20 :delay 0.05)
        (ignore-errors
          (nshell.infrastructure.acl:kill-process
           (- (nshell.infrastructure.acl:pty-process-pgid pty)) 9))
        (%wait-pty-child-exit pty :attempts 20 :delay 0.05)))
    (ignore-errors
      (close (nshell.infrastructure.acl:pty-process-stream pty)))))

(describe "e2e-tests"
  (it "e2e-echo-command"
    (with-complete-command-line (result ast "echo hello world")
      (expect (nshell.domain.parsing:command-node-p ast) :to-be-truthy)
      (expect "echo" :to-equal (nshell.domain.parsing:command-node-command ast))
      (expect '("hello" "world") :to-equal (nshell.domain.parsing:command-node-arg-values ast))))
  (it "e2e-full-repl-cycle"
    (let* ((history (history-kit:make-history))
           (line "pwd"))
      (with-parsed-command-line (result line)
        (expect (nshell.domain.parsing:parse-complete-p result) :to-be-truthy))
      (history-kit:history-add history line)
      (expect 1 :to-equal (history-kit:history-count history))))

  (it "e2e-main-help-exits-cleanly"
    "The entry point prints usage text and exits successfully for --help."
    (%assert-nshell-main-result '("--help")
                                (list +main-usage-line+
                                      "With -c/--command, nshell executes COMMAND once in batch mode (ARGS are $argv)."
                                      "With a SCRIPT file argument, nshell runs the script (ARGS are $argv).")
                                0))

  (it "e2e-main-version-exits-cleanly"
    "The entry point prints a version banner and exits successfully for --version."
    (%assert-nshell-main-result '("--version")
                                "nshell v"
                                0))

  (it "e2e-main-background-pid-is-shell-visible"
    "A background command publishes its process ID through $!."
    (multiple-value-bind (stdout stderr exit-code)
        (%run-nshell-main '("-c" "true & echo $!"))
      (expect 0 :to-equal exit-code)
      (expect "" :to-equal stderr)
      (let ((pid (ignore-errors
                    (parse-integer
                     (string-trim '(#\Space #\Tab #\Newline #\Return)
                                  stdout)))))
        (expect (and pid (plusp pid)) :to-be-truthy))))
  (it "e2e-main-wait-returns-background-status"
    "wait propagates a background command's final status."
    (multiple-value-bind (stdout stderr exit-code)
        (%run-nshell-main '("-c" "false & wait %1"))
      (expect 1 :to-equal exit-code)
      (expect "" :to-equal stderr)
      (expect "" :to-equal stdout)))
  (it "e2e-main-wait-without-jobs-is-successful"
    "wait without job arguments succeeds when there are no jobs."
    (multiple-value-bind (stdout stderr exit-code)
        (%run-nshell-main '("-c" "wait"))
      (expect 0 :to-equal exit-code)
      (expect "" :to-equal stderr)
      (expect "" :to-equal stdout)))
  (progn
  (it "e2e-main-status-variable-follows-last-command"
    "$status mirrors the most recent command exit code."
    (multiple-value-bind (stdout stderr exit-code)
        (%run-nshell-main (list "-c" "false; printf \"%s\\n\" $status"))
      (expect 0 :to-equal exit-code)
      (expect "" :to-equal stderr)
      (expect (format nil "1~%") :to-equal stdout)))
  (it "e2e-main-pipestatus-reports-source-order"
    "$pipestatus exposes each internal pipeline stage in source order."
    (multiple-value-bind (stdout stderr exit-code)
        (%run-nshell-main
         (list "-c"
               "false | true; printf \"<%s,%s>\\n\" $pipestatus"))
      (expect 0 :to-equal exit-code)
      (expect "" :to-equal stderr)
      (expect (format nil "<1,0>~%") :to-equal stdout)))
  (it "e2e-main-pipestatus-reports-external-stage-statuses"
    "$pipestatus exposes each external pipeline stage in source order."
    (multiple-value-bind (stdout stderr exit-code)
        (%run-nshell-main
         (list "-c"
               "sh -c 'exit 3' | sh -c 'exit 0'; printf \"<%s,%s>\\n\" $pipestatus"))
      (expect 0 :to-equal exit-code)
      (expect "" :to-equal stderr)
      (expect (format nil "<3,0>~%") :to-equal stdout))))
  (it "e2e-main-adjacent-quoted-fragments-concatenate" "Adjacent quoted and unquoted fragments form one shell word." (multiple-value-bind (stdout stderr exit-code) (%run-nshell-main (list "-c" "printf \"%s\\n\" \"a\"b")) (expect (format nil "ab~%") :to-equal stdout) (expect "" :to-equal stderr) (expect 0 :to-equal exit-code)))
  (it "e2e-main-escaped-dollar-remains-literal" "A backslash protects a dollar from parameter expansion." (multiple-value-bind (stdout stderr exit-code) (%run-nshell-main (list "-c" "printf \"%s\\n\" \\$HOME")) (expect (format nil "\$HOME~%") :to-equal stdout) (expect "" :to-equal stderr) (expect 0 :to-equal exit-code)))
  (it "e2e-main-heredoc-quoted-fragment-delimiter" "Quoted and unquoted delimiter fragments combine into one here-document marker." (multiple-value-bind (stdout stderr exit-code) (%run-nshell-main (list "-c" (format nil "cat << E\"OF\"~%fragment-heredoc~%EOF~%"))) (expect (format nil "fragment-heredoc~%") :to-equal stdout) (expect "" :to-equal stderr) (expect 0 :to-equal exit-code)))

  (it "e2e-main-interactive-pty-smoke"
    "The public entry point runs an interactive command loop under a real PTY."
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
                      program
                      (%nshell-main-pty-arguments)
                      :rows 24
                      :cols 100))
                (let ((fd (nshell.infrastructure.acl:pty-process-master-fd pty)))
                  (expect (search "nshell v" (%e2e-pty-read-until fd "nshell v")) :to-be-truthy)
                  (%e2e-pty-write-line fd "echo pty-e2e-ready")
                  (expect (search "pty-e2e-ready"
                              (%e2e-pty-read-until fd "pty-e2e-ready")) :to-be-truthy)
                  (%e2e-pty-write-line fd "exit")
                  (expect (search "Goodbye!" (%e2e-pty-read-until fd "Goodbye!")) :to-be-truthy)
                  (expect (%wait-pty-child-exit pty :attempts 80 :delay 0.05) :to-be-truthy)))
          (%terminate-pty-process pty)))))

  (it "e2e-main-interactive-pty-ctrl-c-recovers-foreground-command"
    "Ctrl-C interrupts a foreground command and returns to the public interactive prompt."
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
                      program
                      (%nshell-main-pty-arguments)
                      :rows 24
                      :cols 100))
               (let ((fd (nshell.infrastructure.acl:pty-process-master-fd pty)))
                 (expect (search "nshell v" (%e2e-pty-read-until fd "nshell v")) :to-be-truthy)
                 (%e2e-pty-write-line fd "echo ctrl-c-probe-ready")
                 (expect (search "ctrl-c-probe-ready"
                             (%e2e-pty-read-until fd "ctrl-c-probe-ready")) :to-be-truthy)
                 (%e2e-pty-write-line fd "/bin/sleep 10")
                 (sleep 0.2)
                 (nshell.infrastructure.acl:pty-write fd (string (code-char 3)))
                 (sleep 0.2)
                 (%e2e-pty-write-line fd "echo after-ctrl-c")
                 (let ((output (%e2e-pty-read-until fd "after-ctrl-c" :attempts 220)))
                   (expect (search "after-ctrl-c" output) :to-be-truthy)
                   (expect (search "SB-SYS:INTERACTIVE-INTERRUPT" output) :to-be-falsy)
                   (expect (search "unhandled" output :test #'char-equal) :to-be-falsy))
                 (%e2e-pty-write-line fd "exit")
                 (expect (search "Goodbye!" (%e2e-pty-read-until fd "Goodbye!")) :to-be-truthy)
                 (expect (%wait-pty-child-exit pty :attempts 80 :delay 0.05) :to-be-truthy)))
          (%terminate-pty-process pty)))))

  (it "e2e-main-interactive-pty-job-control-lifecycle"
    "The public entry point exposes background job state and fg completion under a real PTY."
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
                      program
                      (%nshell-main-pty-arguments)
                      :rows 24
                      :cols 100))
               (let ((fd (nshell.infrastructure.acl:pty-process-master-fd pty)))
                 (expect (search "nshell v" (%e2e-pty-read-until fd "nshell v")) :to-be-truthy)
                 (%e2e-pty-write-line fd "/bin/sleep 3 &")
                 (%e2e-pty-write-line fd "jobs")
                 (let ((running-output (%e2e-pty-read-until fd "Running")))
                   (expect (search "Running" running-output) :to-be-truthy)
                   (expect (search "/bin/sleep 3" running-output) :to-be-truthy))
                 (%e2e-pty-write-line fd "fg 1")
                 (%e2e-pty-write-line fd "jobs")
                 (let ((done-output (%e2e-pty-read-until fd "Done" :attempts 220)))
                   (expect (search "Done" done-output) :to-be-truthy)
                   (expect (search "/bin/sleep 3" done-output) :to-be-truthy))
                 (%e2e-pty-write-line fd "exit")
                 (expect (search "Goodbye!" (%e2e-pty-read-until fd "Goodbye!")) :to-be-truthy)
                 (expect (%wait-pty-child-exit pty :attempts 80 :delay 0.05) :to-be-truthy)))
          (%terminate-pty-process pty)))))

  (it "e2e-main-interactive-pty-foreground-pipeline-ignores-external-command-timeout"
  "A foreground external pipeline connected to a real interactive terminal."
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
                    program
                    (%nshell-main-pty-arguments-with-timeout 0.5)
                    :rows 24
                    :cols 100))
             (let ((fd (nshell.infrastructure.acl:pty-process-master-fd pty)))
               (expect (search "nshell v" (%e2e-pty-read-until fd "nshell v")) :to-be-truthy)
               (%e2e-pty-write-line fd "sh -c 'sleep 2; echo pty-outlived-timeout' | cat")
               (let ((output (%e2e-pty-read-until fd "pty-outlived-timeout" :attempts 220)))
                 (expect (search "pty-outlived-timeout" output) :to-be-truthy)
                 (expect (search "timed out after" output) :to-be-falsy))
               (%e2e-pty-write-line fd "exit")
               (expect (search "Goodbye!" (%e2e-pty-read-until fd "Goodbye!")) :to-be-truthy)
               (expect (%wait-pty-child-exit pty :attempts 80 :delay 0.05) :to-be-truthy)))
        (%terminate-pty-process pty)))))

  (it "e2e-main-invalid-args-report-usage"
    "The entry point rejects unsupported option flags with a usage message."
    (%assert-nshell-main-result '("--unknown")
                                nil
                                1
                                :expected-error +main-usage-line+)))
