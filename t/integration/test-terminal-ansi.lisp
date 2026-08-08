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

  (it "terminal-ansi-cursor-motion-is-byte-identical-to-the-hand-rolled-form"
    "The cursor helpers emit exactly the sequences the presentation tier used to
build with (format t \"~~C[~~dA\" #\\Esc n) and friends. These are spelled out as
literals rather than delegated to cl-tty-kit so the test would still catch a
byte change if the kit's emitters ever moved."
    (flet ((emitted (thunk) (with-output-to-string (stream) (funcall thunk stream))))
      (expect (format nil "~C[2A" #\Esc)
              :to-equal (emitted (lambda (s)
                                   (nshell.infrastructure.terminal:ansi-cursor-up 2 s))))
      (expect (format nil "~C[3B" #\Esc)
              :to-equal (emitted (lambda (s)
                                   (nshell.infrastructure.terminal:ansi-cursor-down 3 s))))
      (expect (format nil "~C[12C" #\Esc)
              :to-equal (emitted (lambda (s)
                                   (nshell.infrastructure.terminal:ansi-cursor-forward 12 s))))
      (expect (format nil "~C[7D" #\Esc)
              :to-equal (emitted (lambda (s)
                                   (nshell.infrastructure.terminal:ansi-cursor-back 7 s))))
      (expect (format nil "~C[4G" #\Esc)
              :to-equal (emitted (lambda (s)
                                   (nshell.infrastructure.terminal:ansi-cursor-column 4 s))))))

  (it "terminal-ansi-sgr-helpers-are-byte-identical-to-the-hand-rolled-form"
    "The style helpers emit exactly the SGR sequences the presentation tier used
to write inline."
    (flet ((emitted (thunk) (with-output-to-string (stream) (funcall thunk stream))))
      (expect (format nil "~C[2m" #\Esc)
              :to-equal (emitted #'nshell.infrastructure.terminal:ansi-dim))
      (expect (format nil "~C[7m" #\Esc)
              :to-equal (emitted #'nshell.infrastructure.terminal:ansi-reverse))
      (expect (format nil "~C[0m" #\Esc)
              :to-equal (emitted #'nshell.infrastructure.terminal:ansi-reset-style)))))

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
              output)))
