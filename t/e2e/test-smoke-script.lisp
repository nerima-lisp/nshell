(in-package #:nshell/test)

(describe "e2e-tests"
  (it "e2e-run-script-file-executes-multiline-blocks"
    "Running a script file executes multiline blocks and exposes $argv."
    (with-temporary-output-file (path :prefix "nshell-script")
      (with-open-file (out path :direction :output :if-exists :supersede
                                :if-does-not-exist :create)
        (write-string (format nil "function show~%echo hi $argv[1]~%end~%for i in (seq 1 2)~%echo n=$i~%end~%show $argv~%")
                      out))
      (let ((output (capture-standard-output
                      (nshell.presentation:run-repl-script path '("World")))))
        (expect (search "n=1" output) :to-be-truthy)
        (expect (search "n=2" output) :to-be-truthy)
        (expect (search "hi World" output) :to-be-truthy))))

  (it "e2e-main-script-executes-multiline-blocks"
    "The public script entry point executes multiline blocks and exposes $argv."
    (with-temporary-output-file (path :prefix "nshell-main-script")
      (with-open-file (out path :direction :output :if-exists :supersede
                                :if-does-not-exist :create)
        (write-string (format nil "function show~%echo hi $argv[1]~%end~%for i in (seq 1 2)~%echo n=$i~%end~%show $argv~%")
                      out))
      (%assert-nshell-main-result (list path "World")
                                  '("n=1" "n=2" "hi World")
                                  0)))

  (it "e2e-main-script-preserves-flag-like-argv"
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

  (it "e2e-main-script-stops-after-parse-error"
    "Script execution must not run later forms after a parse error."
    (with-temporary-output-file (path :prefix "nshell-script-parse-error")
      (with-open-file (out path :direction :output :if-exists :supersede
                                :if-does-not-exist :create)
        (write-string (format nil "| echo bad~%echo should-not-run~%") out))
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list path))
        (expect 2 :to-equal exit-code)
        (expect (search "source: parse error" stdout) :to-be-truthy)
        (expect (search "should-not-run" stdout) :to-be-falsy)
        (expect "" :to-equal stderr))))

  (it "e2e-main-command-executes-once"
    "The entry point executes a single batch command with -c."
    (%assert-nshell-main-result '("-c" "echo hello")
                                "hello"
                                0))

  (it "e2e-main-command-exposes-trailing-argv"
    "Command-mode arguments after -c are exposed as $argv."
    (%assert-nshell-main-result '("-c" "echo first=$argv[1]; echo second=$argv[2]; echo all=$argv"
                                  "alpha" "beta")
                                   (list "first=alpha"
                                         "second=beta"
                                         "all=alpha all=beta")
                                   0))

  (it "e2e-main-long-command-exposes-trailing-argv"
    "Command-mode arguments after --command are exposed as $argv."
    (%assert-nshell-main-result '("--command" "echo arg=$argv[1]" "--flag-like")
                                "arg=--flag-like"
                                0))

  (it "e2e-main-command-supports-inline-function-definition"
    "The -c command path supports source-reader function definitions."
    (%assert-nshell-main-result '("-c" "function greet; echo hi $argv[1]; end; greet World")
                                "hi World"
                                0))

  (it "e2e-main-command-supports-inline-control-flow"
    "The -c command path supports inline source-reader control-flow forms."
    (multiple-value-bind (stdout stderr exit-code)
        (%run-nshell-main
         '("-c" "for i in (seq 1 2); echo n=$i; end; if true; echo conditional; end; switch yes; case yes; echo switched; end; begin; echo grouped; end; while false; echo should-not-run; end; echo after-while"))
      (expect 0 :to-equal exit-code)
      (expect (search "n=1" stdout) :to-be-truthy)
      (expect (search "n=2" stdout) :to-be-truthy)
      (expect (search "conditional" stdout) :to-be-truthy)
      (expect (search "switched" stdout) :to-be-truthy)
      (expect (search "grouped" stdout) :to-be-truthy)
      (expect (search "after-while" stdout) :to-be-truthy)
      (expect (search "should-not-run" stdout) :to-be-falsy)
      (expect "" :to-equal stderr)))

  (it "e2e-main-command-expands-command-substitutions"
    "The -c command path expands POSIX-style and fish-style command substitutions."
    (%assert-nshell-main-result '("-c" "echo posix=$(echo hi); echo fish=(echo bye); echo \"dq=$(echo quoted)\"")
                                '("posix=hi" "fish=bye" "dq=quoted")
                                0))

  (it "e2e-main-command-merges-stderr-with-pipe-and-ampersand"
    "The public -c path supports |& by feeding the left stage's stderr downstream."
    (%assert-nshell-main-result
     '("-c" "sh -c 'printf out; printf err >&2' |& cat")
     "outerr"
     0))

  (it "e2e-main-command-applies-pipefail"
    "The public -c path returns an earlier non-zero pipeline status when pipefail is enabled."
    (%assert-nshell-main-result
     '("-c" "set -o pipefail; sh -c 'exit 7' | sh -c 'exit 0'")
     nil
     7))

  (it "e2e-main-command-expands-process-substitution"
    "The -c command path materializes input process substitutions."
    (%assert-nshell-main-result '("-c" "cat <(/usr/bin/printf process-ok)")
                                "process-ok"
                                0))

  (it "e2e-main-command-expands-output-process-substitution"
    "The -c command path materializes output process substitutions."
    (%assert-nshell-main-result
     '("-c" "sh -c 'printf output-ok > \"$1\"' sh >(cat)")
     "output-ok"
     0))

  (it "e2e-main-command-expands-documented-core-forms"
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

  (it "e2e-main-command-expands-list-indexes-and-ranges"
    "The public batch path preserves fish-style list variable indexing and range expansion."
    (%assert-nshell-main-result
     '("-c" "set LIST alpha beta gamma; echo idx=$LIST[2]; echo range=$LIST[1..2]; echo compound=pre-$LIST[1..2].txt")
     '("idx=beta"
       "range=alpha range=beta"
       "compound=pre-alpha.txt compound=pre-beta.txt")
     0))

  (it "e2e-main-command-expands-globs"
    "The public batch path expands filesystem globs against existing files."
    (let* ((root-path (merge-pathnames
                       (format nil "nshell-glob-e2e-~D/" (get-internal-real-time))
                       (host-kit:temporary-directory)))
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
               (expect 0 :to-equal exit-code)
               (expect (search "glob=" stdout) :to-be-truthy)
               (expect (search "alpha.txt" stdout) :to-be-truthy)
               (expect (search "gamma.txt" stdout) :to-be-truthy)
               (expect (search "beta.log" stdout) :to-be-falsy)
               (expect "" :to-equal stderr)))
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
            (host-kit:delete-directory-tree root-path :validate t))))))

  (it "e2e-main-command-applies-fd-redirections"
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
          (expect 0 :to-equal exit-code)
          (expect "" :to-equal stdout)
          (expect "" :to-equal stderr)
          (let ((amp-content (host-kit:read-file-string amp-target))
                (merge-content (host-kit:read-file-string merge-target)))
            (expect (search "out" amp-content) :to-be-truthy)
            (expect (search "err" amp-content) :to-be-truthy)
            (expect (search "merge-out" merge-content) :to-be-truthy)
            (expect (search "merge-err" merge-content) :to-be-truthy))))))

  (it "e2e-main-command-preserves-dynamic-fd-dup-order"
    "The public command path preserves left-to-right semantics for 1>&2 followed by stdout redirection."
    (with-temporary-output-file (target :prefix "nshell-main-dynamic-fd-dup")
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "-c"
                 (format nil
                         "sh -c 'echo out; echo err >&2' 1>&2 > ~A"
                         target)))
        (expect 0 :to-equal exit-code)
        (expect "" :to-equal stdout)
        (expect (search "err" stderr) :to-be-truthy)
        (expect (search "out" stderr) :to-be-falsy)
        (expect (format nil "out~%") :to-equal (host-kit:read-file-string target)))))

  (it "e2e-main-command-preserves-arbitrary-fd-dup-order"
    "The public command path keeps fd 3 on the original stdout while stdout is redirected later."
    (with-temporary-output-file (target :prefix "nshell-main-arbitrary-fd-dup")
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "-c"
                 (format nil
                         "sh -c 'printf out; printf fd3 >&3' 3>&1 1>~A"
                         target)))
        (expect 0 :to-equal exit-code)
        (expect "fd3" :to-equal stdout)
        (expect "" :to-equal stderr)
        (expect "out" :to-equal (host-kit:read-file-string target)))))

  (it "e2e-main-command-reports-internal-fd-redirect-errors"
    "The public command path turns unsupported builtin fd redirects into a shell status."
    (multiple-value-bind (stdout stderr exit-code)
        (%run-nshell-main (list "-c" "echo builtin 3>&1"))
      (expect "" :to-equal stdout)
      (expect 1 :to-equal exit-code)
      (expect (not (null (search "Unsupported file-descriptor duplication 3>&1"
                                 stderr)))
              :to-be-truthy)))

  (it "e2e-main-command-reports-signal-exit-status"
    "External commands killed by a signal report the shell-compatible 128+signal status."
    (%assert-nshell-main-result '("-c" "sh -c 'kill -TERM $$'")
                                nil
                                143))

  (it "e2e-main-pipeline-reports-last-signal-exit-status"
    "A pipeline reports 128+signal when its last external stage is killed by a signal."
    (%assert-nshell-main-result '("-c" "echo ignored | sh -c 'kill -TERM $$'")
                                nil
                                143))

  (it "e2e-main-stdin-batch-executes-multiline-blocks"
    "The no-argument non-interactive entry point executes multiline stdin blocks."
    (%assert-nshell-main-result nil
                                "stdin-ok"
                                0
                                :input (format nil "if true~%echo stdin-ok~%end~%")))

  (it "e2e-main-stdin-batch-stops-after-parse-error"
    "The no-argument non-interactive entry point must not run later forms after a parse error."
    (multiple-value-bind (stdout stderr exit-code)
        (%run-nshell-main nil :input (format nil "| echo bad~%echo should-not-run~%"))
      (expect 2 :to-equal exit-code)
      (expect (search "source: parse error" stdout) :to-be-truthy)
      (expect (search "should-not-run" stdout) :to-be-falsy)
      (expect "" :to-equal stderr)))

  (it "e2e-main-here-string-feeds-external-stdin"
    "The batch command path should feed here-strings to external stdin."
    (%assert-nshell-main-result '("-c" "cat <<< hello")
                                (format nil "hello~%")
                                0))

  (it "e2e-main-here-document-feeds-external-stdin"
    "The batch command path should feed here-documents to external stdin."
    (%assert-nshell-main-result (list "-c" (format nil "cat << EOF~%hello~%EOF"))
                                (format nil "hello~%")
                                0))

  (it "e2e-main-here-document-quoted-delimiter-keeps-body-literal"
    "The public batch command path must not expand a quoted here-document body."
    (%assert-nshell-main-result
     (list "-c" (format nil "cat << \"EOF\"~%$HOME $(printf substituted)~%EOF"))
     (format nil "$HOME $(printf substituted)~%")
     0))

  (it "e2e-main-type-command-executes-cleanly"
    "The entry point executes type through the batch command path."
    (%assert-nshell-main-result '("-c" "type echo")
                                "echo is a shell builtin"
                                0))

  (it "e2e-main-command-resolves-builtin-function-and-path"
    "The command builtin reports builtin, function, and external resolutions."
    (%assert-nshell-main-result
     '("-c"
       "function greet; echo function-body; end; command -v echo; command -v greet; command -V greet; command -v /bin/echo; command greet")
     '("echo" "greet" "greet is a function" "/bin/echo" "function-body")
     0))

  (it "e2e-main-eval-runs-in-the-current-context"
    "The eval builtin parses one command string and keeps its environment changes."
    (%assert-nshell-main-result
     '("-c" "eval 'set EVAL_VALUE ready'; echo $EVAL_VALUE")
     "ready"
     0))

  (it "e2e-main-eval-propagates-the-command-status"
    "The eval builtin returns the status produced by its parsed command list."
    (%assert-nshell-main-result
     '("-c" "eval 'echo before-eval; false'")
     "before-eval"
     1))

  (it "e2e-main-eval-updates-last-exit-status"
    "The eval builtin exposes its command status through the current context."
    (%assert-nshell-main-result
     '("-c" "eval 'false'; echo eval-status=$?")
     "eval-status=1"
     0)))
