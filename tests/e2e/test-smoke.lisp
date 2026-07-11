(in-package #:nshell/test)
(def-suite e2e-tests :description "E2E smoke tests" :in nshell-tests)
(in-suite e2e-tests)

(defparameter +main-usage-line+
  "Usage: nshell [--help] [--version] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]")

(defun %expected-substrings (expected)
  (cond ((null expected) nil)
        ((listp expected) expected)
        (t (list expected))))

(defun %nshell-main-form (arguments)
  (format nil
          "(progn
             (asdf:load-system :nshell)
             (let ((sb-ext:*posix-argv* (list ~{~S~^ ~})))
               (funcall (symbol-function (find-symbol \"MAIN\" \"NSHELL\")))))"
          (cons "nshell" arguments)))

(defun %asdf-bootstrap-forms (root)
  (let ((cl-prolog-root
          (namestring
           (uiop:ensure-directory-pathname
            (merge-pathnames "../cl-prolog/" root)))))
    (list "--eval" "(require :asdf)"
          "--eval" (format nil "(pushnew (truename ~S) asdf:*central-registry* :test #'equal)" root)
          "--eval" (format nil "(pushnew (truename ~S) asdf:*central-registry* :test #'equal)" cl-prolog-root))))

(defun %run-nshell-main (arguments &key input)
  ; Use file-based I/O to avoid pipe fd exhaustion in hermetic build sandboxes.
  ; The :output :string approach creates a stdout pipe whose read-fd can become
  ; invalid (EBADF on select) when fd-stream finalizers race with pipe creation
  ; after many source files are compiled. Writing to temp files is race-free.
  (let ((root (asdf:system-source-directory :nshell))
        (program (append (list (current-sbcl-executable)
                               "--noinform")
                         (%asdf-bootstrap-forms (namestring (asdf:system-source-directory :nshell)))
                         (list "--eval" (%nshell-main-form arguments)))))
    (uiop:with-temporary-file (:pathname stdout-file)
      (uiop:with-temporary-file (:pathname stderr-file)
        (flet ((run-main (&key input-stream)
                 (nth-value 2
                   (uiop:run-program
                    program
                    :directory root
                    :input (or input-stream nil)
                    :output stdout-file
                    :error-output stderr-file
                    :if-output-exists :supersede
                    :if-error-output-exists :supersede
                    :ignore-error-status t
                    :timeout 120))))
          (let ((exit-code
                  (if input
                      (with-input-from-string (input-stream input)
                        (run-main :input-stream input-stream))
                      (run-main))))
            (values (uiop:read-file-string stdout-file)
                    (uiop:read-file-string stderr-file)
                    exit-code)))))))

(defun %assert-nshell-main-result (arguments expected-output expected-code
                                 &key expected-error input)
  (multiple-value-bind (stdout stderr exit-code)
      (%run-nshell-main arguments :input input)
    (is (= expected-code exit-code))
    (when expected-output
      (dolist (expected-substring (%expected-substrings expected-output))
        (is (search expected-substring stdout)
            "stdout should contain ~S, got ~S"
            expected-substring stdout)))
    (when expected-error
      (dolist (expected-substring (%expected-substrings expected-error))
        (is (search expected-substring stderr)
            "stderr should contain ~S, got ~S"
            expected-substring stderr)))
    (unless expected-error
      (is (string= "" stderr)))
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

(test e2e-echo-command
  (with-complete-command-line (result ast "echo hello world")
    (is (nshell.domain.parsing:command-node-p ast))
    (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
    (is (equal '("hello" "world") (nshell.domain.parsing:command-node-arg-values ast)))))
(test e2e-full-repl-cycle
  (let* ((history (nshell.domain.history:make-command-history))
         (line "pwd"))
    (with-parsed-command-line (result line)
      (is (nshell.domain.parsing:parse-complete-p result)))
    (nshell.domain.history:history-add history line)
    (is (= 1 (nshell.domain.history:history-size history)))))

(test e2e-main-help-exits-cleanly
  "The entry point prints usage text and exits successfully for --help."
  (%assert-nshell-main-result '("--help")
                              (list +main-usage-line+
                                    "With -c/--command, nshell executes COMMAND once in batch mode (ARGS are $argv)."
                                    "With a SCRIPT file argument, nshell runs the script (ARGS are $argv).")
                              0))

(test e2e-main-version-exits-cleanly
  "The entry point prints a version banner and exits successfully for --version."
  (%assert-nshell-main-result '("--version")
                              "nshell v"
                              0))

(test e2e-main-interactive-pty-smoke
  "The public entry point runs an interactive command loop under a real PTY."
  #-(or darwin linux)
  (skip "PTY tests are only supported on Darwin and Linux")
  #+(or darwin linux)
  (skip-in-sandbox "launches real nshell under a PTY"
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
                (is (search "nshell v" (%e2e-pty-read-until fd "nshell v")))
                (%e2e-pty-write-line fd "echo pty-e2e-ready")
                (is (search "pty-e2e-ready"
                            (%e2e-pty-read-until fd "pty-e2e-ready")))
                (%e2e-pty-write-line fd "exit")
                (is (search "Goodbye!" (%e2e-pty-read-until fd "Goodbye!")))
                (is (%wait-pty-child-exit pty :attempts 80 :delay 0.05))))
        (%terminate-pty-process pty)))))

(test e2e-main-interactive-pty-ctrl-c-recovers-foreground-command
  "Ctrl-C interrupts a foreground command and returns to the public interactive prompt."
  #-(or darwin linux)
  (skip "PTY tests are only supported on Darwin and Linux")
  #+(or darwin linux)
  (skip-in-sandbox "launches real nshell under a PTY"
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
               (is (search "nshell v" (%e2e-pty-read-until fd "nshell v")))
               (%e2e-pty-write-line fd "echo ctrl-c-probe-ready")
               (is (search "ctrl-c-probe-ready"
                           (%e2e-pty-read-until fd "ctrl-c-probe-ready")))
               (%e2e-pty-write-line fd "/bin/sleep 10")
               (sleep 0.2)
               (nshell.infrastructure.acl:pty-write fd (string (code-char 3)))
               (sleep 0.2)
               (%e2e-pty-write-line fd "echo after-ctrl-c")
               (let ((output (%e2e-pty-read-until fd "after-ctrl-c" :attempts 220)))
                 (is (search "after-ctrl-c" output))
                 (is (not (search "SB-SYS:INTERACTIVE-INTERRUPT" output)))
                 (is (not (search "unhandled" output :test #'char-equal))))
               (%e2e-pty-write-line fd "exit")
               (is (search "Goodbye!" (%e2e-pty-read-until fd "Goodbye!")))
               (is (%wait-pty-child-exit pty :attempts 80 :delay 0.05))))
        (%terminate-pty-process pty)))))

(test e2e-main-interactive-pty-job-control-lifecycle
  "The public entry point exposes background job state and fg completion under a real PTY."
  #-(or darwin linux)
  (skip "PTY tests are only supported on Darwin and Linux")
  #+(or darwin linux)
  (skip-in-sandbox "launches real nshell under a PTY"
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
               (is (search "nshell v" (%e2e-pty-read-until fd "nshell v")))
               (%e2e-pty-write-line fd "/bin/sleep 3 &")
               (%e2e-pty-write-line fd "jobs")
               (let ((running-output (%e2e-pty-read-until fd "Running")))
                 (is (search "Running" running-output))
                 (is (search "/bin/sleep 3" running-output)))
               (%e2e-pty-write-line fd "fg 1")
               (%e2e-pty-write-line fd "jobs")
               (let ((done-output (%e2e-pty-read-until fd "Done" :attempts 220)))
                 (is (search "Done" done-output))
                 (is (search "/bin/sleep 3" done-output)))
               (%e2e-pty-write-line fd "exit")
               (is (search "Goodbye!" (%e2e-pty-read-until fd "Goodbye!")))
               (is (%wait-pty-child-exit pty :attempts 80 :delay 0.05))))
        (%terminate-pty-process pty)))))

(test e2e-main-invalid-args-report-usage
  "The entry point rejects unsupported option flags with a usage message."
  (%assert-nshell-main-result '("--unknown")
                              nil
                              1
                              :expected-error +main-usage-line+))
