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

(test input-state-sudo-prefix-operation-classifies-buffer
  (let ((insert (nshell.presentation::sudo-prefix-operation-for-buffer "apt update"))
        (remove-prefix (nshell.presentation::sudo-prefix-operation-for-buffer
                        "sudo apt update"))
        (remove-command (nshell.presentation::sudo-prefix-operation-for-buffer
                         "sudo")))
    (is (nshell.presentation::sudo-prefix-operation-p insert))
    (is (eq :insert-prefix
            (nshell.presentation::sudo-prefix-operation-kind insert)))
    (is (eq :remove-prefix
            (nshell.presentation::sudo-prefix-operation-kind remove-prefix)))
    (is (eq :remove-command
            (nshell.presentation::sudo-prefix-operation-kind remove-command)))))

(test input-state-sudo-prefix-operation-raw-accessors-stay-internal
  "sudo-prefix-operation exposes explicit readers; generated slot readers stay internal."
  (let ((operation (nshell.presentation::sudo-prefix-operation-for-buffer "apt update")))
    (is (fboundp 'nshell.presentation::%sudo-prefix-operation-kind))
    (is (not (eq (symbol-function
                  'nshell.presentation::sudo-prefix-operation-kind)
                 (symbol-function
                  'nshell.presentation::%sudo-prefix-operation-kind))))
    (is (not (fboundp 'nshell.presentation::make-sudo-prefix-operation)))
    (is (not (fboundp 'nshell.presentation::sudo-prefix-edit-for-buffer)))
    (is (eq :insert-prefix
            (nshell.presentation::sudo-prefix-operation-kind operation)))))

(test input-state-sudo-prefix-edit-projects-buffer-and-cursor
  (labels ((edit-for (buffer)
             (nshell.presentation::sudo-prefix-edit-for-operation
              (nshell.presentation::sudo-prefix-operation-for-buffer buffer))))
    (let ((edit (edit-for "apt update")))
      (is (nshell.presentation::sudo-prefix-edit-p edit))
      (is (nshell.presentation::sudo-prefix-plan-p
           (nshell.presentation::sudo-prefix-edit-plan edit)))
      (is (not (fboundp 'nshell.presentation::make-sudo-prefix-edit)))
      (is (not (fboundp 'nshell.presentation::make-sudo-prefix-plan)))
      (is (not (fboundp 'nshell.presentation::sudo-prefix-edit-splice)))
      (is (not (fboundp 'nshell.presentation::sudo-prefix-edit-cursor-delta)))
      (is (string= "sudo apt update"
                   (nshell.presentation::sudo-prefix-edit-buffer edit
                                                                 "apt update")))
      (is (= 8 (nshell.presentation::sudo-prefix-edit-cursor-pos edit 3))))
    (let ((edit (edit-for "sudo apt update")))
      (is (string= "apt update"
                   (nshell.presentation::sudo-prefix-edit-buffer edit
                                                                 "sudo apt update")))
      (is (= 0 (nshell.presentation::sudo-prefix-edit-cursor-pos edit 3))))
    (let ((edit (edit-for "sudo")))
      (is (string= ""
                   (nshell.presentation::sudo-prefix-edit-buffer edit "sudo")))
      (is (= 0 (nshell.presentation::sudo-prefix-edit-cursor-pos edit 4))))))

(test input-state-dispatch-action-classifies-key-events
  (labels ((action-for (type &optional char data)
             (nshell.presentation::input-dispatch-action-for-key-event
              (input-key-event type char nil data))))
    (let ((char-action (action-for :char #\x))
          (next-history-action (action-for :ctrl-n))
          (eol-action (action-for :ctrl-e))
          (paste-action (action-for :paste nil "abc"))
          (unknown-action (action-for :unknown)))
      (is (nshell.presentation::%input-dispatch-action-p char-action))
      (is (eq :insert-char
              (nshell.presentation::input-dispatch-action-kind char-action)))
      (is (char= #\x
                 (nshell.presentation::input-dispatch-action-value
                  char-action)))
      (is (eq :emit
              (nshell.presentation::input-dispatch-action-kind
               next-history-action)))
      (is (eq :history-next
              (nshell.presentation::input-dispatch-action-value
               next-history-action)))
      (is (eq :move-eol-or-accept-suggestion
              (nshell.presentation::input-dispatch-action-kind eol-action)))
      (is (eq :paste
              (nshell.presentation::input-dispatch-action-kind paste-action)))
      (is (eq :none
              (nshell.presentation::input-dispatch-action-kind
               unknown-action))))))

(test input-state-dispatch-action-raw-accessors-stay-internal
  "input-dispatch-action exposes explicit readers; generated slots and predicates stay internal."
  (let ((action (nshell.presentation::input-dispatch-action-for-key-event
                 (input-key-event :ctrl-l))))
    (is (not (fboundp 'nshell.presentation::input-dispatch-action-p)))
    (is (fboundp 'nshell.presentation::%input-dispatch-action-kind))
    (is (not (eq (symbol-function
                  'nshell.presentation::input-dispatch-action-kind)
                 (symbol-function
                  'nshell.presentation::%input-dispatch-action-kind))))
    (is (not (fboundp 'nshell.presentation::make-input-dispatch-action)))
    (is (eq :emit
            (nshell.presentation::input-dispatch-action-kind action)))
    (is (eq :clear-screen
            (nshell.presentation::input-dispatch-action-value action)))))

(test input-state-dispatch-transition-commits-action-output
  "Dispatch actions project to transition values before returning reducer values."
  (let* ((state (completion-session-state
                 :buffer "git"
                 :cursor-pos 2
                 :completion-index 1
                 :suggestion " status"))
         (action (nshell.presentation::input-dispatch-action-for-key-event
                  (input-key-event :ctrl-l)))
         (transition (nshell.presentation::input-dispatch-transition-for-action
                      state
                      action)))
    (is (nshell.presentation::%input-dispatch-transition-p transition))
    (is (not (fboundp 'nshell.presentation::input-dispatch-transition-p)))
    (is (not (fboundp 'nshell.presentation::make-input-dispatch-transition)))
    (is (fboundp 'nshell.presentation::%input-dispatch-transition-state))
    (is (eq :clear-screen
            (nshell.presentation::input-dispatch-transition-output
             transition)))
    (with-expected-input-state-reduction (new-state output)
        state
        (nshell.presentation::commit-input-dispatch-transition transition)
        :clear-screen
        (:buffer "git"
         :cursor-pos 2
         :completion-index 1
         :suggestion " status"))))

(test input-state-dispatch-action-applies-output-actions-without-state-change
  (let* ((state (completion-session-state
                 :buffer "git"
                 :cursor-pos 2
                 :completion-index 1
                 :suggestion " status"))
         (action (nshell.presentation::input-dispatch-action-for-key-event
                  (input-key-event :ctrl-l))))
    (with-expected-input-state-reduction (new-state output)
        state
        (nshell.presentation::reduce-insert-input-state-action state action)
        :clear-screen
        (:buffer "git"
         :cursor-pos 2
         :completion-index 1
         :suggestion " status"))))

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

(test input-state-char-transposition-projects-buffer-and-cursor
  (let ((transposition (nshell.presentation::char-transposition-at-cursor
                        "abcd" 2)))
    (is (nshell.presentation::char-transposition-p transposition))
    (is (nshell.presentation::char-transposition-plan-p
         (nshell.presentation::char-transposition-plan transposition)))
    (is (not (fboundp 'nshell.presentation::make-char-transposition)))
    (is (not (fboundp 'nshell.presentation::make-char-transposition-plan)))
    (is (not (fboundp 'nshell.presentation::char-transposition-left)))
    (is (not (fboundp 'nshell.presentation::char-transposition-right)))
    (is (string= "acbd"
                 (nshell.presentation::char-transposition-buffer
                  transposition
                  "abcd")))
    (is (= 3 (nshell.presentation::char-transposition-cursor-pos
              transposition))))
  (let ((transposition (nshell.presentation::char-transposition-at-cursor
                        "abcd" 4)))
    (is (string= "abdc"
                 (nshell.presentation::char-transposition-buffer
                  transposition
                  "abcd")))
    (is (= 4 (nshell.presentation::char-transposition-cursor-pos
              transposition))))
  (is (null (nshell.presentation::char-transposition-at-cursor "a" 1)))
  (is (null (nshell.presentation::char-transposition-at-cursor "ab" 0))))

(test input-state-word-transform-edit-projects-token-replacement
  (let* ((edit (nshell.presentation::word-transform-edit-at-cursor
                "echo hello tail"
                5
                #'string-upcase))
         (plan (nshell.presentation::word-transform-edit-plan edit)))
    (is (nshell.presentation::%word-transform-edit-p edit))
    (is (nshell.presentation::%word-transform-plan-p plan))
    (is (eq plan (nshell.presentation::word-transform-edit-plan edit)))
    (is (fboundp 'nshell.presentation::%make-word-transform-edit))
    (is (fboundp 'nshell.presentation::%make-word-transform-plan))
    (is (not (fboundp 'nshell.presentation::word-transform-edit-p)))
    (is (not (fboundp 'nshell.presentation::word-transform-plan-p)))
    (is (not (fboundp 'nshell.presentation::make-word-transform-edit)))
    (is (not (fboundp 'nshell.presentation::make-word-transform-plan)))
    (is (not (fboundp 'nshell.presentation::word-transform-edit-start)))
    (is (not (fboundp 'nshell.presentation::word-transform-edit-end)))
    (is (not (fboundp 'nshell.presentation::word-transform-edit-replacement)))
    (is (= 5 (nshell.presentation::word-transform-plan-start plan)))
    (is (= 10 (nshell.presentation::word-transform-plan-end plan)))
    (is (string= "HELLO"
                 (nshell.presentation::word-transform-plan-replacement plan)))
    (is (string= "echo HELLO tail"
                 (nshell.presentation::word-transform-edit-buffer
                  edit
                  "echo hello tail")))
    (is (= 10 (nshell.presentation::word-transform-edit-cursor-pos edit))))
  (let ((edit (nshell.presentation::word-transform-edit-at-cursor
               "echo hello"
               0
               (lambda (word)
                 (concatenate 'string word "-suffix")))))
    (is (string= "echo-suffix hello"
                 (nshell.presentation::word-transform-edit-buffer
                  edit
                  "echo hello")))
    (is (= 11 (nshell.presentation::word-transform-edit-cursor-pos edit))))
  (is (null (nshell.presentation::word-transform-edit-at-cursor
             "   "
             0
             #'string-upcase))))

(test input-state-word-transposition-projects-token-swap
  (let* ((transposition (nshell.presentation::word-transposition-at-cursor
                         "echo one two" 9))
         (plan (nshell.presentation::word-transposition-plan transposition)))
    (is (nshell.presentation::%word-transposition-p transposition))
    (is (nshell.presentation::%word-transposition-plan-p plan))
    (is (eq plan (nshell.presentation::word-transposition-plan transposition)))
    (is (fboundp 'nshell.presentation::%make-word-transposition))
    (is (fboundp 'nshell.presentation::%make-word-transposition-plan))
    (is (not (fboundp 'nshell.presentation::word-transposition-p)))
    (is (not (fboundp 'nshell.presentation::word-transposition-plan-p)))
    (is (not (fboundp 'nshell.presentation::make-word-transposition)))
    (is (not (fboundp 'nshell.presentation::make-word-transposition-plan)))
    (is (not (fboundp 'nshell.presentation::word-transposition-left-start)))
    (is (not (fboundp 'nshell.presentation::word-transposition-left-end)))
    (is (not (fboundp 'nshell.presentation::word-transposition-middle-start)))
    (is (not (fboundp 'nshell.presentation::word-transposition-middle-end)))
    (is (not (fboundp 'nshell.presentation::word-transposition-right-start)))
    (is (not (fboundp 'nshell.presentation::word-transposition-right-end)))
    (is (= 5 (nshell.presentation::word-transposition-plan-left-start plan)))
    (is (= 8 (nshell.presentation::word-transposition-plan-left-end plan)))
    (is (= 8 (nshell.presentation::word-transposition-plan-middle-start plan)))
    (is (= 9 (nshell.presentation::word-transposition-plan-middle-end plan)))
    (is (= 9 (nshell.presentation::word-transposition-plan-right-start plan)))
    (is (= 12 (nshell.presentation::word-transposition-plan-right-end plan)))
    (is (string= "echo two one"
                 (nshell.presentation::word-transposition-buffer
                  transposition
                  "echo one two")))
    (is (= 12 (nshell.presentation::word-transposition-cursor-pos
               transposition))))
  (is (null (nshell.presentation::word-transposition-at-cursor "one" 3))))

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
