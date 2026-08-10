(in-package #:nshell/test)

(describe "input-state-tests"
  (it "completion-rendering-highlights-selected-candidate"
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
      (expect (search "λ status  show working tree status" output) :to-be-truthy)
      (expect (search (format nil "~C[7mλ stash  store local modifications" #\Esc)
                  output) :to-be-truthy)
      (expect (search (format nil "modifications  ~C[0m" #\Esc)
                  output) :to-be-truthy)))

  (it "completion-render-line-count-uses-rendered-column-layout"
    (expect 0 :to-equal (nshell.presentation::completion-render-line-count nil
                                                                :terminal-width 80))
    (expect 2 :to-equal (nshell.presentation::completion-render-line-count
              '("a" "b" "c" "d")
              :terminal-width 12))
    (expect 2 :to-equal (nshell.presentation::completion-render-line-count
              '("a" "あ")
              :terminal-width 10))
    (expect 65 :to-equal (nshell.presentation::completion-render-line-count
               (loop for index from 1 to 65
                     collect (format nil "cmd~d" index))
               :terminal-width 1)))

  (it "completion-default-terminal-width-uses-terminal-columns"
    (let ((original-get-terminal-size
            (symbol-function 'nshell.infrastructure.acl:get-terminal-size)))
      (unwind-protect
           (progn
             (setf (symbol-function 'nshell.infrastructure.acl:get-terminal-size)
                   (lambda () (values 24 80)))
             (expect 1 :to-equal (nshell.presentation::completion-render-line-count
                       '("123456789012345"
                         "abcdefghijklmno"
                         "zzzzzzzzzzzzzzz"
                         "yyyyyyyyyyyyyyy"))))
        (setf (symbol-function 'nshell.infrastructure.acl:get-terminal-size)
              original-get-terminal-size))))

  (it "completion-rendering-falls-back-when-terminal-size-fails"
    (let ((original-get-terminal-size
            (symbol-function 'nshell.infrastructure.acl:get-terminal-size)))
      (unwind-protect
           (progn
             (setf (symbol-function 'nshell.infrastructure.acl:get-terminal-size)
                   (lambda () (error "terminal size unavailable")))
             (expect 1 :to-equal (nshell.presentation::completion-render-line-count
                       '("fallback"))))
        (setf (symbol-function 'nshell.infrastructure.acl:get-terminal-size)
              original-get-terminal-size))))

  (it "completion-rendering-uses-all-candidate-kind-icons"
    (let* ((candidates (list
                        (nshell.domain.completion:make-candidate
                         "directory" :kind :directory)
                        (nshell.domain.completion:make-candidate
                         "--option" :kind :option)
                        (nshell.domain.completion:make-candidate
                         "VARIABLE" :kind :variable)
                        (nshell.domain.completion:make-candidate
                         "unknown" :kind :unknown)))
           (output (capture-standard-output
                     (nshell.presentation:render-completions
                      candidates
                      :terminal-width 80))))
      (expect (search "/ directory" output) :to-be-truthy)
      (expect (search "- --option" output) :to-be-truthy)
      (expect (search "$  VARIABLE" output) :to-be-truthy)
      (expect (search "· unknown" output) :to-be-truthy)))

  (it "completion-rendering-reports-omitted-candidates"
    (let* ((candidates (loop for index from 1 to 65
                             collect (nshell.domain.completion:make-candidate
                                      (format nil "candidate-~d" index)
                                      :kind :file)))
           (output (capture-standard-output
                     (nshell.presentation:render-completions
                      candidates
                      :terminal-width 80))))
      (expect (search "… and 1 more" output) :to-be-truthy)
      (expect 14 :to-equal (nshell.presentation:render-completions
                candidates
                :terminal-width 80))))

  (it "completion-rendering-pads-wide-candidates-to-column-width"
    (let* ((candidates (list (nshell.domain.completion:make-candidate
                              "λ あ"
                              :kind :file)))
           (output (capture-standard-output
                     (nshell.presentation:render-completions
                      candidates
                      :terminal-width 80))))
      (expect (concatenate 'string
                                (string #\Newline)
                                "∙ λ あ  "
                                (string #\Newline)) :to-equal output)))

  (it "completion-rendering-returns-rendered-line-count"
    (let ((*standard-output* (make-string-output-stream)))
      (expect 2 :to-equal (nshell.presentation:render-completions
                '("a" "b" "c" "d")
                :terminal-width 12))))

  (it "completion-common-prefix-uses-candidate-text"
    (let ((candidates (list
                       (nshell.domain.completion:make-candidate
                        "checkout"
                        :kind :command
                        :description "switch branch")
                       (nshell.domain.completion:make-candidate
                        "check-ignore"
                        :kind :command
                        :description "debug ignores"))))
      (expect "check" :to-equal (nshell.presentation::completion-common-prefix candidates))))

  (it "completion-common-prefix-extension-preserves-suffix"
    (let* ((state (input-state
                   :buffer "git ch --dry-run"
                   :cursor-pos 6))
           (candidates '("checkout" "check-ignore")))
      (multiple-value-bind (new-state extended-p)
          (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                      candidates)
        (expect (null extended-p) :to-be-falsy)
        (is-input-state new-state
                        :buffer "git check --dry-run"
                        :cursor-pos 9
                        :completion-index -1
                        :suggestion nil))))

  (it "completion-common-prefix-extension-shell-escapes-insertion"
    (let* ((state (input-state
                   :buffer "cat my"
                   :cursor-pos 6))
           (candidates '("my file-a.txt" "my file-b.txt")))
      (multiple-value-bind (new-state extended-p)
          (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                      candidates)
        (expect (null extended-p) :to-be-falsy)
        (is-input-state new-state
                        :buffer "cat my\\ file-"
                        :cursor-pos 13
                        :completion-index -1
                        :suggestion nil))))

  (it "completion-common-prefix-extension-quoted-token-keeps-spaces-raw"
    (let* ((state (input-state
                   :buffer "cat 'my"
                   :cursor-pos 7))
           (candidates '("my file-a.txt" "my file-b.txt")))
      (multiple-value-bind (new-state extended-p)
          (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                      candidates)
        (expect (null extended-p) :to-be-falsy)
        (is-input-state new-state
                        :buffer "cat 'my file-"
                        :cursor-pos 13
                        :completion-index -1
                        :suggestion nil))))

  (it "completion-common-prefix-extension-single-quoted-token-keeps-backslash-raw"
    (let* ((state (input-state
                   :buffer "cat 'my\\ "
                   :cursor-pos 9))
           (candidates '("my\\ file-a.txt" "my\\ file-b.txt")))
      (multiple-value-bind (new-state extended-p)
          (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                      candidates)
        (expect (null extended-p) :to-be-falsy)
        (is-input-state new-state
                        :buffer "cat 'my\\ file-"
                        :cursor-pos 14
                        :completion-index -1
                        :suggestion nil))))

  (it "completion-common-prefix-extension-closed-quoted-token-keeps-closing-quote"
    (let* ((state (input-state
                   :buffer "cat \"my\""
                   :cursor-pos 8))
           (candidates '("my file-a.txt" "my file-b.txt")))
      (multiple-value-bind (new-state extended-p)
          (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                      candidates)
        (expect (null extended-p) :to-be-falsy)
        (is-input-state new-state
                        :buffer "cat \"my file-\""
                        :cursor-pos 13
                        :completion-index -1
                        :suggestion nil))))

  (it "completion-common-prefix-extension-matches-escaped-token"
    (let* ((state (input-state
                   :buffer "cat my\\ "
                   :cursor-pos 8))
           (candidates '("my file-a.txt" "my file-b.txt")))
      (multiple-value-bind (new-state extended-p)
          (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                      candidates)
        (expect (null extended-p) :to-be-falsy)
        (is-input-state new-state
                        :buffer "cat my\\ file-"
                        :cursor-pos 13
                        :completion-index -1
                        :suggestion nil))))

  (it "completion-common-prefix-extension-keeps-unquoted-trailing-quote-literal"
    (let* ((state (input-state
                   :buffer "cat my\""
                   :cursor-pos 7))
           (candidates '("my file-a.txt" "my file-b.txt")))
      (multiple-value-bind (new-state extended-p)
          (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                      candidates)
        (expect extended-p :to-be-null)
        (is-input-state new-state
                        :buffer "cat my\""
                        :cursor-pos 7
                        :completion-index -1
                        :suggestion nil))))

  (it "completion-insertion-text-escapes-by-quote-context"
    "insertion-text adds backslashes for unquoted/double; single handles apostrophes specially."
    (flet ((ins (text &key (ctx nil))
             (nshell.presentation::%completion-insertion-text text :quote-context ctx)))
      (expect "foo" :to-equal (ins "foo"))
      (expect "foo\\ bar" :to-equal (ins "foo bar"))
      (expect "foo\\$bar" :to-equal (ins "foo$bar"))
      (expect "foo bar" :to-equal (ins "foo bar" :ctx :double))
      (expect "foo\\$bar" :to-equal (ins "foo$bar" :ctx :double))
      (expect "foo'\\''bar" :to-equal (ins "foo'bar" :ctx :single))
      (expect "foo bar" :to-equal (ins "foo bar" :ctx :single))))

  (it "completion-unescape-token-strips-backslashes-by-context"
    "unescape-token strips \\ in unquoted/double only for escapable chars."
    (flet ((un (text &key (ctx nil))
             (nshell.presentation::%completion-unescape-token text :quote-context ctx)))
      ;; unquoted: any char after \ has its backslash consumed
      (expect "foo bar" :to-equal (un "foo\\ bar"))
      ;; double-quoted: only double-quote-escapable chars have backslash consumed
      (expect "foo$bar" :to-equal (un "foo\\$bar" :ctx :double))
      ;; backslash + space in double-quote keeps the backslash (space is not special)
      (expect "foo\\ bar" :to-equal (un "foo\\ bar" :ctx :double))
      ;; single-quoted: backslash is never consumed
      (expect "foo\\bar" :to-equal (un "foo\\bar"  :ctx :single))))

  (it "completion-escaped-position-p-counts-preceding-backslashes"
    "escaped-position-p detects an odd number of immediately preceding backslashes."
    (flet ((esc (input pos)
             (nshell.presentation::%completion-escaped-position-p input pos)))
      (expect (esc "abc" 2) :to-be-falsy)
      ;; "a\ " has chars a(0) \(1) space(2); position=2 looks back at index 1 (\) → escaped
      (expect (esc "a\\ " 2) :to-be-truthy)
      ;; "a\\ " has chars a(0) \(1) \(2) space(3); position=3 looks back at 2 backslashes → even → not escaped
      (expect (esc "a\\\\ " 3) :to-be-falsy)))

  (it "completion-quote-context-returns-quote-style-from-token-start"
    "quote-context returns :single/:double at quote char, nil for plain start."
    (flet ((ctx (input start &optional (end 99))
             (nshell.presentation::%completion-quote-context input start end)))
      (expect :single :to-be (ctx "'foo" 0))
      (expect :double :to-be (ctx "\"foo" 0))
      (expect (ctx "foo"  0) :to-be-null)))

  (it "completion-token-bounds-return-slices"
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
      (expect (nshell.presentation::%completion-token-slice-p token-bounds) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::completion-token-slice-p) :to-be-falsy)
      (expect 5 :to-equal (nshell.presentation::completion-token-slice-start token-bounds))
      (expect 14 :to-equal (nshell.presentation::completion-token-slice-end token-bounds))
      (expect (nshell.presentation::%completion-token-slice-p body-bounds) :to-be-truthy)
      (expect 6 :to-equal (nshell.presentation::completion-token-slice-start body-bounds))
      (expect 13 :to-equal (nshell.presentation::completion-token-slice-end body-bounds))
      (expect 5 :to-equal (nshell.presentation::completion-token-slice-start empty-bounds))
      (expect 5 :to-equal (nshell.presentation::completion-token-slice-end empty-bounds))))

  (it "completion-token-context-captures-raw-token-and-quote-state"
    "completion-token-context centralizes bounds, quote state, and raw token extraction."
    (let ((context (nshell.presentation::%completion-token-context "cat 'my\\ " 9)))
      (expect (nshell.presentation::%completion-token-context-p context) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::completion-token-context-p) :to-be-falsy)
      (expect :single :to-be (nshell.presentation::completion-token-context-quote-context context))
      (expect "my\\ " :to-equal (nshell.presentation::completion-token-context-raw-token context))
      (expect 5 :to-equal (nshell.presentation::completion-token-slice-start
                (nshell.presentation::completion-token-context-body-bounds context)))
      (expect 9 :to-equal (nshell.presentation::completion-token-slice-end
                (nshell.presentation::completion-token-context-body-bounds context)))))

  (it "completion-token-raw-accessors-stay-internal"
    "completion token structs expose explicit readers; generated slot readers remain internal."
    (let ((context (nshell.presentation::%completion-token-context "cat foo" 7)))
      (expect (fboundp 'nshell.presentation::%completion-token-context-bounds) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::%completion-token-slice-start) :to-be-truthy)
      (expect (eq (symbol-function
                    'nshell.presentation::completion-token-context-bounds)
                   (symbol-function
                    'nshell.presentation::%completion-token-context-bounds)) :to-be-falsy)
      (expect (eq (symbol-function
                    'nshell.presentation::completion-token-slice-start)
                   (symbol-function
                    'nshell.presentation::%completion-token-slice-start)) :to-be-falsy)
      (expect 4 :to-equal (nshell.presentation::completion-token-slice-start
              (nshell.presentation::completion-token-context-bounds context)))
      (expect 7 :to-equal (nshell.presentation::completion-token-slice-end
              (nshell.presentation::completion-token-context-bounds context)))))

  (it "common-prefix-two-finds-shared-leading-substring"
    "common-prefix-two returns the longest common prefix of two strings."
    (flet ((pre (a b) (nshell.presentation::%common-prefix-two a b)))
      (expect "" :to-equal (pre "" "abc"))
      (expect "" :to-equal (pre "abc" "def"))
      (expect "check" :to-equal (pre "checkout" "check-ignore"))
      (expect "abc" :to-equal (pre "abc" "abc"))))

  (it "completion-escape-character-p-identifies-shell-special-chars"
    "escape-character-p returns true for chars requiring backslash in unquoted context."
    (flet ((esc (ch) (nshell.presentation::%completion-escape-character-p ch)))
      (expect (esc #\Space) :to-be-truthy)
      (expect (esc #\$) :to-be-truthy)
      (expect (esc #\*) :to-be-truthy)
      (expect (esc #\\) :to-be-truthy)
      (expect (esc #\a) :to-be-falsy)
      (expect (esc #\-) :to-be-falsy)))

  (it "completion-quote-delimiters-extracts-open-and-close-quote"
    "quote-delimiters returns the opening and closing quote strings for a token range."
    (flet ((delims (input start end)
             (multiple-value-list
              (nshell.presentation::%completion-quote-delimiters input start end))))
      ;; closed single-quoted token
      (expect '("'" "'") :to-equal (delims "'foo'" 0 5))
      ;; open single-quoted token (no closing quote)
      (expect '("'" "") :to-equal (delims "'foo"  0 4))
      ;; closed double-quoted token
      (expect '("\"" "\"") :to-equal (delims "\"foo\"" 0 5))
      ;; unquoted token
      (expect '("" "") :to-equal (delims "foo" 0 3))))

  (it "completion-splice-with-quote-context-inserts-replacement-at-range"
    "splice-with-quote-context replaces [start,end) with the replacement string."
    (flet ((splice (input start end replacement &key ctx)
             (multiple-value-list
              (nshell.presentation::%completion-splice-with-quote-context
               input start end replacement :quote-context ctx))))
      ;; unquoted: no delimiters added
      (expect '("cat bar" 7) :to-equal (splice "cat foo" 4 7 "bar"))
      ;; single-quoted closed: keep surrounding quotes; cursor = start + 1(quote) + 3(bar) = 8
      (expect '("cat 'bar'" 8) :to-equal (splice "cat 'foo'" 4 9 "bar" :ctx :single)))))
