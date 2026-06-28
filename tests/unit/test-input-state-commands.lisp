(in-package #:nshell/test)

(in-suite input-state-tests)

(test input-state-alt-s-toggles-sudo-prefix
  (let ((state (completion-session-state
                :buffer "apt update"
                :cursor-pos 3
                :completion-index 2
                :suggestion " && apt upgrade")))
    (with-expected-input-state-reduction (prefixed prefixed-output)
        state
        (reduce-once state :alt-s)
        :suggest-update
        (:buffer "sudo apt update"
         :cursor-pos 8
         :completion-index -1
         :suggestion nil)
      (with-expected-input-state-reduction (unprefixed unprefixed-output)
          prefixed
          (reduce-once prefixed :alt-s)
          :suggest-update
          (:buffer "apt update" :cursor-pos 3)))))

(test input-state-alt-s-removes-bare-sudo-prefix
  (let ((state (input-state
                :buffer "sudo"
                :cursor-pos 4)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :alt-s)
        :suggest-update
        (:buffer "" :cursor-pos 0))))

(test input-state-ctrl-p-and-ctrl-n-request-history-navigation
  (let ((state (completion-session-state
                :buffer "git"
                :cursor-pos 2
                :completion-index 1
                :suggestion " status")))
    (with-expected-input-state-reduction (prev-state prev-output)
        state
        (reduce-once state :ctrl-p)
        :history-prev
        (:buffer "git"
         :cursor-pos 2
         :completion-index 1
         :suggestion " status"))
    (with-expected-input-state-reduction (next-state next-output)
        state
        (reduce-once state :ctrl-n)
        :history-next
        (:buffer "git" :cursor-pos 2))))

(test input-state-alt-dot-requests-last-history-argument
  (let ((state (completion-session-state
                :buffer "echo "
                :cursor-pos 5
                :completion-index 1
                :suggestion "tail")))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :alt-dot)
        :insert-last-argument
        (:buffer "echo "
         :cursor-pos 5
         :completion-index 1
         :suggestion "tail"))))

(test input-state-enter-on-text-returns-execute
  (let ((state (input-state :buffer "echo hi" :cursor-pos 7)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :enter)
        :execute
        (:buffer "echo hi"))))

(test input-state-enter-accepts-suggestion-at-eol-before-execute
  (let ((state (completion-session-state
                :buffer "echo"
                :cursor-pos 4
                :completion-index 1
                :suggestion " hello")))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :enter)
        :execute
        (:buffer "echo hello"
         :cursor-pos 10
         :completion-index -1
         :suggestion nil))))

(test input-state-enter-expands-abbreviation-before-execute
  (let ((state (completion-session-state
                :buffer "gco"
                :cursor-pos 3
                :completion-index 2
                :suggestion " ignored"
                :abbreviation-expander
                (lambda (token)
                  (when (string= token "gco")
                    "git checkout")))))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :enter)
        :execute
        (:buffer "git checkout ignored"
         :cursor-pos 20
         :completion-index -1
         :suggestion nil))))

(test input-state-inserts-continuation-newline-at-cursor
  (let ((state (input-state :buffer "echo \"hi\"" :cursor-pos 5)))
    (with-expected-input-state-reduction (new-state output)
        state
        (nshell.presentation:insert-newline-at-cursor state)
        :suggest-update
        (:buffer (format nil "echo ~%\"hi\"")
         :cursor-pos 6))))

(test input-state-inserts-indented-continuation-newline-at-cursor
  (let ((state (input-state :buffer "echo |" :cursor-pos 6)))
    (with-expected-input-state-reduction (new-state output)
        state
        (nshell.presentation:insert-newline-at-cursor state :indent 2)
        :suggest-update
        (:buffer (format nil "echo |~%  ")
         :cursor-pos 9))))

(test input-state-ctrl-d-empty-quits-but-non-empty-deletes
  (multiple-value-bind (empty-state empty-output)
      (reduce-once (input-state) :ctrl-d)
    (declare (ignore empty-state))
    (is (eq :quit empty-output)))
  (let ((state (input-state :buffer "ab" :cursor-pos 1)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :ctrl-d)
        :suggest-update
        (:buffer "a" :cursor-pos 1))))

