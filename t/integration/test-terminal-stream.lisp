(in-package #:nshell/test)

(describe "terminal-integration-tests"
  (it "terminal-stream-decodes-meta-y"
    "ESC y is decoded as Meta-Y for yank-pop."
    (let ((event (single-key-event-from-string (esc-sequence "y"))))
      (expect :alt-y :to-be (nshell.infrastructure.terminal:key-event-type event))))

  (it "terminal-stream-decodes-printable-and-control-keys"
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
      (expect (+ 3 (length control-cases)) :to-equal (length events))
      (expect :char :to-be (nshell.infrastructure.terminal:key-event-type (first events)))
      (expect #\a :to-equal (nshell.infrastructure.terminal:key-event-char (first events)))
      (expect :tab :to-be (nshell.infrastructure.terminal:key-event-type (second events)))
      (expect :enter :to-be (nshell.infrastructure.terminal:key-event-type (third events)))
      (loop :for event :in (nthcdr 3 events)
            :for case :in control-cases
            :do (expect (cdr case) :to-be (nshell.infrastructure.terminal:key-event-type event)))))

  (it "terminal-stream-decodes-unicode-graphic-characters"
    "Unicode graphic characters pass through terminal decoding into input state."
    (let* ((line "echo あ漢")
           (events (read-key-events-from-string line))
           (state (apply-key-events-to-input-state
                   (input-state)
                   events)))
      (expect (length line) :to-equal (length events))
      (expect (every (lambda (event)
                   (eq :char (nshell.infrastructure.terminal:key-event-type event)))
                 events) :to-be-truthy)
      (expect line :to-equal (nshell.presentation:input-state-buffer state))
      (expect (length line) :to-equal (nshell.presentation:input-state-cursor-pos state))))

  (it "terminal-stream-decodes-csi-navigation"
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
        (expect (cdr case) :to-be (nshell.infrastructure.terminal:key-event-type event)))))

  (it "terminal-stream-decodes-csi-without-consuming-following-input"
    "A CSI event stops at its final byte so later input remains readable."
    (let ((events (read-key-events-from-string
                   (concatenate 'string (esc-sequence "[C") "ab"))))
      (expect 3 :to-equal (length events))
      (expect :right :to-be (nshell.infrastructure.terminal:key-event-type (first events)))
      (expect #\a :to-equal (nshell.infrastructure.terminal:key-event-char (second events)))
      (expect #\b :to-equal (nshell.infrastructure.terminal:key-event-char (third events)))))

  (it "terminal-stream-decodes-bracketed-paste-as-single-event"
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
      (expect 2 :to-equal (length events))
      (expect :paste :to-be (nshell.infrastructure.terminal:key-event-type paste))
      (expect (list :protocol :bracketed :text paste-text) :to-equal (nshell.infrastructure.terminal:key-event-data paste))
      (expect :char :to-be (nshell.infrastructure.terminal:key-event-type next))
      (expect #\x :to-equal (nshell.infrastructure.terminal:key-event-char next))))

  (it "terminal-stream-normalizes-bracketed-paste-newlines"
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
      (expect 1 :to-equal (length events))
      (expect :paste :to-be (nshell.infrastructure.terminal:key-event-type paste))
      (expect (list :protocol :bracketed :text normalized-paste) :to-equal (nshell.infrastructure.terminal:key-event-data paste))))

  (it "terminal-stream-caps-bracketed-paste-retention"
    "Bracketed paste input is consumed fully but retained text is bounded."
    (let* ((limit 4096)
           (paste-text (make-string (+ limit 128) :initial-element #\x))
           (events (read-key-events-from-string
                    (concatenate 'string
                                 (esc-sequence "[200~")
                                 paste-text
                                 (esc-sequence "[201~")
                                 "x")))
           (paste (first events))
           (next (second events)))
      (expect 2 :to-equal (length events))
      (expect limit :to-equal
              (length (getf (nshell.infrastructure.terminal:key-event-data paste)
                            :text)))
      (expect :char :to-be (nshell.infrastructure.terminal:key-event-type next))
      (expect #\x :to-equal (nshell.infrastructure.terminal:key-event-char next))))

  (it "terminal-stream-decodes-modified-arrows-and-sgr-mouse-reports"
    "Advanced terminal CSI variants are normalized before presentation handling."
    (let ((shift-right (single-key-event-from-string (esc-sequence "[1;2C")))
          (shift-left (single-key-event-from-string (esc-sequence "[1;2D")))
          (alt-left (single-key-event-from-string (esc-sequence "[1;3D")))
          (ctrl-right (single-key-event-from-string (esc-sequence "[1;5C")))
          (shift-ctrl-right (single-key-event-from-string (esc-sequence "[1;6C")))
          (mouse (single-key-event-from-string (esc-sequence "[<0;10;5M")))
          (mouse-release (single-key-event-from-string (esc-sequence "[<0;10;5m")))
          (mouse-wheel (single-key-event-from-string (esc-sequence "[<64;12;7M"))))
      (expect :shift-right :to-be (nshell.infrastructure.terminal:key-event-type shift-right))
      (expect :shift-left :to-be (nshell.infrastructure.terminal:key-event-type shift-left))
      (expect :alt-left :to-be (nshell.infrastructure.terminal:key-event-type alt-left))
      (expect :ctrl-right :to-be (nshell.infrastructure.terminal:key-event-type ctrl-right))
      (expect :shift-ctrl-right :to-be (nshell.infrastructure.terminal:key-event-type shift-ctrl-right))
      (expect :mouse :to-be (nshell.infrastructure.terminal:key-event-type mouse))
      (expect 0 :to-equal (nshell.infrastructure.terminal:key-event-number mouse))
      (expect '(:protocol :sgr :button 0 :button-code 0
                   :column 10 :row 5 :event :press :modifiers nil) :to-equal (nshell.infrastructure.terminal:key-event-data mouse))
      (expect :release :to-be (getf (nshell.infrastructure.terminal:key-event-data mouse-release)
                    :event))
      (expect :wheel-up :to-be (getf (nshell.infrastructure.terminal:key-event-data mouse-wheel)
                    :event))))

  (it "terminal-stream-queries-cursor-position"
    "Cursor position reports are decoded to 1-based coordinates."
    (let ((response (coerce (list #\Esc #\[ #\6 #\; #\1 #\1 #\R) 'string))
          (captured-output nil)
          (row nil)
          (column nil))
      (with-input-from-string (input response)
        (let ((*standard-input* input))
          (setf captured-output
                (with-output-to-string (output)
                  (let ((*standard-output* output))
                    (multiple-value-setq (row column)
                      (nshell.infrastructure.terminal:query-cursor-position
                       :attempts 8 :sleep-seconds 0)))))))
      (expect row :to-equal 6)
      (expect column :to-equal 11)
      (expect captured-output :to-equal (esc-sequence "[6n"))))

  (it "terminal-stream-cursor-query-preserves-ordinary-input"
    "A missing cursor response must not consume the next ordinary key."
    (with-input-from-string (input "x")
      (let ((*standard-input* input))
        (with-output-to-string (output)
          (let ((*standard-output* output))
            (multiple-value-bind (row column)
                (nshell.infrastructure.terminal:query-cursor-position
                 :attempts 1 :sleep-seconds 0)
              (expect row :to-equal nil)
              (expect column :to-equal nil)
              (expect (read-char *standard-input* nil nil) :to-equal #\x)))))))

  (it "terminal-stream-decodes-meta-editing-keys"
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
      (expect :alt-b :to-be (nshell.infrastructure.terminal:key-event-type meta-b))
      (expect :alt-f :to-be (nshell.infrastructure.terminal:key-event-type meta-f))
      (expect :alt-c :to-be (nshell.infrastructure.terminal:key-event-type meta-c))
      (expect :alt-d :to-be (nshell.infrastructure.terminal:key-event-type meta-d))
      (expect :alt-l :to-be (nshell.infrastructure.terminal:key-event-type meta-l))
      (expect :alt-r :to-be (nshell.infrastructure.terminal:key-event-type meta-r))
      (expect :alt-dot :to-be (nshell.infrastructure.terminal:key-event-type meta-dot))
      (expect :alt-s :to-be (nshell.infrastructure.terminal:key-event-type meta-s))
      (expect :alt-t :to-be (nshell.infrastructure.terminal:key-event-type meta-t))
      (expect :alt-u :to-be (nshell.infrastructure.terminal:key-event-type meta-u))
      (expect :alt-s :to-be (nshell.infrastructure.terminal:key-event-type meta-shift-s))
      (expect :alt-u :to-be (nshell.infrastructure.terminal:key-event-type meta-shift-u))
      (expect :alt-backspace :to-be (nshell.infrastructure.terminal:key-event-type meta-backspace))
      (expect :alt-backspace :to-be (nshell.infrastructure.terminal:key-event-type meta-control-h)))))
