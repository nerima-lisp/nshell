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

(defun %run-nshell-main (arguments &key input)
  (let ((root (asdf:system-source-directory :nshell))
        (program (list (current-sbcl-executable)
                       "--noinform"
                       "--eval" "(require :asdf)"
                       "--eval" "(push (truename \"./\") asdf:*central-registry*)"
                       "--eval" (%nshell-main-form arguments))))
    (flet ((run-main (&key input-stream)
             (if input-stream
                 (uiop:run-program
                  program
                  :directory root
                  :input input-stream
                  :output :string
                  :error-output :string
                  :ignore-error-status t)
                 (uiop:run-program
                  program
                  :directory root
                  :output :string
                  :error-output :string
                  :ignore-error-status t))))
      (multiple-value-bind (stdout stderr exit-code)
          (if input
              (with-input-from-string (input-stream input)
                (run-main :input-stream input-stream))
              (run-main))
        (values stdout stderr exit-code)))))

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
    (list "--noinform"
          "--disable-debugger"
          "--eval" "(require :asdf)"
          "--eval" (format nil "(push (truename ~S) asdf:*central-registry*)" root)
          "--eval" (%nshell-main-form nil))))

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

(defun %e2e-pty-read-until (fd needle &key (attempts 120))
  (let ((output ""))
    (dotimes (i attempts output)
      (let ((chunk (%e2e-pty-read-available fd)))
        (when chunk
          (setf output (concatenate 'string output chunk))
          (when (search needle output :test #'char-equal)
            (return output)))))))

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
    (is (equal '("hello" "world") (nshell.domain.parsing:command-node-args ast)))))
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
               (is (search "[1]" (%e2e-pty-read-until fd "[1]")))
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

(test e2e-run-script-file-executes-multiline-blocks
  "Running a script file executes multiline blocks and exposes $argv."
  (with-temporary-output-file (path :prefix "nshell-script")
    (with-open-file (out path :direction :output :if-exists :supersede
                              :if-does-not-exist :create)
      (write-string (format nil "function show~%echo hi $argv[1]~%end~%for i in (seq 1 2)~%echo n=$i~%end~%show $argv~%")
                    out))
    (let ((output (capture-standard-output
                    (nshell.presentation::run-repl-script path '("World")))))
      (is (search "n=1" output))
      (is (search "n=2" output))
      (is (search "hi World" output)))))

(test e2e-main-script-executes-multiline-blocks
  "The public script entry point executes multiline blocks and exposes $argv."
  (with-temporary-output-file (path :prefix "nshell-main-script")
    (with-open-file (out path :direction :output :if-exists :supersede
                              :if-does-not-exist :create)
      (write-string (format nil "function show~%echo hi $argv[1]~%end~%for i in (seq 1 2)~%echo n=$i~%end~%show $argv~%")
                    out))
    (%assert-nshell-main-result (list path "World")
                                '("n=1" "n=2" "hi World")
                                0)))

(test e2e-main-script-preserves-flag-like-argv
  "Script arguments that look like top-level flags are passed through as $argv."
  (with-temporary-output-file (path :prefix "nshell-script-argv")
    (with-open-file (out path :direction :output :if-exists :supersede
                              :if-does-not-exist :create)
      (write-string "echo arg=$argv[1]\n" out))
    (%assert-nshell-main-result (list path "--help")
                                "arg=--help"
                                0)
    (%assert-nshell-main-result (list path "--version")
                                "arg=--version"
                                0)))

(test e2e-main-script-stops-after-parse-error
  "Script execution must not run later forms after a parse error."
  (with-temporary-output-file (path :prefix "nshell-script-parse-error")
    (with-open-file (out path :direction :output :if-exists :supersede
                              :if-does-not-exist :create)
      (write-string (format nil "| echo bad~%echo should-not-run~%") out))
    (multiple-value-bind (stdout stderr exit-code)
        (%run-nshell-main (list path))
      (is (= 2 exit-code))
      (is (search "source: parse error" stdout))
      (is (not (search "should-not-run" stdout)))
      (is (string= "" stderr)))))

(test e2e-main-command-executes-once
  "The entry point executes a single batch command with -c."
  (%assert-nshell-main-result '("-c" "echo hello")
                              "hello"
                              0))

(test e2e-main-command-exposes-trailing-argv
  "Command-mode arguments after -c are exposed as $argv."
  (%assert-nshell-main-result '("-c" "echo first=$argv[1]; echo second=$argv[2]; echo all=$argv"
                                "alpha" "beta")
                                 (list "first=alpha"
                                       "second=beta"
                                       "all=alpha all=beta")
                                 0))

(test e2e-main-long-command-exposes-trailing-argv
  "Command-mode arguments after --command are exposed as $argv."
  (%assert-nshell-main-result '("--command" "echo arg=$argv[1]" "--flag-like")
                              "arg=--flag-like"
                              0))

(test e2e-main-command-supports-inline-function-definition
  "The -c command path supports source-reader function definitions."
  (%assert-nshell-main-result '("-c" "function greet; echo hi $argv[1]; end; greet World")
                              "hi World"
                              0))

(test e2e-main-command-supports-inline-control-flow
  "The -c command path supports inline source-reader control-flow forms."
  (multiple-value-bind (stdout stderr exit-code)
      (%run-nshell-main
       '("-c" "for i in (seq 1 2); echo n=$i; end; if true; echo conditional; end; switch yes; case yes; echo switched; end; begin; echo grouped; end; while false; echo should-not-run; end; echo after-while"))
    (is (= 0 exit-code))
    (is (search "n=1" stdout))
    (is (search "n=2" stdout))
    (is (search "conditional" stdout))
    (is (search "switched" stdout))
    (is (search "grouped" stdout))
    (is (search "after-while" stdout))
    (is (not (search "should-not-run" stdout)))
    (is (string= "" stderr))))

(test e2e-main-command-expands-command-substitutions
  "The -c command path expands POSIX-style and fish-style command substitutions."
  (%assert-nshell-main-result '("-c" "echo posix=$(echo hi); echo fish=(echo bye); echo \"dq=$(echo quoted)\"")
                              '("posix=hi" "fish=bye" "dq=quoted")
                              0))

(test e2e-main-command-expands-documented-core-forms
  "The -c command path expands arithmetic, parameter, and brace forms documented for scripts."
  (%assert-nshell-main-result
   '("-c" "set FOO bar; echo arith=$((1 + 2 * 3)); echo param=${FOO:-fallback}; echo alt=${FOO:+yes}; echo brace=a{b,c}; echo range={1..3}")
   '("arith=7"
     "param=bar"
     "alt=yes"
     "brace=ab brace=ac"
     "range=1 range=2 range=3")
   0))

(test e2e-main-command-expands-list-indexes-and-ranges
  "The public batch path preserves fish-style list variable indexing and range expansion."
  (%assert-nshell-main-result
   '("-c" "set LIST alpha beta gamma; echo idx=$LIST[2]; echo range=$LIST[1..2]; echo compound=pre-$LIST[1..2].txt")
   '("idx=beta"
     "range=alpha range=beta"
     "compound=pre-alpha.txt compound=pre-beta.txt")
   0))

(test e2e-main-command-expands-globs
  "The public batch path expands filesystem globs against existing files."
  (let* ((root-path (merge-pathnames
                     (format nil "nshell-glob-e2e-~D/" (get-internal-real-time))
                     (uiop:temporary-directory)))
         (root (namestring root-path))
         (txt-a (merge-pathnames "alpha.txt" root-path))
         (txt-b (merge-pathnames "gamma.txt" root-path))
         (log-file (merge-pathnames "beta.log" root-path)))
    (unwind-protect
         (progn
           (ensure-directories-exist txt-a)
           (with-open-file (out txt-a :direction :output :if-does-not-exist :create)
             (write-string "alpha" out))
           (with-open-file (out txt-b :direction :output :if-does-not-exist :create)
             (write-string "gamma" out))
           (with-open-file (out log-file :direction :output :if-does-not-exist :create)
             (write-string "beta" out))
           (multiple-value-bind (stdout stderr exit-code)
               (%run-nshell-main (list "-c" (format nil "echo glob=~A*.txt" root)))
             (is (= 0 exit-code))
             (is (search "glob=" stdout))
             (is (search "alpha.txt" stdout))
             (is (search "gamma.txt" stdout))
             (is (not (search "beta.log" stdout)))
             (is (string= "" stderr))))
      (ignore-errors
        (when (probe-file txt-a)
          (delete-file txt-a)))
      (ignore-errors
        (when (probe-file txt-b)
          (delete-file txt-b)))
      (ignore-errors
        (when (probe-file log-file)
          (delete-file log-file)))
      (ignore-errors
        (when (probe-file root-path)
          (uiop:delete-directory-tree root-path :validate t))))))

(test e2e-main-command-applies-fd-redirections
  "The -c command path applies fd redirections to external command stdout and stderr."
  (with-temporary-output-file (amp-target :prefix "nshell-main-amp-redir")
    (with-temporary-output-file (merge-target :prefix "nshell-main-merge-redir")
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "-c"
                 (format nil
                         "sh -c 'echo out; echo err >&2' &> ~A; sh -c 'echo merge-out; echo merge-err >&2' > ~A 2>&1"
                         amp-target
                         merge-target)))
        (is (= 0 exit-code))
        (is (string= "" stdout))
        (is (string= "" stderr))
        (let ((amp-content (uiop:read-file-string amp-target))
              (merge-content (uiop:read-file-string merge-target)))
          (is (search "out" amp-content))
          (is (search "err" amp-content))
          (is (search "merge-out" merge-content))
          (is (search "merge-err" merge-content)))))))

(test e2e-main-command-reports-signal-exit-status
  "External commands killed by a signal report the shell-compatible 128+signal status."
  (%assert-nshell-main-result '("-c" "sh -c 'kill -TERM $$'")
                              nil
                              143))

(test e2e-main-pipeline-reports-last-signal-exit-status
  "A pipeline reports 128+signal when its last external stage is killed by a signal."
  (%assert-nshell-main-result '("-c" "echo ignored | sh -c 'kill -TERM $$'")
                              nil
                              143))

(test e2e-main-stdin-batch-executes-multiline-blocks
  "The no-argument non-interactive entry point executes multiline stdin blocks."
  (%assert-nshell-main-result nil
                              "stdin-ok"
                              0
                              :input (format nil "if true~%echo stdin-ok~%end~%")))

(test e2e-main-stdin-batch-stops-after-parse-error
  "The no-argument non-interactive entry point must not run later forms after a parse error."
  (multiple-value-bind (stdout stderr exit-code)
      (%run-nshell-main nil :input (format nil "| echo bad~%echo should-not-run~%"))
    (is (= 2 exit-code))
    (is (search "source: parse error" stdout))
    (is (not (search "should-not-run" stdout)))
    (is (string= "" stderr))))

(test e2e-main-here-string-feeds-external-stdin
  "The batch command path should feed here-strings to external stdin."
  (%assert-nshell-main-result '("-c" "cat <<< hello")
                              (format nil "hello~%")
                              0))

(test e2e-main-here-document-feeds-external-stdin
  "The batch command path should feed here-documents to external stdin."
  (%assert-nshell-main-result (list "-c" (format nil "cat << EOF~%hello~%EOF"))
                              (format nil "hello~%")
                              0))

(test e2e-main-type-command-executes-cleanly
  "The entry point executes type through the batch command path."
  (%assert-nshell-main-result '("-c" "type echo")
                              "echo is a shell builtin"
                              0))

(test e2e-abbreviation-expands-on-enter-before-execution
  (with-repl-test-state
    (setf (gethash "say" nshell.presentation::*abbreviations*) "echo hello")
    (setf nshell.presentation::*input-state*
          (nshell.presentation::make-repl-input-state :buffer "say"))
    (multiple-value-bind (state output)
        (reduce-once nshell.presentation::*input-state* :enter)
      (setf nshell.presentation::*input-state* state)
      (is-input-state state :buffer "echo hello" :cursor-pos 10)
      (is (eq :execute output))
      (let ((rendered (capture-process-output-event output)))
        (is (search "hello" rendered))
        (is (= 0 nshell.presentation::*last-exit-code*))
        (is (string= ""
                     (nshell.presentation:input-state-buffer
                      nshell.presentation::*input-state*)))))))

(test e2e-command-position-abbreviation-expands-only-at-command-position
  (with-repl-test-state
    (setf (gethash "gco" nshell.presentation::*abbreviations*)
          (nshell.domain.abbreviation:make-abbreviation
           :expansion "echo command"
           :position :command))
    (setf nshell.presentation::*input-state*
          (nshell.presentation::make-repl-input-state :buffer "echo gco"))
    (multiple-value-bind (state output)
        (reduce-once nshell.presentation::*input-state* :enter)
      (is-input-state state :buffer "echo gco" :cursor-pos 8)
      (is (eq :execute output)))
    (setf nshell.presentation::*input-state*
          (nshell.presentation::make-repl-input-state :buffer "gco"))
    (multiple-value-bind (state output)
        (reduce-once nshell.presentation::*input-state* :enter)
      (is-input-state state :buffer "echo command" :cursor-pos 12)
      (is (eq :execute output)))))

(test e2e-meta-s-input-cycle
  (let* ((events (read-key-events-from-string
                  (concatenate 'string "apt update" (esc-sequence "s"))))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "sudo apt update" line))
    (with-complete-command-line (result ast line)
      (is (string= "sudo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("apt" "update")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-t-input-cycle
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "gti status" 'list)
                                  (make-list 8 :initial-element (code-char 2))
                                  (list (code-char 20)))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status" line))
    (with-complete-command-line (result ast line)
      (is (string= "git" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("status")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-alt-t-input-cycle
  (let* ((events (read-key-events-from-string
                  (concatenate 'string "echo world hello" (esc-sequence "t"))))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo hello world" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hello" "world")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-alt-u-input-cycle
  (let* ((events (read-key-events-from-string
                  (concatenate 'string "echo hello" (esc-sequence "u"))))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo HELLO" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("HELLO")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-bracketed-paste-normalizes-newlines-and-undos-once
  (let* ((raw-paste (format nil "echo one~C~Cecho two~C"
                            #\Return #\Newline #\Return))
         (expected (format nil "echo one~%echo two~%"))
         (events (read-key-events-from-string
                  (concatenate 'string
                               (esc-sequence "[200~")
                               raw-paste
                               (esc-sequence "[201~"))))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events)))
    (is-input-state state
                    :buffer expected
                    :cursor-pos (length expected))
    (multiple-value-bind (undone output)
        (reduce-once state :ctrl-underscore)
      (is-input-state undone :buffer "" :cursor-pos 0)
      (is (eq :suggest-update output)))))

(test e2e-alt-t-preserves-quoted-word-cycle
  (let* ((events (read-key-events-from-string
                  (concatenate 'string
                               "echo tail \"hello world\""
                               (esc-sequence "t"))))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo \"hello world\" tail" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hello world" "tail")
                 (nshell.domain.parsing:command-node-arg-values ast))))))

(test e2e-alt-d-preserves-quoted-word-cycle
  (let* ((events (read-key-events-from-string (esc-sequence "d")))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "echo \"hello world\" tail"
                  :cursor-pos 4)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo tail" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("tail")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-k-replaces-line-suffix
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "echo hello world" 'list)
                                  (make-list 5 :initial-element (code-char 2))
                                  (list (code-char 11))
                                  (coerce "shell" 'list))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo hello shell" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hello" "shell")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-u-yank-restores-killed-line
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "echo hello world" 'list)
                                  (list (code-char 21)
                                        (code-char 25)))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo hello world" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hello" "world")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-w-yank-restores-escaped-word
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "echo hello\\ world" 'list)
                                  (list (code-char 23)
                                        (code-char 25)))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo hello\\ world" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hello world")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-g-cancels-completion-session
  (let* ((events (read-key-events-from-string (string (code-char 7))))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "g"
                  :cursor-pos 1
                  :completion-index 0
                  :completion-base-buffer "g"
                  :completion-base-cursor 1
                  :last-candidates '("git" "grep")
                  :suggestion "it")
                 events)))
    (is-input-state state
                    :buffer "g"
                    :cursor-pos 1
                    :completion-index -1
                    :completion-base-buffer nil
                    :completion-base-cursor nil
                    :last-candidates nil
                    :suggestion nil)))

(test e2e-end-accepts-autosuggestion-tail
  (let* ((events (read-key-events-from-string (esc-sequence "[F")))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "git"
                  :cursor-pos 3
                  :suggestion " status")
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status" line))
    (with-complete-command-line (result ast line)
      (is (string= "git" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("status")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-e-accepts-autosuggestion-tail
  (let* ((events (read-key-events-from-string (string (code-char 5))))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "git"
                  :cursor-pos 3
                  :suggestion " status")
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status" line))
    (with-complete-command-line (result ast line)
      (is (string= "git" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("status")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-right-and-ctrl-f-accept-autosuggestion-tail
  "Decoded Right and Ctrl-F both accept the complete autosuggestion tail at line end."
  (let* ((right-events (read-key-events-from-string (esc-sequence "[C")))
         (ctrl-f-events (read-key-events-from-string (string (code-char 6))))
         (right-state (apply-key-events-to-input-state
                       (input-state
                        :buffer "git"
                        :cursor-pos 3
                        :suggestion " status")
                       right-events))
         (ctrl-f-state (apply-key-events-to-input-state
                        (input-state
                        :buffer "git"
                        :cursor-pos 3
                        :suggestion " status")
                        ctrl-f-events)))
    (is (string= (nshell.presentation:input-state-buffer right-state)
                 (nshell.presentation:input-state-buffer ctrl-f-state)))
    (is (string= "git status"
                 (nshell.presentation:input-state-buffer right-state)))
    (is (= (nshell.presentation:input-state-cursor-pos right-state)
           (nshell.presentation:input-state-cursor-pos ctrl-f-state)))
    (is (null (nshell.presentation:input-state-suggestion right-state)))
    (is (null (nshell.presentation:input-state-suggestion ctrl-f-state)))))

(test e2e-alt-right-accepts-autosuggestion-operator-then-command
  (let* ((events (read-key-events-from-string
                  (concatenate 'string (esc-sequence "f") (esc-sequence "f"))))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "git status"
                  :cursor-pos 10
                  :suggestion " | grep modified")
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status | grep" line))
    (is (string= " modified"
                 (nshell.presentation:input-state-suggestion state)))
    (with-complete-command-line (result ast line)
      (let ((commands (nshell.domain.parsing:pipeline-node-commands ast)))
        (is (= 2 (length commands)))
        (is (string= "git"
                     (nshell.domain.parsing:command-node-command (first commands))))
        (is (equal '("status")
                   (nshell.domain.parsing:command-node-args (first commands))))
        (is (string= "grep"
                     (nshell.domain.parsing:command-node-command (second commands))))))))

(test e2e-ctrl-right-accepts-autosuggestion-word
  (let* ((events (read-key-events-from-string (esc-sequence "[1;5C")))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "git"
                  :cursor-pos 3
                  :suggestion " status --short")
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status" line))
    (is (string= " --short"
                 (nshell.presentation:input-state-suggestion state)))
    (with-complete-command-line (result ast line)
      (is (string= "git" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("status")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-alt-right-accepts-attached-redirection-target
  (let* ((events (read-key-events-from-string (esc-sequence "f")))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "echo hi"
                  :cursor-pos 7
                  :suggestion " >out.txt && cat out.txt")
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo hi >out.txt" line))
    (is (string= " && cat out.txt"
                 (nshell.presentation:input-state-suggestion state)))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hi" (">" . nil) "out.txt")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-control-h-backspace-input-cycle
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "git statusx" 'list)
                                  (list (code-char 8)))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status" line))
    (with-complete-command-line (result ast line)
      (is (string= "git" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("status")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-d-deletes-character-under-cursor
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "echo hxello" 'list)
                                  (make-list 5 :initial-element (code-char 2))
                                  (list (code-char 4)))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo hello" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hello")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-d-on-empty-input-requests-quit
  (let* ((events (read-key-events-from-string (string (code-char 4))))
         (event (first events)))
    (multiple-value-bind (state output)
        (nshell.presentation:reduce-input-state (input-state) event)
      (is-input-state state
                      :buffer ""
                      :cursor-pos 0)
      (is (eq :quit output)))))

(test e2e-ctrl-l-clears-screen-without-losing-editing-session
  (with-repl-test-state
    (let ((state (input-state
                  :buffer "git"
                  :cursor-pos 3
                  :completion-index 0
                  :completion-base-buffer "git"
                  :completion-base-cursor 3
                  :last-candidates '("git" "grep")
                  :suggestion " status")))
      (multiple-value-bind (next-state output)
          (nshell.presentation:reduce-input-state
           state
           (input-key-event :ctrl-l))
        (is (eq :clear-screen output))
        (is-input-state next-state
                        :buffer "git"
                        :cursor-pos 3
                        :completion-index 0
                        :completion-base-buffer "git"
                        :completion-base-cursor 3
                        :last-candidates '("git" "grep")
                        :suggestion " status")
        (setf nshell.presentation::*input-state* next-state)
        (let ((rendered (capture-process-output-event output)))
          (is (search "[2J" rendered))
          (is (search "[1;1H" rendered))))
      (is-input-state nshell.presentation::*input-state*
                      :buffer "git"
                      :cursor-pos 3
                      :completion-index 0
                      :completion-base-buffer "git"
                      :completion-base-cursor 3
                      :last-candidates '("git" "grep")
                      :suggestion " status"))))

(test e2e-ctrl-underscore-undo-input-cycle
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "git statusx" 'list)
                                  (list (code-char 31)))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status" line))
    (with-complete-command-line (result ast line)
      (is (string= "git" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("status")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-alt-y-yank-pop-input-cycle
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "echo first second" 'list)
                                  (list (code-char 23)
                                        (code-char 23)
                                        (code-char 25))
                                  (coerce (esc-sequence "y") 'list))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo second" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("second")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-multiline-quoted-command-cycle
  (let* ((history (nshell.domain.history:make-command-history))
         (line (format nil "echo \"hello~%world\"")))
    (with-complete-command-line (result ast line)
      (is (nshell.domain.parsing:command-node-p ast))
      (is (equal (list (format nil "hello~%world"))
                 (nshell.domain.parsing:command-node-arg-values ast))))
    (nshell.domain.history:history-add history line)
    (is (= 1 (nshell.domain.history:history-size history)))))

(test e2e-newline-sequence-executes-both-commands
  (with-complete-command-line (result ast (format nil "echo one~%echo two"))
    (is (null (nshell.domain.parsing:parse-errors result)))
    (multiple-value-bind (output-text code)
        (call-repl-execute-ast ast)
      (is (= 0 code))
      (is (string= (format nil "one~%two~%") output-text)))))

(test e2e-here-document-tail-command-executes
  (with-complete-command-line (result ast
                                      (format nil "cat << EOF~%hello~%EOF~%echo done"))
    (is (null (nshell.domain.parsing:parse-errors result)))
    (multiple-value-bind (output-text code)
        (call-repl-execute-ast ast)
      (is (= 0 code))
      (is (string= (format nil "hello~%done~%") output-text)))))
(test e2e-pipeline-smoke
  "Verify pipeline execution via spawn-pipeline"
  (let* ((cmd1 (nshell.domain.parsing:make-command-node "echo" '("hello")))
         (pipe (nshell.domain.parsing:make-pipeline-node (list cmd1)))
         (exit (nshell.infrastructure.acl:spawn-pipeline
                (nshell.domain.parsing:pipeline-node-commands pipe))))
    (is (= 0 exit))))

(test e2e-pipeline-redirections-apply-per-stage
  "Pipeline stages should apply their own input and output redirects."
  (with-repl-test-state
    (let* ((root (merge-pathnames (format nil "nshell-pipeline-redir-~d/"
                                          (random 1000000))
                                  (uiop:temporary-directory)))
           (input (merge-pathnames "input.txt" root))
           (output (merge-pathnames "output.txt" root))
           (content "pipeline redirection"))
      (unwind-protect
           (progn
             (ensure-directories-exist root)
             (with-open-file (stream input
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (write-string content stream))
             (let ((line (format nil "cat < ~a | cat > ~a"
                                 (namestring input)
                                 (namestring output))))
               (with-complete-command-line (result ast line)
                (multiple-value-bind (output-text code)
                    (call-repl-execute-ast ast)
                  (declare (ignore output-text))
                  (is (= 0 code)))
                (is (probe-file output))
                 (with-open-file (stream output :direction :input)
                   (let ((actual (make-string (file-length stream))))
                     (read-sequence actual stream)
                     (is (string= content actual)))))))
        (handler-case
            (when (probe-file root)
              (uiop:delete-directory-tree root :validate t))
          (error ()))))))
(test e2e-syntax-error-stops-before-execution
  (with-parsed-command-line (result "| echo should-not-run")
    (is (not (nshell.domain.parsing:parse-complete-p result)))
    (is (eq :missing-command
            (nshell.domain.parsing:parse-diagnostic-kind
             (first (nshell.domain.parsing:parse-errors result)))))))
(test e2e-external-command
  "External command execution returns correct exit code"
  (is (= 0 (nshell.infrastructure.acl:run-external "true" '())))
  (is (not (= 0 (nshell.infrastructure.acl:run-external "false" '())))))
