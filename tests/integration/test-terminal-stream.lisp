(in-package #:nshell/test)

(in-suite terminal-integration-tests)

(test terminal-stream-decodes-meta-y
  "ESC y is decoded as Meta-Y for yank-pop."
  (let ((event (single-key-event-from-string (esc-sequence "y"))))
    (is (eq :alt-y
            (nshell.infrastructure.terminal:key-event-type event)))))

(test terminal-stream-decodes-printable-and-control-keys
  "Terminal input is decoded through the public stream reader."
  (let* ((control-cases '((1 . :ctrl-a)
                          (2 . :ctrl-b)
                          (3 . :ctrl-c)
                          (4 . :ctrl-d)
                          (5 . :ctrl-e)
                          (6 . :ctrl-f)
                          (7 . :ctrl-g)
                          (8 . :backspace)
                          (11 . :ctrl-k)
                          (12 . :ctrl-l)
                          (14 . :ctrl-n)
                          (16 . :ctrl-p)
                          (18 . :ctrl-r)
                          (19 . :ctrl-s)
                          (20 . :ctrl-t)
                          (21 . :ctrl-u)
                          (23 . :ctrl-w)
                          (25 . :ctrl-y)
                          (31 . :ctrl-underscore)))
         (events (read-key-events-from-string
                  (coerce (append (list #\a #\Tab #\Newline)
                                  (mapcar (lambda (case)
                                            (code-char (car case)))
                                          control-cases))
                          'string))))
    (is (= (+ 3 (length control-cases)) (length events)))
    (is (eq :char (nshell.infrastructure.terminal:key-event-type (first events))))
    (is (char= #\a (nshell.infrastructure.terminal:key-event-char (first events))))
    (is (eq :tab (nshell.infrastructure.terminal:key-event-type (second events))))
    (is (eq :enter (nshell.infrastructure.terminal:key-event-type (third events))))
    (loop :for event :in (nthcdr 3 events)
          :for case :in control-cases
          :do (is (eq (cdr case)
                      (nshell.infrastructure.terminal:key-event-type event))))))

(test terminal-stream-decodes-unicode-graphic-characters
  "Unicode graphic characters pass through terminal decoding into input state."
  (let* ((line "echo あ漢")
         (events (read-key-events-from-string line))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events)))
    (is (= (length line) (length events)))
    (is (every (lambda (event)
                 (eq :char (nshell.infrastructure.terminal:key-event-type event)))
               events))
    (is (string= line (nshell.presentation:input-state-buffer state)))
    (is (= (length line) (nshell.presentation:input-state-cursor-pos state)))))

(test terminal-stream-decodes-csi-navigation
  "Common CSI escape sequences produce navigation key events."
  (dolist (case '(("[A" . :up)
                  ("[B" . :down)
                  ("[C" . :right)
                  ("[D" . :left)
                  ("[H" . :home)
                  ("[F" . :end)
                  ("[3~" . :delete)
                  ("[5~" . :page-up)
                  ("[6~" . :page-down)
                  ("[Z" . :shift-tab)))
    (let ((event (single-key-event-from-string (esc-sequence (car case)))))
      (is (eq (cdr case)
              (nshell.infrastructure.terminal:key-event-type event))))))

(test terminal-stream-decodes-csi-without-consuming-following-input
  "A CSI event stops at its final byte so later input remains readable."
  (let ((events (read-key-events-from-string
                 (concatenate 'string (esc-sequence "[C") "ab"))))
    (is (= 3 (length events)))
    (is (eq :right
            (nshell.infrastructure.terminal:key-event-type (first events))))
    (is (char= #\a
               (nshell.infrastructure.terminal:key-event-char (second events))))
    (is (char= #\b
               (nshell.infrastructure.terminal:key-event-char (third events))))))

(test terminal-stream-decodes-bracketed-paste-as-single-event
  "Bracketed paste content is decoded as one structured paste event."
  (let* ((paste-text (format nil "echo one~%echo two"))
         (events (read-key-events-from-string
                  (concatenate 'string
                               (esc-sequence "[200~")
                               paste-text
                               (esc-sequence "[201~")
                               "x")))
         (paste (first events))
         (next (second events)))
    (is (= 2 (length events)))
    (is (eq :paste
            (nshell.infrastructure.terminal:key-event-type paste)))
    (is (equal (list :protocol :bracketed :text paste-text)
               (nshell.infrastructure.terminal:key-event-data paste)))
    (is (eq :char
            (nshell.infrastructure.terminal:key-event-type next)))
    (is (char= #\x
               (nshell.infrastructure.terminal:key-event-char next)))))

(test terminal-stream-normalizes-bracketed-paste-newlines
  "Bracketed paste normalizes CRLF and CR line endings to LF."
  (let* ((raw-paste (format nil "echo one~C~Cecho two~Cecho three"
                            #\Return #\Newline #\Return))
         (normalized-paste (format nil "echo one~%echo two~%echo three"))
         (events (read-key-events-from-string
                  (concatenate 'string
                               (esc-sequence "[200~")
                               raw-paste
                               (esc-sequence "[201~"))))
         (paste (first events)))
    (is (= 1 (length events)))
    (is (eq :paste
            (nshell.infrastructure.terminal:key-event-type paste)))
    (is (equal (list :protocol :bracketed :text normalized-paste)
               (nshell.infrastructure.terminal:key-event-data paste)))))

(test terminal-stream-decodes-modified-arrows-and-sgr-mouse-reports
  "Advanced terminal CSI variants are normalized before presentation handling."
  (let ((shift-right (single-key-event-from-string (esc-sequence "[1;2C")))
        (shift-left (single-key-event-from-string (esc-sequence "[1;2D")))
        (alt-left (single-key-event-from-string (esc-sequence "[1;3D")))
        (ctrl-right (single-key-event-from-string (esc-sequence "[1;5C")))
        (shift-ctrl-right (single-key-event-from-string (esc-sequence "[1;6C")))
        (mouse (single-key-event-from-string (esc-sequence "[<0;10;5M")))
        (mouse-release (single-key-event-from-string (esc-sequence "[<0;10;5m")))
        (mouse-wheel (single-key-event-from-string (esc-sequence "[<64;12;7M"))))
    (is (eq :shift-right
            (nshell.infrastructure.terminal:key-event-type shift-right)))
    (is (eq :shift-left
            (nshell.infrastructure.terminal:key-event-type shift-left)))
    (is (eq :alt-left
            (nshell.infrastructure.terminal:key-event-type alt-left)))
    (is (eq :ctrl-right
            (nshell.infrastructure.terminal:key-event-type ctrl-right)))
    (is (eq :shift-ctrl-right
            (nshell.infrastructure.terminal:key-event-type shift-ctrl-right)))
    (is (eq :mouse
            (nshell.infrastructure.terminal:key-event-type mouse)))
    (is (= 0 (nshell.infrastructure.terminal:key-event-number mouse)))
    (is (equal '(:protocol :sgr :button 0 :button-code 0
                 :column 10 :row 5 :event :press :modifiers nil)
               (nshell.infrastructure.terminal:key-event-data mouse)))
    (is (eq :release
            (getf (nshell.infrastructure.terminal:key-event-data mouse-release)
                  :event)))
    (is (eq :wheel-up
            (getf (nshell.infrastructure.terminal:key-event-data mouse-wheel)
                  :event)))))

(test terminal-stream-decodes-meta-editing-keys
  "ESC-prefixed Meta editing chords normalize to presentation key events."
  (let ((meta-b (single-key-event-from-string (esc-sequence "b")))
        (meta-f (single-key-event-from-string (esc-sequence "f")))
        (meta-c (single-key-event-from-string (esc-sequence "c")))
        (meta-d (single-key-event-from-string (esc-sequence "d")))
        (meta-l (single-key-event-from-string (esc-sequence "l")))
        (meta-r (single-key-event-from-string (esc-sequence "r")))
        (meta-dot (single-key-event-from-string (esc-sequence ".")))
        (meta-s (single-key-event-from-string (esc-sequence "s")))
        (meta-t (single-key-event-from-string (esc-sequence "t")))
        (meta-u (single-key-event-from-string (esc-sequence "u")))
        (meta-shift-s (single-key-event-from-string (esc-sequence "S")))
        (meta-shift-u (single-key-event-from-string (esc-sequence "U")))
        (meta-backspace
          (single-key-event-from-string
           (coerce (list #\Esc (code-char 127)) 'string)))
        (meta-control-h
          (single-key-event-from-string
           (coerce (list #\Esc (code-char 8)) 'string))))
    (is (eq :alt-b
            (nshell.infrastructure.terminal:key-event-type meta-b)))
    (is (eq :alt-f
            (nshell.infrastructure.terminal:key-event-type meta-f)))
    (is (eq :alt-c
            (nshell.infrastructure.terminal:key-event-type meta-c)))
    (is (eq :alt-d
            (nshell.infrastructure.terminal:key-event-type meta-d)))
    (is (eq :alt-l
            (nshell.infrastructure.terminal:key-event-type meta-l)))
    (is (eq :alt-r
            (nshell.infrastructure.terminal:key-event-type meta-r)))
    (is (eq :alt-dot
            (nshell.infrastructure.terminal:key-event-type meta-dot)))
    (is (eq :alt-s
            (nshell.infrastructure.terminal:key-event-type meta-s)))
    (is (eq :alt-t
            (nshell.infrastructure.terminal:key-event-type meta-t)))
    (is (eq :alt-u
            (nshell.infrastructure.terminal:key-event-type meta-u)))
    (is (eq :alt-s
            (nshell.infrastructure.terminal:key-event-type meta-shift-s)))
    (is (eq :alt-u
            (nshell.infrastructure.terminal:key-event-type meta-shift-u)))
    (is (eq :alt-backspace
            (nshell.infrastructure.terminal:key-event-type meta-backspace)))
    (is (eq :alt-backspace
            (nshell.infrastructure.terminal:key-event-type meta-control-h)))))
