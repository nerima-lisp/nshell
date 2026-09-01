(in-package #:nshell/test)

(describe "terminal detection"
  (it "recognizes descriptors that are not terminals"
    "A non-interactive test process must never be classified as an interactive terminal."
    (expect (nshell.infrastructure.terminal:interactive-terminal-p 999999)
            :to-be nil))

  (it "exposes platform terminal request constants"
    (expect (plusp nshell.infrastructure.acl::+tiocswinsz+)
            :to-be-truthy)
    (expect (plusp nshell.infrastructure.acl::+tiocsctty+)
            :to-be-truthy)))
