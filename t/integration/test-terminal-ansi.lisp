(in-package #:nshell/test)

(describe "terminal-integration-tests"
  (it "terminal-ansi-emits-advanced-control-sequences"
    "Advanced terminal mode helpers emit standard ANSI control sequences."
    (let ((output (with-output-to-string (stream)
                    (nshell.infrastructure.terminal:ansi-hide-cursor stream)
                    (nshell.infrastructure.terminal:ansi-show-cursor stream)
                    (nshell.infrastructure.terminal:ansi-enable-bracketed-paste stream)
                    (nshell.infrastructure.terminal:ansi-disable-bracketed-paste stream)
                    (nshell.infrastructure.terminal:ansi-enable-sgr-mouse stream)
                    (nshell.infrastructure.terminal:ansi-disable-sgr-mouse stream)
                    (nshell.infrastructure.terminal:ansi-enable-alternate-screen stream)
                    (nshell.infrastructure.terminal:ansi-disable-alternate-screen stream))))
      (expect (search (format nil "~C[?25l" #\Esc) output) :to-be-truthy)
      (expect (search (format nil "~C[?25h" #\Esc) output) :to-be-truthy)
      (expect (search (format nil "~C[?2004h" #\Esc) output) :to-be-truthy)
      (expect (search (format nil "~C[?2004l" #\Esc) output) :to-be-truthy)
      (expect (search (format nil "~C[?1000h~C[?1006h" #\Esc #\Esc) output) :to-be-truthy)
      (expect (search (format nil "~C[?1006l~C[?1000l" #\Esc #\Esc) output) :to-be-truthy)
      (expect (search (format nil "~C[?1049h" #\Esc) output) :to-be-truthy)
      (expect (search (format nil "~C[?1049l" #\Esc) output) :to-be-truthy))))
