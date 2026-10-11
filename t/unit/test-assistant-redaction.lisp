(in-package #:nshell/test)

(describe "assistant-environment-denylist-contracts"
  (it "excludes only typed settings and unexported internal status"
    (cl-weave:expect-assertions 6)
    (with-repl-test-state
      (repl-test-set-env "NSHELL_AI_MAX_STEPS" "1" t)
      (repl-test-set-env "?" "0")
      (repl-test-set-env "status" "2")
      (multiple-value-bind (names values)
          (nshell.presentation::%assistant-export-environment-data)
        (dolist (name '("NSHELL_AI_MAX_STEPS" "?" "status"))
          (expect (member name names :test #'string=) :to-be-truthy))
        (dolist (value '("1" "0" "2"))
          (expect nil :to-be (member value values :test #'string=))))))

  (it "retains invalid settings and exported status values"
    (let ((cases '(("NSHELL_AI_MAX_STEPS" "0" t)
                   ("NSHELL_AI_MAX_STEPS" "-1" t)
                   ("NSHELL_AI_MAX_STEPS" "private-value" t)
                   ("?" "private-value" nil)
                   ("status" "256" nil)
                   ("status" "0" t))))
      (cl-weave:expect-assertions (length cases))
      (dolist (case cases)
        (with-repl-test-state
          (apply #'repl-test-set-env case)
          (expect (member (second case)
                          (nth-value 1
                            (nshell.presentation::%assistant-export-environment-data))
                          :test #'string=)
                  :to-be-truthy)))))

  (it "protects unknown one-character secrets including duplicate setting values"
    (cl-weave:expect-assertions 6)
    (dolist (value '("1" "7" "Q"))
      (with-repl-test-state
        (repl-test-set-env "NSHELL_AI_MAX_STEPS" "1" t)
        (repl-test-set-env "UNKNOWN_VALUE" value t)
        (let ((values (nth-value 1
                        (nshell.presentation::%assistant-export-environment-data))))
          (expect (member value values :test #'string=) :to-be-truthy)
          (expect "prefix:[REDACTED]:suffix" :to-equal
                  (nshell.feature.assistant:redact-text
                   (format nil "prefix:~A:suffix" value)
                   :denylist-values values)))))))

(describe "assistant-redaction-contracts"
  (it "P1 denies quoted assigned and option-wrapped command names"
    (let ((cases '("\"pass\" show" "'pass' show" "p'a'ss show" "p\\ass show"
                   "DUMMY=1 pass show" "ONE=1 TWO=2 /usr/bin/pass show"
                   "sudo -uroot pass show" "sudo -n pass show"
                   "sudo -Eu root pass show" "sudo --user=root pass show"
                   "sudo -u root -- pass show" "env -u DUMMY pass show"
                   "env -uDUMMY pass show" "env DUMMY=1 pass show"
                   "nice -n 10 pass show" "nice -n10 pass show"
                   "stdbuf -oL pass show" "command -- 'pass' show"
                   "echo ok & pass show" "echo ok |& pass show"
                   "echo $(sudo -n pass show)" "echo $(DUMMY=1 pass show)"
                   "echo \"$(pass show)\"" "echo <(pass show)"
                   "echo >(pass show)" "echo $(pass show")))
      (cl-weave:expect-assertions (length cases))
      (dolist (line cases)
        (expect "" :to-equal
                (nshell.feature.assistant:redact-lines
                 line :denylist-paths nil :denylist-commands '("pass"))))))

  (it "P1 retains ordinary arguments and wrapper option values"
    (let ((cases '("echo pass" "echo 'pass'" "echo 'x | pass show'"
                   "echo 'x ; pass show'" "DUMMY=1 echo pass"
                   "sudo -u pass echo ok" "sudo --user=pass echo ok"
                   "env -u pass echo ok" "env -upass echo ok"
                   "nice -n 10 echo pass" "stdbuf -oL echo pass"
                   "DUMMY=pass" "echo '$(pass show)'")))
      (cl-weave:expect-assertions (length cases))
      (dolist (line cases)
        (expect line :to-equal
                (nshell.feature.assistant:redact-lines
                 line :denylist-paths nil :denylist-commands '("pass"))))))

  (it "removes known token shapes and PEM material"
    (let* ((pem (format nil "-----BEGIN TEST PRIVATE KEY-----~%secret-key-material~%-----END TEST PRIVATE KEY-----"))
           (raw (format nil "sk-abcdefghijklmnopqrstuvwxyz ghp_12345678901234567890 Bearer abcdefghijklmnopqrstuvwxyz ~a"
                        pem))
           (redacted (nshell.feature.assistant:redact-text raw)))
      (expect nil :to-be (search "sk-abcdefghijklmnopqrstuvwxyz" redacted))
      (expect nil :to-be (search "ghp_12345678901234567890" redacted))
      (expect nil :to-be (search "Bearer abcdefghijklmnopqrstuvwxyz" redacted))
      (expect nil :to-be (search "-----BEGIN TEST PRIVATE KEY-----" redacted))
      (expect (search "[REDACTED]" redacted) :to-be-truthy)))

  (it "covers credential prefixes at their real boundary lengths"
    (dolist (case '( ("sk-" . "abcdefghijklmnopqrstuvwxyz")
                     ("ghp_" . "12345678901234567890")
                     ("AKIA" . "IOSFODNN7EXAMPLE")
                     ("xox" . "b-12345678901234567890")
                     ("Bearer " . "abcdefghijklmnopqrstuvwxyz")
                     ("bearer " . "abcdefghijklmnopqrstuvwxyz")))
      (let* ((raw (concatenate 'string (car case) (cdr case)))
             (redacted (nshell.feature.assistant:redact-text raw)))
        (expect nil :to-be (search (cdr case) redacted))))))

  (it "provides built-in denylist defaults"
    (let ((redacted
            (nshell.feature.assistant:redact-payload
             '(("output" . "cat /Users/example/.ssh/id_ed25519")
               ("message" . "visible"))
             :denylist-paths
             nshell.feature.assistant:+assistant-default-denylist-paths+
             :denylist-commands
             nshell.feature.assistant:+assistant-default-denylist-commands+)))
      (expect nil :to-be (search "id_ed25519" (write-to-string redacted)))
      (expect (search "visible" (write-to-string redacted)) :to-be-truthy)))

  (it "keeps environment names while dropping values and denylisted lines"
    (let* ((payload
             (list :environment '("API_TOKEN=secret-environment-value"
                                  ("HOME" . "/Users/example"))
                   :output (format nil "cat /tmp/private.env~%visible output")
                   :command "cat /tmp/private.env"))
           (redacted
             (nshell.feature.assistant:redact-payload
              payload
              :denylist-paths '("*/private.env")
              :denylist-commands '("cat")))
           (printed (with-output-to-string (stream)
                      (write redacted :stream stream))))
      (expect (search "API_TOKEN" printed) :to-be-truthy)
      (expect nil :to-be (search "secret-environment-value" printed))
      (expect nil :to-be (search "/tmp/private.env" printed))
      (expect (search "visible output" printed) :to-be-truthy)))

  (it "matches denylisted commands at shell command boundaries"
    (dolist (case '( ("op read" . "")
                     ("echo x | op read" . "")
                     ("echo ok; op read" . "")
                     ("echo ok && op read" . "")
                     ("echo $(op read)" . "")
                     ("sudo -E pass show" . "")
                     ("env -- gh auth token" . "")
                     ("command -- gpg --list" . "")
                     ("echo top" . "echo top")
                     ("echo stop" . "echo stop")
                     ("echo option" . "echo option")))
      (expect (cdr case) :to-equal
              (nshell.feature.assistant:redact-lines
               (car case)
               :denylist-paths nil
               :denylist-commands
               '("pass" "gpg" "op" "gh auth token")))))
