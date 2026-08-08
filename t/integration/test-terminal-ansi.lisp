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
      (expect (search (format nil "~C[?1049l" #\Esc) output) :to-be-truthy)))

  (it "terminal-ansi-emits-exact-osc52-clipboard-sequence"
    "The clipboard helper emits OSC 52 with a base64 payload and BEL terminator."
    (let ((output (with-output-to-string (stream)
                    (nshell.infrastructure.terminal:ansi-copy-to-clipboard
                     "Hello, nshell!"
                     stream))))
      (expect (format nil "~C]52;c;SGVsbG8sIG5zaGVsbCE=~C" #\Esc #\Bell)
              :to-equal
              output)))

  (it "terminal-ansi-osc52-encodes-utf8-before-base64"
    "Non-ASCII clipboard text is encoded as UTF-8 before base64."
    (let ((output (with-output-to-string (stream)
                    (nshell.infrastructure.terminal:ansi-copy-to-clipboard
                     "café"
                     stream))))
      (expect (format nil "~C]52;c;Y2Fmw6k=~C" #\Esc #\Bell)
              :to-equal
              output))))