(test input-state-backspace-removes-character-before-cursor
  (let ((state (input-state :buffer "abc" :cursor-pos 2)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :backspace)
        :suggest-update
        (:buffer "ac" :cursor-pos 1))))

(test input-state-ctrl-t-transposes-chars-around-cursor
  (let ((state (completion-session-state
                :buffer "abcd"
                :cursor-pos 2
                :completion-index 3
                :suggestion " ignored")))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :ctrl-t)
        :suggest-update
        (:buffer "acbd"
         :cursor-pos 3
         :completion-index -1
         :suggestion nil))))

(test input-state-ctrl-t-at-eol-transposes-last-two-chars
  (let ((state (input-state
                :buffer "abcd"
                :cursor-pos 4)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :ctrl-t)
        :suggest-update
        (:buffer "abdc" :cursor-pos 4))))

(test input-state-ctrl-t-noops-without-left-char
  (with-expected-noop-input-state-reductions (new-state output)
      :ctrl-t
      (list (input-state :buffer "" :cursor-pos 0)
            (input-state :buffer "a" :cursor-pos 1)
            (input-state :buffer "ab" :cursor-pos 0))))

(test input-state-alt-t-transposes-last-two-words-at-eol
  (let ((state (completion-session-state
                :buffer "echo one two"
                :cursor-pos 12
                :completion-index 3
                :suggestion " ignored")))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :alt-t)
        :suggest-update
        (:buffer "echo two one"
         :cursor-pos 12
         :completion-index -1
         :suggestion nil))))

(test input-state-alt-t-transposes-word-at-cursor-with-previous-word
  (let ((state (input-state
                :buffer "echo one two"
                :cursor-pos 9)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :alt-t)
        :suggest-update
        (:buffer "echo two one" :cursor-pos 12))))

(test input-state-alt-t-treats-escaped-space-as-token-content
  (let ((state (input-state
                :buffer "echo my\\ file.txt tail"
                :cursor-pos 22)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :alt-t)
        :suggest-update
        (:buffer "echo tail my\\ file.txt" :cursor-pos 22))))

(test input-state-alt-t-treats-quoted-space-as-token-content
  (let ((state (input-state
                :buffer "echo \"hello world\" tail"
                :cursor-pos 23)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :alt-t)
        :suggest-update
        (:buffer "echo tail \"hello world\"" :cursor-pos 23))))

(test input-state-alt-t-treats-shell-operators-as-word-boundaries
  (let ((state (input-state
                :buffer "echo one|two"
                :cursor-pos 12)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :alt-t)
        :suggest-update
        (:buffer "echo two|one" :cursor-pos 12))))

(test input-state-alt-t-noops-without-two-words
  (with-expected-noop-input-state-reductions (new-state output)
      :alt-t
      (list (input-state :buffer "" :cursor-pos 0)
            (input-state :buffer "one" :cursor-pos 3)
            (input-state :buffer "one " :cursor-pos 4))))

(test input-state-alt-t-participates-in-undo
  (let ((state (input-state :buffer "echo one two" :cursor-pos 12)))
    (with-reduced-input-state (transposed) (reduce-once state :alt-t)
      (with-reduced-input-state (undone output) (reduce-once transposed :ctrl-underscore)
        (is-input-state undone :buffer "echo one two" :cursor-pos 12)
        (is (eq :suggest-update output))))))

(test input-state-alt-u-upcases-word-at-cursor
  (let ((state (completion-session-state
                :buffer "echo hello world"
                :cursor-pos 5
                :completion-index 2
                :suggestion " ignored")))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :alt-u)
        :suggest-update
        (:buffer "echo HELLO world"
         :cursor-pos 10
         :completion-index -1
         :suggestion nil))))

