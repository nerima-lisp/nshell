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
