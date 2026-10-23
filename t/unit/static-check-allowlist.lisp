(in-package #:nshell/test)

(defparameter +static-check-allowlist+
  '(:unregistered-lisp-files
    (("src/infrastructure/terminal/linux-abi/termios2.lisp"
      "SB-GROVEL registers this file under #+linux; Darwin omits that component."
      :unless-feature
      :linux)
     ("t/scripts/test-dependency-assertions.lisp"
      "Standalone dependency assertion entry point invoked with sbcl --script."))
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
      "The test alias is described alongside test in the prose section and omitted from the short inventory."))))
