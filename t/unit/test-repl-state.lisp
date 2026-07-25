(in-package #:nshell/test)

(describe "repl-tests"
  (it "exported-environment-strings-only-include-exported-vars"
    "The REPL passes only exported domain environment variables to process launch."
    (with-repl-test-state
      (repl-test-set-env "LOCAL_ONLY" "hidden")
      (repl-test-set-env "VISIBLE" "yes" t)
      (let ((strings (nshell.presentation:exported-environment-strings)))
        (expect (member "VISIBLE=yes" strings :test #'string=) :to-be-truthy)
        (expect (member "LOCAL_ONLY=hidden" strings :test #'string=) :to-be-falsy))))

  (it "repl-builtin-dispatches-through-application-registry"
    "REPL builtin execution uses the application builtin registry and syncs context state."
    (with-repl-test-state
      (multiple-value-bind (output builtin-p code)
          (call-repl-builtin "set" '("GREETING" "hello"))
        (expect "" :to-equal output)
        (expect (null builtin-p) :to-be-falsy)
        (expect 0 :to-equal code)
        (expect "hello" :to-equal (repl-test-env "GREETING")))
      (multiple-value-bind (output builtin-p code)
          (call-repl-builtin "type" '("echo"))
        (expect (null builtin-p) :to-be-falsy)
        (expect 0 :to-equal code)
        (expect (search "echo is a shell builtin" output) :to-be-truthy))
      (multiple-value-bind (output builtin-p code)
          (call-repl-builtin "not-a-builtin" nil)
        (expect "" :to-equal output)
        (expect builtin-p :to-be-falsy)
        (expect code :to-be-null))))

  (it "repl-builtin-syncs-mutable-shell-state"
    "Registry builtins update REPL aliases, abbreviations, function table, and running flag."
    (with-repl-test-state
      (call-repl-builtin "alias" '("ll" "ls -l"))
      (expect "ls -l" :to-equal (repl-test-alias "ll"))
      (call-repl-builtin "abbr" '("-a" "gco" "git" "checkout"))
      (expect "git checkout" :to-equal (repl-test-abbreviation "gco"))
      (call-repl-builtin "function" '("hi" "echo" "hello" "end"))
      (expect '("echo hello") :to-equal (repl-test-function "hi"))
      (call-repl-builtin "exit" nil)
      (expect (repl-test-running-p) :to-be-falsy))))
