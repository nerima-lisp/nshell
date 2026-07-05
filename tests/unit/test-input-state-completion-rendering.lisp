(in-package #:nshell/test)

(in-suite input-state-tests)

(test completion-rendering-highlights-selected-candidate
  (let* ((candidates (list (nshell.domain.completion:make-candidate
                            "status"
                            :kind :command
                            :description "show working tree status")
                           (nshell.domain.completion:make-candidate
                            "stash"
                            :kind :command
                            :description "store local modifications")))
         (output (capture-standard-output
                   (nshell.presentation:render-completions
                    candidates
                    :selected-index 1))))
    (is (search "λ status  show working tree status" output))
    (is (search (format nil "~C[7mλ stash  store local modifications" #\Esc)
                output))
    (is (search (format nil "modifications  ~C[0m" #\Esc)
                output))))

(test completion-render-line-count-uses-rendered-column-layout
  (is (= 0 (nshell.presentation::completion-render-line-count nil
                                                              :terminal-width 80)))
  (is (= 2 (nshell.presentation::completion-render-line-count
            '("a" "b" "c" "d")
            :terminal-width 12)))
  (is (= 2 (nshell.presentation::completion-render-line-count
            '("a" "あ")
            :terminal-width 10)))
  (is (= 65 (nshell.presentation::completion-render-line-count
             (loop for index from 1 to 65
                   collect (format nil "cmd~d" index))
             :terminal-width 1))))

(test completion-default-terminal-width-uses-terminal-columns
  (let ((original-get-terminal-size
          (symbol-function 'nshell.infrastructure.acl:get-terminal-size)))
    (unwind-protect
         (progn
           (setf (symbol-function 'nshell.infrastructure.acl:get-terminal-size)
                 (lambda () (values 24 80)))
           (is (= 1 (nshell.presentation::completion-render-line-count
                     '("123456789012345"
                       "abcdefghijklmno"
                       "zzzzzzzzzzzzzzz"
                       "yyyyyyyyyyyyyyy")))))
      (setf (symbol-function 'nshell.infrastructure.acl:get-terminal-size)
            original-get-terminal-size))))

(test completion-rendering-pads-wide-candidates-to-column-width
  (let* ((candidates (list (nshell.domain.completion:make-candidate
                            "λ あ"
                            :kind :file)))
         (output (capture-standard-output
                   (nshell.presentation:render-completions
                    candidates
                    :terminal-width 80))))
    (is (string= (concatenate 'string
                              (string #\Newline)
                              "∙ λ あ  "
                              (string #\Newline))
                 output))))

(test completion-rendering-returns-rendered-line-count
  (let ((*standard-output* (make-string-output-stream)))
    (is (= 2 (nshell.presentation:render-completions
              '("a" "b" "c" "d")
              :terminal-width 12)))))

(test completion-common-prefix-uses-candidate-text
  (let ((candidates (list
                     (nshell.domain.completion:make-candidate
                      "checkout"
                      :kind :command
                      :description "switch branch")
                     (nshell.domain.completion:make-candidate
                      "check-ignore"
                      :kind :command
                      :description "debug ignores"))))
    (is (string= "check"
                 (nshell.presentation::completion-common-prefix candidates)))))

(test completion-common-prefix-extension-preserves-suffix
  (let* ((state (input-state
                 :buffer "git ch --dry-run"
                 :cursor-pos 6))
         (candidates '("checkout" "check-ignore")))
    (multiple-value-bind (new-state extended-p)
        (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                    candidates)
      (is (not (null extended-p)))
      (is-input-state new-state
                      :buffer "git check --dry-run"
                      :cursor-pos 9
                      :completion-index -1
                      :suggestion nil))))

(test completion-common-prefix-extension-shell-escapes-insertion
  (let* ((state (input-state
                 :buffer "cat my"
                 :cursor-pos 6))
         (candidates '("my file-a.txt" "my file-b.txt")))
    (multiple-value-bind (new-state extended-p)
        (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                    candidates)
      (is (not (null extended-p)))
      (is-input-state new-state
                      :buffer "cat my\\ file-"
                      :cursor-pos 13
                      :completion-index -1
                      :suggestion nil))))

(test completion-common-prefix-extension-quoted-token-keeps-spaces-raw
  (let* ((state (input-state
                 :buffer "cat 'my"
                 :cursor-pos 7))
         (candidates '("my file-a.txt" "my file-b.txt")))
    (multiple-value-bind (new-state extended-p)
        (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                    candidates)
      (is (not (null extended-p)))
      (is-input-state new-state
                      :buffer "cat 'my file-"
                      :cursor-pos 13
                      :completion-index -1
                      :suggestion nil))))

(test completion-common-prefix-extension-single-quoted-token-keeps-backslash-raw
  (let* ((state (input-state
                 :buffer "cat 'my\\ "
                 :cursor-pos 9))
         (candidates '("my\\ file-a.txt" "my\\ file-b.txt")))
    (multiple-value-bind (new-state extended-p)
        (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                    candidates)
      (is (not (null extended-p)))
      (is-input-state new-state
                      :buffer "cat 'my\\ file-"
                      :cursor-pos 14
                      :completion-index -1
                      :suggestion nil))))

(test completion-common-prefix-extension-closed-quoted-token-keeps-closing-quote
  (let* ((state (input-state
                 :buffer "cat \"my\""
                 :cursor-pos 8))
         (candidates '("my file-a.txt" "my file-b.txt")))
    (multiple-value-bind (new-state extended-p)
        (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                    candidates)
      (is (not (null extended-p)))
      (is-input-state new-state
                      :buffer "cat \"my file-\""
                      :cursor-pos 13
                      :completion-index -1
                      :suggestion nil))))

(test completion-common-prefix-extension-matches-escaped-token
  (let* ((state (input-state
                 :buffer "cat my\\ "
                 :cursor-pos 8))
         (candidates '("my file-a.txt" "my file-b.txt")))
    (multiple-value-bind (new-state extended-p)
        (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                    candidates)
      (is (not (null extended-p)))
      (is-input-state new-state
                      :buffer "cat my\\ file-"
                      :cursor-pos 13
                      :completion-index -1
                      :suggestion nil))))

(test completion-common-prefix-extension-keeps-unquoted-trailing-quote-literal
  (let* ((state (input-state
                 :buffer "cat my\""
                 :cursor-pos 7))
         (candidates '("my file-a.txt" "my file-b.txt")))
    (multiple-value-bind (new-state extended-p)
        (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                    candidates)
      (is (null extended-p))
      (is-input-state new-state
                      :buffer "cat my\""
                      :cursor-pos 7
                      :completion-index -1
                      :suggestion nil))))

(test completion-insertion-text-escapes-by-quote-context
  "insertion-text adds backslashes for unquoted/double; single handles apostrophes specially."
  (flet ((ins (text &key (ctx nil))
           (nshell.presentation::%completion-insertion-text text :quote-context ctx)))
    (is (string= "foo"         (ins "foo")))
    (is (string= "foo\\ bar"   (ins "foo bar")))
    (is (string= "foo\\$bar"   (ins "foo$bar")))
    (is (string= "foo bar"     (ins "foo bar" :ctx :double)))
    (is (string= "foo\\$bar"   (ins "foo$bar" :ctx :double)))
    (is (string= "foo'\\''bar" (ins "foo'bar" :ctx :single)))
    (is (string= "foo bar"     (ins "foo bar" :ctx :single)))))

(test completion-unescape-token-strips-backslashes-by-context
  "unescape-token strips \\ in unquoted/double only for escapable chars."
  (flet ((un (text &key (ctx nil))
           (nshell.presentation::%completion-unescape-token text :quote-context ctx)))
    ;; unquoted: any char after \ has its backslash consumed
    (is (string= "foo bar"  (un "foo\\ bar")))
    ;; double-quoted: only double-quote-escapable chars have backslash consumed
    (is (string= "foo$bar"  (un "foo\\$bar" :ctx :double)))
    ;; backslash + space in double-quote keeps the backslash (space is not special)
    (is (string= "foo\\ bar" (un "foo\\ bar" :ctx :double)))
    ;; single-quoted: backslash is never consumed
    (is (string= "foo\\bar" (un "foo\\bar"  :ctx :single)))))

(test completion-escaped-position-p-counts-preceding-backslashes
  "escaped-position-p detects an odd number of immediately preceding backslashes."
  (flet ((esc (input pos)
           (nshell.presentation::%completion-escaped-position-p input pos)))
    (is (not (esc "abc" 2)))
    ;; "a\ " has chars a(0) \(1) space(2); position=2 looks back at index 1 (\) → escaped
    (is (esc "a\\ " 2))
    ;; "a\\ " has chars a(0) \(1) \(2) space(3); position=3 looks back at 2 backslashes → even → not escaped
    (is (not (esc "a\\\\ " 3)))))

(test completion-quote-context-returns-quote-style-from-token-start
  "quote-context returns :single/:double at quote char, nil for plain start."
  (flet ((ctx (input start &optional (end 99))
           (nshell.presentation::%completion-quote-context input start end)))
    (is (eq :single (ctx "'foo" 0)))
    (is (eq :double (ctx "\"foo" 0)))
    (is (null       (ctx "foo"  0)))))

(test completion-token-bounds-return-slices
  "completion token bounds are explicit slices; body bounds remove quote delimiters."
  (let* ((token-bounds (nshell.presentation::%completion-token-bounds
                        "echo \"foo bar\""
                        7))
         (body-bounds (nshell.presentation::%completion-token-body-bounds
                       "echo \"foo bar\""
                       token-bounds))
         (empty-bounds (nshell.presentation::%completion-token-bounds
                        "echo "
                        5)))
    (is (nshell.presentation::%completion-token-slice-p token-bounds))
    (is (not (fboundp 'nshell.presentation::completion-token-slice-p)))
    (is (= 5 (nshell.presentation::completion-token-slice-start token-bounds)))
    (is (= 14 (nshell.presentation::completion-token-slice-end token-bounds)))
    (is (nshell.presentation::%completion-token-slice-p body-bounds))
    (is (= 6 (nshell.presentation::completion-token-slice-start body-bounds)))
    (is (= 13 (nshell.presentation::completion-token-slice-end body-bounds)))
    (is (= 5 (nshell.presentation::completion-token-slice-start empty-bounds)))
    (is (= 5 (nshell.presentation::completion-token-slice-end empty-bounds)))))

(test completion-token-context-captures-raw-token-and-quote-state
  "completion-token-context centralizes bounds, quote state, and raw token extraction."
  (let ((context (nshell.presentation::%completion-token-context "cat 'my\\ " 9)))
    (is (nshell.presentation::%completion-token-context-p context))
    (is (not (fboundp 'nshell.presentation::completion-token-context-p)))
    (is (eq :single
            (nshell.presentation::completion-token-context-quote-context context)))
    (is (string= "my\\ "
                 (nshell.presentation::completion-token-context-raw-token context)))
    (is (= 5 (nshell.presentation::completion-token-slice-start
              (nshell.presentation::completion-token-context-body-bounds context))))
    (is (= 9 (nshell.presentation::completion-token-slice-end
              (nshell.presentation::completion-token-context-body-bounds context))))))

(test completion-token-raw-accessors-stay-internal
  "completion token structs expose explicit readers; generated slot readers remain internal."
  (let ((context (nshell.presentation::%completion-token-context "cat foo" 7)))
    (is (fboundp 'nshell.presentation::%completion-token-context-bounds))
    (is (fboundp 'nshell.presentation::%completion-token-slice-start))
    (is (not (eq (symbol-function
                  'nshell.presentation::completion-token-context-bounds)
                 (symbol-function
                  'nshell.presentation::%completion-token-context-bounds))))
    (is (not (eq (symbol-function
                  'nshell.presentation::completion-token-slice-start)
                 (symbol-function
                  'nshell.presentation::%completion-token-slice-start))))
    (is (= 4
           (nshell.presentation::completion-token-slice-start
            (nshell.presentation::completion-token-context-bounds context))))
    (is (= 7
           (nshell.presentation::completion-token-slice-end
            (nshell.presentation::completion-token-context-bounds context))))))

(test common-prefix-two-finds-shared-leading-substring
  "common-prefix-two returns the longest common prefix of two strings."
  (flet ((pre (a b) (nshell.presentation::%common-prefix-two a b)))
    (is (string= ""        (pre "" "abc")))
    (is (string= ""        (pre "abc" "def")))
    (is (string= "check"   (pre "checkout" "check-ignore")))
    (is (string= "abc"     (pre "abc" "abc")))))

(test completion-escape-character-p-identifies-shell-special-chars
  "escape-character-p returns true for chars requiring backslash in unquoted context."
  (flet ((esc (ch) (nshell.presentation::%completion-escape-character-p ch)))
    (is (esc #\Space))
    (is (esc #\$))
    (is (esc #\*))
    (is (esc #\\))
    (is (not (esc #\a)))
    (is (not (esc #\-)))))

(test completion-quote-delimiters-extracts-open-and-close-quote
  "quote-delimiters returns the opening and closing quote strings for a token range."
  (flet ((delims (input start end)
           (multiple-value-list
            (nshell.presentation::%completion-quote-delimiters input start end))))
    ;; closed single-quoted token
    (is (equal '("'" "'") (delims "'foo'" 0 5)))
    ;; open single-quoted token (no closing quote)
    (is (equal '("'" "")  (delims "'foo"  0 4)))
    ;; closed double-quoted token
    (is (equal '("\"" "\"") (delims "\"foo\"" 0 5)))
    ;; unquoted token
    (is (equal '("" "")  (delims "foo" 0 3)))))

(test completion-splice-with-quote-context-inserts-replacement-at-range
  "splice-with-quote-context replaces [start,end) with the replacement string."
  (flet ((splice (input start end replacement &key ctx)
           (multiple-value-list
            (nshell.presentation::%completion-splice-with-quote-context
             input start end replacement :quote-context ctx))))
    ;; unquoted: no delimiters added
    (is (equal '("cat bar" 7) (splice "cat foo" 4 7 "bar")))
    ;; single-quoted closed: keep surrounding quotes; cursor = start + 1(quote) + 3(bar) = 8
    (is (equal '("cat 'bar'" 8)
               (splice "cat 'foo'" 4 9 "bar" :ctx :single)))))
