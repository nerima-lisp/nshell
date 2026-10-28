(in-package #:nshell/test)

(describe "input-state-tests"
  (it "terminal-width-preserves-positive-terminal-columns"
    (with-rebound-function (nshell.infrastructure.acl:get-terminal-size
                            (lambda () (values 24 120)))
      (expect 120 :to-equal (nshell.presentation::terminal-width))))

  (it "terminal-width-falls-back-for-zero-terminal-columns"
    (with-rebound-function (nshell.infrastructure.acl:get-terminal-size
                            (lambda () (values 24 0)))
      (expect 80 :to-equal (nshell.presentation::terminal-width))))

  (it "completion-rendering-highlights-selected-candidate"
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* :truecolor))
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
                        :selected-index 1
                        :theme (nshell.domain.configuration:default-theme)))))
        (expect (search (concatenate 'string
                                      "λ "
                                      (esc-sequence "[38;2;95;175;255m")
                                      "status"
                                      (esc-sequence "[0m"))
                        output)
                :to-be-truthy)
        (expect (search (concatenate 'string
                                      (esc-sequence "[38;2;128;128;128m")
                                      "show working tree status"
                                      (esc-sequence "[0m"))
                        output)
                :to-be-truthy)
        (expect (search (format nil "~C[7mλ stash  store local modifications" #\Esc)
                    output) :to-be-truthy)
        (expect (search (format nil "modifications  ~C[0m" #\Esc)
                    output) :to-be-truthy))))

  (it "completion-rendering-colors-command-text-with-theme"
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* :truecolor))
      (let* ((candidates (list (nshell.domain.completion:make-candidate
                                "ls" :kind :command)))
             (output (capture-standard-output
                       (nshell.presentation:render-completions
                        candidates
                        :terminal-width 80
                        :theme (nshell.domain.configuration:default-theme)))))
        (expect (search (concatenate 'string
                                      (esc-sequence "[38;2;95;175;255m")
                                      "ls"
                                      (esc-sequence "[0m"))
                        output)
                :to-be-truthy))))

  (it "completion-rendering-colors-description-with-theme"
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* :truecolor))
      (let* ((candidates (list (nshell.domain.completion:make-candidate
                                "ls" :kind :command :description "list files")))
             (output (capture-standard-output
                       (nshell.presentation:render-completions
                        candidates
                        :terminal-width 80
                        :theme (nshell.domain.configuration:default-theme)))))
        (expect (search (concatenate 'string
                                      (esc-sequence "[38;2;128;128;128m")
                                      "list files"
                                      (esc-sequence "[0m"))
                        output)
                :to-be-truthy))))

  (it "completion-rendering-appends-trailing-slash-to-directory-candidates"
    (let* ((candidates (list (nshell.domain.completion:make-candidate
                              "beta" :kind :directory)
                             (nshell.domain.completion:make-candidate
                              "gamma/" :kind :directory)))
           (output (capture-standard-output
                     (nshell.presentation:render-completions
                      candidates
                      :terminal-width 80
                      :theme (nshell.domain.configuration:find-theme-preset "mono")))))
      (expect (search "beta/" output) :to-be-truthy)
      (expect (search "gamma//" output) :to-be-falsy)
      (expect (search "gamma/" output) :to-be-truthy)))

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
    (with-rebound-function (nshell.infrastructure.acl:get-terminal-size
                            (lambda () (values 24 80)))
      (expect 1 :to-equal (nshell.presentation::completion-render-line-count
                            '("123456789012345"
                              "abcdefghijklmno"
                              "zzzzzzzzzzzzzzz"
                              "yyyyyyyyyyyyyyy")))))

  (it "completion-rendering-falls-back-when-terminal-size-fails"
    (with-rebound-function (nshell.infrastructure.acl:get-terminal-size
                            (lambda () (error "terminal size unavailable")))
      (expect 1 :to-equal (nshell.presentation::completion-render-line-count
                            '("fallback")))))

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
                      :terminal-width 80
                      :theme (nshell.domain.configuration:find-theme-preset "mono")))))
      (expect (search (concatenate 'string
                                    "/ "
                                    (esc-sequence "[1m")
                                    "directory/"
                                    (esc-sequence "[0m"))
                      output)
              :to-be-truthy)
      (expect (search "- --option" output) :to-be-truthy)
      (expect (search "$  VARIABLE" output) :to-be-truthy)
      (expect (search "· unknown" output) :to-be-truthy)))

  (it "completion-rendering-renders-candidates-beyond-sixty-four"
    (let* ((candidates (loop for index from 1 to 100
                             collect (nshell.domain.completion:make-candidate
                                      (format nil "candidate-~d" index)
                                      :kind :file)))
           (output (capture-standard-output
                     (nshell.presentation:render-completions
                      candidates
                      :terminal-width 80)))
           (expected-lines
             (nshell.presentation::completion-render-line-count
              candidates
              :terminal-width 80)))
      (expect (search "candidate-100" output) :to-be-truthy)
      (expect (search "… and " output) :to-be-falsy)
      (expect expected-lines :to-equal
              (let ((*standard-output* (make-string-output-stream)))
                (nshell.presentation:render-completions
                 candidates
                 :terminal-width 80)))))
  (it "completion-rendering-bounds-rows-and-keeps-selection-visible"
    (let* ((candidates (loop for index from 1 to 100
                             collect (nshell.domain.completion:make-candidate
                                      (format nil "candidate-~3,'0d" index)
                                      :kind :file)))
           (max-rows 5)
           (output (capture-standard-output
                     (nshell.presentation:render-completions
                      candidates
                      :selected-index 99
                      :terminal-width 80
                      :max-rows max-rows
                      :footer "100/100"))))
      (expect 5 :to-equal
              (nshell.presentation::completion-render-line-count
               candidates
               :terminal-width 80
               :max-rows max-rows
               :footer-p t))
      (expect 6 :to-equal
              (count #\Newline output))
      (expect (search "candidate-085" output) :to-be-truthy)
      (expect (search "candidate-100" output) :to-be-truthy)
      (expect (search "candidate-001" output) :to-be-falsy)
      (expect (search "100/100" output) :to-be-truthy)))
  (it "completion-rendering-keeps-candidate-row-when-max-rows-is-one"
    (let* ((candidates (list (nshell.domain.completion:make-candidate
                              "alpha"
                              :kind :file)))
           (rendered-lines nil)
           (output
             (with-output-to-string (stream)
               (let ((*standard-output* stream))
                 (setf rendered-lines
                       (nshell.presentation:render-completions
                        candidates
                        :terminal-width 80
                        :max-rows 1
                        :footer "1/1"))))))
      (expect 1 :to-equal
              (nshell.presentation::completion-render-line-count
               candidates
               :terminal-width 80
               :max-rows 1
               :footer-p t))
      (expect 1 :to-equal rendered-lines)
      (expect (search "alpha" output) :to-be-truthy)
      (expect (search "1/1" output) :to-be-falsy)))
  (it "completion-rendering-keeps-fitting-list-nonmodal-on-24-row-terminal"
    (with-repl-test-state
      (let* ((candidates (loop for index from 1 to 30
                               collect (nshell.domain.completion:make-candidate
                                        (format nil "candidate-~3,'0d" index)
                                        :kind :file)))
             (nshell.presentation::*input-state*
               (nshell.presentation:make-input-state
                :buffer "echo "
                :last-candidates candidates))
             (nshell.presentation::*prompt-rendered-lines* 1)
             (nshell.presentation::*prompt-rendered-cursor-row* 0)
             (output
               (with-fixed-terminal-size (24 80)
                 (capture-standard-output
                   (nshell.presentation::%render-current-completion-results)))))
        (expect nil :to-equal
                (nshell.presentation::input-state-completion-pager
                 nshell.presentation::*input-state*))
        (expect (search "candidate-030" output) :to-be-truthy)
        (expect (search "arrows move" output) :to-be-falsy)
        (expect (<= nshell.presentation::*completion-rendered-lines* 23)
                :to-be-truthy))))
  (it "completion-event-pages-large-results-before-counting-rows"
    (with-repl-test-state
      (let* ((base-state
               (nshell.presentation:make-input-state :buffer "complete "))
             (candidates (loop repeat 20000 collect :candidate))
             (line-count-calls 0))
        (setf nshell.presentation::*input-state* base-state)
        (with-temporary-functions
            (('nshell.presentation::%completion-session-valid-p
              (lambda (state)
                (declare (ignore state))
                nil))
             ('nshell.presentation::%refresh-completion-session-state
              (lambda (state)
                (declare (ignore state))
                (values base-state candidates)))
             ('nshell.presentation::%completion-pager-row-budget
              (lambda () 10))
             ('nshell.presentation::terminal-width
              (lambda () 80))
             ('nshell.presentation::completion-render-line-count
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (incf line-count-calls)
                1)))
          (nshell.presentation::%process-complete-output-event)
          (expect 0 :to-equal line-count-calls)
          (expect (nshell.presentation::input-state-completion-pager
                   nshell.presentation::*input-state*)
                  :to-be-truthy)))))
  (it "completion-rendering-previews-first-file-without-an-index"
    (host-kit:with-temporary-directory (directory)
      (let* ((path (merge-pathnames "preview.txt" directory))
             (candidates
               (list (nshell.domain.completion:make-candidate
                      (namestring path) :kind :file)
                     (nshell.domain.completion:make-candidate
                      "later-command" :kind :command))))
        (host-kit:write-file-string
         (format nil "first body~%second body~%") path)
        (with-repl-test-state
          (let* ((nshell.presentation::*input-state*
                   (nshell.presentation:make-input-state
                    :buffer "preview " :last-candidates candidates))
                 (nshell.presentation::*prompt-rendered-lines* 1)
                 (nshell.presentation::*prompt-rendered-cursor-row* 0)
                 (nshell.infrastructure.terminal:*terminal-color-depth* :truecolor)
                 (output
                   (with-fixed-terminal-size (24 80)
                     (capture-standard-output
                       (nshell.presentation::%render-current-completion-results)))))
            (expect (search "first body" output) :to-be-truthy)
            (expect (search "second body" output) :to-be-truthy)
            (expect (search (format nil "~C[7m∙ " #\Esc) output) :to-be-truthy)
            (expect (>= nshell.presentation::*completion-rendered-lines* 3) :to-be-truthy))))))
  (it "completion-rendering-includes-preview-lines-in-pager-budget"
    (host-kit:with-temporary-directory (directory)
      (let* ((path (merge-pathnames "preview.txt" directory))
             (long-text (make-string 72 :initial-element #\x))
             (candidates
               (cons (nshell.domain.completion:make-candidate
                      (namestring path) :kind :file)
                     (loop for index from 1 to 5
                           collect
                           (nshell.domain.completion:make-candidate
                            (format nil "candidate-~d-~a" index long-text)
                            :kind :command))))
             (grid-lines
               (nshell.presentation::completion-render-line-count
                candidates :terminal-width 80))
             (row-budget nil))
        (host-kit:write-file-string
         (format nil "preview-one~%preview-two") path)
        (with-repl-test-state
          (let* ((nshell.presentation::*input-state*
                   (nshell.presentation:make-input-state
                    :buffer "preview " :last-candidates candidates))
                 (nshell.presentation::*prompt-rendered-lines* 1)
                 (nshell.presentation::*prompt-rendered-cursor-row* 0)
                 (output
                   (with-fixed-terminal-size (8 80)
                     (setf row-budget
                           (nshell.presentation::%completion-pager-row-budget))
                     (expect (<= grid-lines row-budget) :to-be-truthy)
                     (expect (> (+ grid-lines 2) row-budget) :to-be-truthy)
                     (capture-standard-output
                       (nshell.presentation::%render-current-completion-results)))))
            (expect (nshell.presentation::input-state-completion-pager
                     nshell.presentation::*input-state*)
                    :to-be-truthy)
            (expect (search "preview-one" output) :to-be-truthy)
            (expect (search "preview-two" output) :to-be-truthy)
            (expect (search "arrows move" output) :to-be-truthy)
            (expect (<= nshell.presentation::*completion-rendered-lines*
                        row-budget)
                    :to-be-truthy))))))
  (it "file-preview-formatting-bounds-lines-and-width"
    (let* ((bytes
             (sb-ext:string-to-octets
              (format nil "alpha~%bravo~%charlie") :external-format :utf-8))
           (lines
             (nshell.presentation::format-file-preview-lines
              bytes :max-lines 2 :max-width 4)))
      (expect 2 :to-equal (length lines))
      (expect (every (lambda (line)
                       (<= (nshell.presentation::%string-visible-width line) 4))
                     lines) :to-be-truthy)))
  (it "file-preview-formatting-escapes-bidi-and-line-separator-controls"
    (let* ((text
             (coerce
              (list #\A (code-char #x202e)
                    #\B (code-char #x2066)
                    #\C (code-char #x2028)
                    #\D (code-char #x2029)
                    #\E)
              (quote string)))
           (lines
             (nshell.presentation::format-file-preview-lines
              (sb-ext:string-to-octets text :external-format :utf-8)
              :max-lines 3
              :max-width 80))
           (line (first lines)))
      (expect 1 :to-equal (length lines))
      (expect (loop for escape in (list "\\u202e"
                                        "\\u2066"
                                        "\\u2028"
                                        "\\u2029")
                    always (search escape line))
              :to-be-truthy)
      (expect (loop for code in (list #x202e #x2066 #x2028 #x2029)
                    always (null (position (code-char code) line)))
              :to-be-truthy)))
  (it "file-preview-formatting-escapes-controls-and-rejects-invalid-utf8"
    (let* ((control-bytes
             (make-array
              9 :element-type (quote (unsigned-byte 8))
              :initial-contents (list #x41 #x1b #x42 #x09 #x43 #x7f #x44 #xc2 #x85)))
           (lines
             (nshell.presentation::format-file-preview-lines
              control-bytes :max-lines 3 :max-width 80))
           (line (first lines))
           (nul-bytes
             (make-array
              3 :element-type (quote (unsigned-byte 8))
              :initial-contents (list #x41 #x00 #x42)))
           (invalid-utf8
             (make-array
              2 :element-type (quote (unsigned-byte 8))
              :initial-contents (list #xc3 #x28)))
           (invalid-utf8-cases
             (list
              invalid-utf8
              (make-array
               2 :element-type (quote (unsigned-byte 8))
               :initial-contents (list #xc0 #xaf))
              (make-array
               3 :element-type (quote (unsigned-byte 8))
               :initial-contents (list #xed #xa0 #x80))
              (make-array
               2 :element-type (quote (unsigned-byte 8))
               :initial-contents (list #xe2 #x82))
              (let ((bytes
                      (make-array
                       0 :element-type (quote (unsigned-byte 8))
                       :adjustable t :fill-pointer 0)))
                (loop repeat 4095 do
                  (vector-push-extend #x61 bytes))
                (vector-push-extend #xc3 bytes)
                bytes))))
      (expect 1 :to-equal (length lines))
      (expect (search "\\x1b" line) :to-be-truthy)
      (expect nil :to-equal (position #\Tab line))
      (expect (loop for character across line
                    for code = (char-code character)
                    always (and (>= code #x20)
                                (not (<= #x7f code #x9f)))) :to-be-truthy)
      (expect (let ((before-tab (position #\B line))
                    (after-tab (position #\C line)))
                (and before-tab after-tab
                     (> after-tab (1+ before-tab))
                     (loop for index from (1+ before-tab) below after-tab
                           always (char= (char line index) #\Space))))
              :to-be-truthy)
      (expect nil :to-equal
              (nshell.presentation::format-file-preview-lines
               nul-bytes :max-lines 3 :max-width 80))
      (expect
       (loop for bytes in invalid-utf8-cases
             always
             (null
              (nshell.presentation::format-file-preview-lines
               bytes :max-lines 3 :max-width 80)))
       :to-be-truthy)))

  (it "completion-rendering-skips-preview-for-command-and-directory"
    (host-kit:with-temporary-directory (directory)
      (let ((path (merge-pathnames "preview.txt" directory)))
        (host-kit:write-file-string "preview-only-body" path)
        (loop for kind in (list :command :directory)
              do (with-repl-test-state
                   (let* ((nshell.presentation::*input-state*
                            (nshell.presentation:make-input-state
                             :buffer "preview "
                             :completion-index 0
                             :last-candidates
                             (list (nshell.domain.completion:make-candidate
                                    (namestring path) :kind kind))))
                          (nshell.presentation::*prompt-rendered-lines* 1)
                          (nshell.presentation::*prompt-rendered-cursor-row* 0)
                          (output
                            (with-fixed-terminal-size (24 80)
                              (capture-standard-output
                                (nshell.presentation::%render-current-completion-results)))))
                     (expect nil :to-equal
                             (search "preview-only-body" output))))))))

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
  (it "completion-rendering-truncates-wide-candidates-by-display-width"
    (let* ((wide-text (make-string 20 :initial-element #\界))
           (candidates (list (nshell.domain.completion:make-candidate
                              wide-text
                              :kind :file)))
           (output (capture-standard-output
                     (nshell.presentation:render-completions
                      candidates
                      :terminal-width 12
                      :max-rows 2
                      :footer "status")))
           (line-end (position #\Newline output :start 1))
           (candidate-line (subseq output 1 line-end)))
      (expect 2 :to-equal
              (let ((*standard-output* (make-string-output-stream)))
                (nshell.presentation:render-completions
                 candidates
                 :terminal-width 12
                 :max-rows 2
                 :footer "status")))
      (expect 12 :to-equal
              (nshell.presentation::%string-visible-width candidate-line))
      (expect (search "∙ 界界界界" candidate-line) :to-be-truthy)
      (expect (search "界界界界界" candidate-line) :to-be-falsy)))

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

  (it "completion-common-prefix-extension-preserves-suffix-and-completes-midword"
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
                        :suggestion nil)))
    (let* ((buffer "cat nested/sexp-pathZZ")
           (typed-prefix "cat nested/sexp-path")
           (state (input-state
                   :buffer buffer
                   :cursor-pos (length typed-prefix)))
           (candidates '("nested/sexp-path.txt")))
      (multiple-value-bind (new-state extended-p)
          (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                      candidates)
        (expect extended-p :to-be-truthy)
        (is-input-state new-state
                        :buffer "cat nested/sexp-path.txt"
                        :cursor-pos (length "cat nested/sexp-path.txt")
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
    "insertion text preserves filename characters in each quote context."
    (flet ((ins (text &key (ctx nil))
             (nshell.presentation::%completion-insertion-text text :quote-context ctx))
           (word-value (input)
             (with-complete-command-line (result ast input)
               (declare (ignore result))
               (first (nshell.domain.parsing:command-node-arg-values ast)))))
      (expect "foo" :to-equal (ins "foo"))
      (expect "foo\\ bar" :to-equal (ins "foo bar"))
      (expect "foo\\$bar" :to-equal (ins "foo$bar"))
      (expect "foo bar" :to-equal (ins "foo bar" :ctx :double))
      (expect "foo\\$bar" :to-equal (ins "foo$bar" :ctx :double))
      (expect "foo'\\''bar" :to-equal (ins "foo'bar" :ctx :single))
      (expect "foo bar" :to-equal (ins "foo bar" :ctx :single))
      (expect (format nil "'foo~cbar'" #\Newline)
              :to-equal (ins (format nil "foo~cbar" #\Newline)))
      (expect (format nil "foo~cbar" #\Newline)
              :to-equal (ins (format nil "foo~cbar" #\Newline) :ctx :double))
      (expect (format nil "foo~cbar" #\Newline)
              :to-equal (ins (format nil "foo~cbar" #\Newline) :ctx :single))
      (let* ((control-text (format nil "tab~creturn~cend" #\Tab #\Return))
             (escaped-control-text
               (format nil "tab\\~creturn\\~cend" #\Tab #\Return))
             (linefeed-text (format nil "line'!~cfeed" #\Newline))
             (linefeed-insertion (ins linefeed-text))
             (input (concatenate 'string "echo " linefeed-insertion))
             (context (nshell.presentation::%completion-token-context
                       input (length input)))
             (double-linefeed (format nil "double~cquoted" #\Newline))
             (double-insertion (ins double-linefeed :ctx :double)))
        (expect escaped-control-text :to-equal (ins control-text))
        (expect control-text :to-equal (ins control-text :ctx :double))
        (expect control-text :to-equal (word-value
                                        (concatenate 'string
                                                     "echo "
                                                     escaped-control-text)))
        (expect linefeed-text :to-equal (word-value input))
        (expect linefeed-text
                :to-equal
                (nshell.presentation::completion-token-context-raw-token
                 context))
        (expect double-linefeed
                :to-equal
                (word-value (concatenate 'string
                                         "echo \""
                                         double-insertion
                                         "\""))))))

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

(describe "completion-variable-insertion-tests"
  (it "variable-candidates-insert-their-sigil-unescaped"
    "A $VAR candidate must stay an expansion after insertion, not a literal."
    (let ((candidate (nshell.domain.completion:make-candidate
                      "$HOME" :kind :variable :description "/home/tester")))
      (expect "echo $HOME"
              :to-equal
              (nshell.presentation:apply-completion "echo $HO" candidate))))

  (it "non-variable-candidates-keep-shell-escaping"
    (let ((candidate (nshell.domain.completion:make-candidate
                      "my file.txt" :kind :file)))
      (expect "cat my\\ file.txt"
              :to-equal
              (nshell.presentation:apply-completion "cat my" candidate))))

  (it "variable-common-prefix-extension-keeps-the-sigil-unescaped"
    (let* ((state (input-state :buffer "echo $X" :cursor-pos 7))
           (candidates (list (nshell.domain.completion:make-candidate
                              "$XDG_CACHE" :kind :variable)
                             (nshell.domain.completion:make-candidate
                              "$XDG_CONFIG" :kind :variable))))
      (multiple-value-bind (new-state extended-p)
          (nshell.presentation::maybe-extend-completion-common-prefix state candidates)
        (expect extended-p :to-be-truthy)
        (expect "echo $XDG_C" :to-equal (nshell.presentation:input-state-buffer new-state)))))
  (it "file-candidates-preserve-variable-directory-prefix-and-escape-suffix"
    (dolist (case '(("cat $TARGET/fi" "$TARGET/file name.txt"
                    "cat $TARGET/file\\ name.txt")
                   ("cat \${TARGET}/fi" "\${TARGET}/file name.txt"
                    "cat \${TARGET}/file\\ name.txt")))
      (destructuring-bind (input candidate-text expected) case
        (let ((candidate
                (nshell.domain.completion:make-candidate
                 candidate-text :kind :file)))
          (expect expected :to-equal
                  (nshell.presentation:apply-completion input candidate)))))
    (let* ((state (input-state
                   :buffer "cat $TARGET/"
                   :cursor-pos (length "cat $TARGET/")))
           (candidates
             (list (nshell.domain.completion:make-candidate
                    "$TARGET/file-a" :kind :file)
                   (nshell.domain.completion:make-candidate
                    "$TARGET/file-b" :kind :file))))
      (multiple-value-bind (new-state extended-p)
          (nshell.presentation::maybe-extend-completion-common-prefix
           state candidates)
        (expect extended-p :to-be-truthy)
        (expect "cat $TARGET/file-"
                :to-equal
                (nshell.presentation:input-state-buffer new-state))))))
