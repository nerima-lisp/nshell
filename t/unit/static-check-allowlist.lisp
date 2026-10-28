(in-package #:nshell/test)

(defparameter +static-check-allowlist+
  '(:unregistered-lisp-files
    (("src/infrastructure/terminal/linux-abi/termios2.lisp"
      "SB-GROVEL registers this file under #+linux; Darwin omits that component."
      :unless-feature
      :linux)
     ("t/scripts/test-dependency-assertions.lisp"
      "Standalone dependency assertion entry point invoked with sbcl --script.")
     ("t/scenarios/P12/public-api-consumer.lisp"
      "Standalone public API consumer fixture loaded directly by the P12 comparison scenario."))
    :layer-violations
    (("src/application/builtin-type-helpers.lisp" :application
                                                  :presentation
                                                  "HIGHLIGHT->ANSI"
                                                  1
                                                  "The type builtin currently delegates terminal coloring to presentation; retain this known boundary until that adapter is moved.")
     ("src/application/builtin-type-helpers.lisp" :application
                                                  :presentation
                                                  "HIGHLIGHT-LINE"
                                                  1
                                                  "The type builtin currently delegates syntax highlighting to presentation; retain this known boundary until that adapter is moved.")
     ("src/infrastructure/assistant-sidecar.lisp" :infrastructure
                                                  :application
                                                  "ASSISTANT-SETTING-VALUE"
                                                  2
                                                  "The sidecar currently reads two model settings from the application layer; retain these known references until settings access is moved behind a lower boundary."))
    :builtin-document-omissions
    (("."
      "The source alias for source is intentionally omitted from the short builtin inventory.")
     ("["
      "The test alias is described alongside test in the prose section and omitted from the short inventory."))
    :nested-test-declarations
    (("t/unit/test-east-asian-width.lisp" "IT"
      "matches-only-locale-language-prefixes"
      "This pre-existing declaration is nested in its parent test form; retain it as an exact baseline exception.")
     ("t/unit/test-east-asian-width.lisp" "IT"
      "respects-explicit-width-in-batch-initialization"
      "This pre-existing declaration is nested in its parent test form; retain it as an exact baseline exception.")
     ("t/unit/test-east-asian-width.lisp" "IT"
      "uses-locale-fallback-in-batch-auto-mode"
      "This pre-existing declaration is nested in its parent test form; retain it as an exact baseline exception.")
     ("t/unit/test-east-asian-width.lisp" "IT"
      "preserves-ordinary-input-when-querying-cpr"
      "This pre-existing declaration is nested in its parent test form; retain it as an exact baseline exception.")
     ("t/unit/test-east-asian-width.lisp" "IT"
      "parses-cpr-and-honors-the-short-timeout"
      "This pre-existing declaration is nested in its parent test form; retain it as an exact baseline exception.")
     ("t/unit/test-east-asian-width.lisp" "IT"
      "returns-three-states-for-terminal-probe"
      "This pre-existing declaration is nested in its parent test form; retain it as an exact baseline exception.")
     ("t/unit/test-repl-output-transient-panel.lisp" "IT"
      "resets-transient-panel-state-on-commit-only-once"
      "This pre-existing declaration is nested in its parent test form; retain it as an exact baseline exception.")
     ("t/unit/test-repl-output-transient-panel.lisp" "IT"
      "does-not-commit-when-the-panel-is-not-displayed"
      "This pre-existing declaration is nested in its parent test form; retain it as an exact baseline exception."))))
