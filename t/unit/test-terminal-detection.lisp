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
  (it "sgr-mouse-mode-enables-tracking-before-sgr-and-disables-in-reverse"
    "The terminal receives the normal tracking and SGR modes in paired order."
    (with-temporary-function
        ('nshell.infrastructure.terminal:terminal-control-sequences-supported-p
         (lambda () t))
      (let ((enabled
              (with-output-to-string (*standard-output*)
                (nshell.infrastructure.terminal:ansi-enable-sgr-mouse)))
            (disabled
              (with-output-to-string (*standard-output*)
                (nshell.infrastructure.terminal:ansi-disable-sgr-mouse))))
        (expect
         (concatenate 'string
                      (string #\Esc) "[?1000h"
                      (string #\Esc) "[?1006h")
         :to-equal enabled)
        (expect
         (concatenate 'string
                      (string #\Esc) "[?1006l"
                      (string #\Esc) "[?1000l")
         :to-equal disabled)))))