(test input-state-alt-l-downcases-next-word-after-cursor
  (let ((state (input-state
                :buffer "echo   WORLD tail"
                :cursor-pos 4)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :alt-l)
        :suggest-update
        (:buffer "echo   world tail" :cursor-pos 12))))

(test input-state-alt-c-capitalizes-quoted-token
  (let ((state (input-state
                :buffer "echo \"HELLO world\" tail"
                :cursor-pos 5)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :alt-c)
        :suggest-update
        (:buffer "echo \"Hello world\" tail" :cursor-pos 18))))

(test input-state-alt-case-treats-shell-operators-as-word-boundaries
  (let ((state (input-state
                :buffer "echo one|two"
                :cursor-pos 8)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :alt-u)
        :suggest-update
        (:buffer "echo one|TWO" :cursor-pos 12))))

(test input-state-alt-case-noops-without-word
  (with-expected-noop-input-state-reductions (new-state output)
      :alt-u
      (list (input-state :buffer "" :cursor-pos 0)
            (input-state :buffer "   |" :cursor-pos 4))))

(test input-state-alt-u-participates-in-undo
  (let ((state (input-state :buffer "echo hello" :cursor-pos 5)))
    (with-reduced-input-state (upcased) (reduce-once state :alt-u)
      (with-reduced-input-state (undone output) (reduce-once upcased :ctrl-underscore)
        (is-input-state undone :buffer "echo hello" :cursor-pos 5)
        (is (eq :suggest-update output))))))

(test input-state-ctrl-underscore-undoes-last-edit
  (let ((state (apply-key-events-to-input-state
                (input-state)
                (list (input-key-event :char #\a)
                      (input-key-event :char #\b)
                      (input-key-event :char #\c)))))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :ctrl-underscore)
        :suggest-update
        (:buffer "ab" :cursor-pos 2))))

(test input-state-alt-r-redoes-undone-edit
  (let ((state (apply-key-events-to-input-state
                (input-state)
                (list (input-key-event :char #\a)
                      (input-key-event :char #\b)
                      (input-key-event :char #\c)))))
    (with-reduced-input-state (undone) (reduce-once state :ctrl-underscore)
      (with-reduced-input-state (redone output) (reduce-once undone :alt-r)
        (is-input-state redone :buffer "abc" :cursor-pos 3)
        (is (eq :suggest-update output))))))

(test input-state-navigation-is-not-an-undo-step
  (let ((typed (apply-key-events-to-input-state
                (input-state)
                (list (input-key-event :char #\a)
                      (input-key-event :char #\b)
                      (input-key-event :char #\c)))))
    (with-reduced-input-state (moved) (reduce-once typed :ctrl-b)
      (with-reduced-input-state (edited) (reduce-once moved :char #\X)
        (with-reduced-input-state (undone output) (reduce-once edited :ctrl-underscore)
          (is-input-state undone :buffer "abc" :cursor-pos 2)
          (is (eq :suggest-update output)))))))

(test input-state-new-edit-clears-redo-stack
  (let ((state (apply-key-events-to-input-state
                (input-state)
                (list (input-key-event :char #\a)
                      (input-key-event :char #\b)))))
    (with-reduced-input-state (undone) (reduce-once state :ctrl-underscore)
      (with-reduced-input-state (edited) (reduce-once undone :char #\X)
        (with-reduced-input-state (redone output) (reduce-once edited :alt-r)
          (is-input-state redone :buffer "aX" :cursor-pos 2)
          (is (eq :none output)))))))

(test input-state-kill-and-yank-participate-in-undo-redo
  (let ((state (input-state :buffer "echo one two" :cursor-pos 12)))
    (with-reduced-input-state (killed) (reduce-once state :ctrl-w)
      (with-reduced-input-state (undone undo-output) (reduce-once killed :ctrl-underscore)
        (is-input-state undone :buffer "echo one two" :cursor-pos 12)
        (is (eq :suggest-update undo-output))
        (with-reduced-input-state (redone redo-output) (reduce-once undone :alt-r)
          (is-input-state redone :buffer "echo one " :cursor-pos 9)
          (is (eq :suggest-update redo-output)))))))
