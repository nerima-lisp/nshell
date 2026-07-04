(in-package #:nshell/test)

(in-suite repl-tests)

(test exported-environment-strings-only-include-exported-vars
  "The REPL passes only exported domain environment variables to process launch."
  (with-repl-test-state
    (repl-test-set-env "LOCAL_ONLY" "hidden")
    (repl-test-set-env "VISIBLE" "yes" t)
    (let ((strings (nshell.presentation:exported-environment-strings)))
      (is (member "VISIBLE=yes" strings :test #'string=))
      (is (not (member "LOCAL_ONLY=hidden" strings :test #'string=))))))

(test repl-builtin-dispatches-through-application-registry
  "REPL builtin execution uses the application builtin registry and syncs context state."
  (with-repl-test-state
    (multiple-value-bind (output builtin-p code)
        (call-repl-builtin "set" '("GREETING" "hello"))
      (is (string= "" output))
      (is (not (null builtin-p)))
      (is (= 0 code))
      (is (string= "hello" (repl-test-env "GREETING"))))
    (multiple-value-bind (output builtin-p code)
        (call-repl-builtin "type" '("echo"))
      (is (not (null builtin-p)))
      (is (= 0 code))
      (is (search "echo is a shell builtin" output)))
    (multiple-value-bind (output builtin-p code)
        (call-repl-builtin "not-a-builtin" nil)
      (is (string= "" output))
      (is (not builtin-p))
      (is (null code)))))

(test repl-builtin-syncs-mutable-shell-state
  "Registry builtins update REPL aliases, abbreviations, function table, and running flag."
  (with-repl-test-state
    (call-repl-builtin "alias" '("ll" "ls -l"))
    (is (string= "ls -l" (repl-test-alias "ll")))
    (call-repl-builtin "abbr" '("-a" "gco" "git" "checkout"))
    (is (string= "git checkout" (repl-test-abbreviation "gco")))
    (call-repl-builtin "function" '("hi" "echo" "hello" "end"))
    (is (equal '("echo hello") (repl-test-function "hi")))
    (call-repl-builtin "exit" nil)
    (is (not (repl-test-running-p)))))
