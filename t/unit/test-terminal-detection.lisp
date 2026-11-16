(in-package #:nshell/test)

(describe "terminal detection"
  (it "recognizes descriptors that are not terminals"
    "A non-interactive test process must never be classified as an interactive terminal."
    (expect (nshell.infrastructure.terminal:interactive-terminal-p 999999)
            :to-be nil))

  (it "uses standard input when no descriptor is supplied"
    (expect (nshell.infrastructure.terminal:interactive-terminal-p)
            :to-be nil))

  (it "exposes platform terminal request constants"
    (expect (plusp nshell.infrastructure.acl::+tiocswinsz+)
            :to-be-truthy)
    (expect (plusp nshell.infrastructure.acl::+tiocsctty+)
            :to-be-truthy))
  (it "sgr-mouse-cleanup-disables-modes-in-reverse"
    "Terminal cleanup disables SGR mode before tracking mode."
    (with-temporary-function
        ((quote nshell.infrastructure.terminal:terminal-control-sequences-supported-p)
         (lambda () t))
      (let ((disabled
              (with-output-to-string (*standard-output*)
                (nshell.infrastructure.terminal:ansi-disable-sgr-mouse))))
        (expect
         (format nil "~c[?1006l~c[?1000l" (code-char 27) (code-char 27))
         :to-equal disabled)))))
