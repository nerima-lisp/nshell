(in-package #:nshell/test)
(in-suite e2e-tests)

(test e2e-run-script-file-executes-multiline-blocks
  "Running a script file executes multiline blocks and exposes $argv."
  (with-temporary-output-file (path :prefix "nshell-script")
    (with-open-file (out path :direction :output :if-exists :supersede
                              :if-does-not-exist :create)
      (write-string (format nil "function show~%echo hi $argv[1]~%end~%for i in (seq 1 2)~%echo n=$i~%end~%show $argv~%")
                    out))
    (let ((output (capture-standard-output
                    (nshell.presentation:run-repl-script path '("World")))))
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
   '("-c" "set FOO bar; echo arith=$((1 + 2 * 3)); echo param=${FOO:-fallback}; echo alt=${FOO:+yes}; echo sub=${FOO:1:2}; echo brace=a{b,c}; echo range={1..3}")
   '("arith=7"
     "param=bar"
     "alt=yes"
     "sub=ar"
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
