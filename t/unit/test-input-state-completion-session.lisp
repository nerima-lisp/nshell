(in-package #:nshell/test)

(describe "input-state-tests"
  (it "input-state-edit-after-completion-list-clears-stale-candidates"
    (let ((state (completion-session-state
                  :buffer "g"
                  :cursor-pos 1
                  :completion-index -1
                  :last-candidates '("git" "grep"))))
      (multiple-value-bind (edited edit-output) (reduce-once state :char #\x)
        (is-input-state-with-completion-cleared edited
                                                :buffer "gx"
                                                :cursor-pos 2)
        (expect :suggest-update :to-be edit-output)
        (multiple-value-bind (tabbed tab-output) (reduce-once edited :tab)
          (is-input-state-with-completion-cleared tabbed
                                                  :buffer "gx")
          (expect :complete :to-be tab-output)))))

  (it "input-state-copy-clearing-completion-with-buffer-replaces-buffer-and-clears-session"
    (let* ((state (completion-session-state
                   :buffer "g"
                   :cursor-pos 1
                   :completion-index 2
                   :completion-base-buffer "g"
                   :completion-base-cursor 1
                   :last-candidates '("git" "grep")
                   :suggestion "it"))
           (new-state (nshell.presentation::copy-input-state-clearing-completion
                       state
                       :buffer "git status"
                       :cursor-pos 4)))
      (is-input-state new-state
                      :buffer "git status"
                      :cursor-pos 4)
      (is-completion-session-cleared new-state)))

  (it "input-completion-session-clear-is-private-value"
    (let* ((state (input-state
                   :buffer "git"
                   :cursor-pos 2
                   :completion-index 1
                   :completion-base-buffer "g"
                   :completion-base-cursor 1
                   :last-candidates '("git" "grep")
                   :suggestion " status"
                   :search-query "g"
                   :search-original-buffer "git"
                   :search-original-cursor 3
                   :search-index 4))
           (clear (nshell.presentation::completion-session-clear))
           (cleared (nshell.presentation::apply-completion-session-clear state clear)))
      (expect (nshell.presentation::%input-session-clear-p clear) :to-be-truthy)
      (expect :completion :to-be (nshell.presentation::%input-session-clear-kind clear))
      (expect (listp clear) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-input-session-clear) :to-be-falsy)
      (is-input-state cleared
                      :buffer "git"
                      :cursor-pos 2)
      (is-completion-session-cleared cleared)
      (is-search-state cleared
                       :query "g"
                       :original-buffer "git"
                       :original-cursor 3
                       :index 4)))

  (it "input-completion-session-clear-rejects-history-search-clear"
    (expect (lambda () (nshell.presentation::apply-completion-session-clear
       (input-state)
       (nshell.presentation::history-search-session-clear))) :to-throw 'error))

  (it "input-state-escape-clears-completion-session-without-editing"
    (let ((state (completion-session-state
                  :buffer "g"
                  :cursor-pos 1
                  :completion-index 0
                  :completion-base-buffer "g"
                  :completion-base-cursor 1
                  :last-candidates '("git" "grep")
                  :suggestion "it status")))
      (multiple-value-bind (new-state output) (reduce-once state :escape)
        (is-input-state-with-completion-cleared new-state
                                                :buffer "g"
                                                :cursor-pos 1)
        (expect :redraw :to-be output))))

  (it "input-state-ctrl-g-clears-completion-session-without-editing"
    (let ((state (completion-session-state
                  :buffer "git"
                  :cursor-pos 2
                  :completion-index 1
                  :completion-base-buffer "g"
                  :completion-base-cursor 1
                  :last-candidates '("git" "grep")
                  :suggestion " status")))
      (multiple-value-bind (new-state output) (reduce-once state :ctrl-g)
        (is-input-state-with-completion-cleared new-state
                                                :buffer "git"
                                                :cursor-pos 2)
        (expect :redraw :to-be output))))

  (it "input-state-ctrl-c-clears-completion-session-on-empty-buffer"
    (let ((state (completion-session-state
                  :buffer ""
                  :cursor-pos 0
                  :completion-index 0
                  :completion-base-buffer ""
                  :completion-base-cursor 0
                  :last-candidates '("git"))))
      (multiple-value-bind (new-state output) (reduce-once state :ctrl-c)
        (is-input-state-with-completion-cleared new-state
                                                :buffer ""
                                                :cursor-pos 0)
        (expect :redraw :to-be output))))

  (it "input-state-ctrl-l-preserves-completion-session"
    (let ((state (completion-session-state
                  :buffer "g"
                  :cursor-pos 1
                  :completion-index 0
                  :completion-base-buffer "g"
                  :completion-base-cursor 1
                  :last-candidates '("git" "grep"))))
      (multiple-value-bind (new-state output) (reduce-once state :ctrl-l)
        (is-input-state new-state
                        :buffer "g"
                        :cursor-pos 1
                        :completion-index 0
                        :completion-base-buffer "g"
                        :completion-base-cursor 1
                        :last-candidates '("git" "grep"))
        (expect :clear-screen :to-be output))))

  (it "completion-output-helper-validates-rendered-completion-session"
    (let ((state (completion-session-state
                  :buffer "git status"
                  :cursor-pos 10
                  :completion-index 0
                  :completion-base-buffer "git st"
                  :completion-base-cursor 6
                  :last-candidates '("status" "stash"))))
      (expect (nshell.presentation::%completion-session-valid-p state) :to-be-truthy)
      (expect (nshell.presentation::%completion-session-valid-p
                (nshell.presentation::copy-input-state-with
                 state :buffer "git stash")) :to-be-falsy)))
  (it "completion-pager-reducer-ctrl-c-restores-original-input"
    (let ((state (input-state
                  :buffer "echo original "
                  :cursor-pos 15
                  :completion-base-buffer "echo original "
                  :completion-base-cursor 15
                  :last-candidates '("alpha" "beta")
                  :completion-pager (list :query "b" :index 1))))
      (multiple-value-bind (new-state output)
          (nshell.presentation:reduce-input-state
           state
           (input-key-event :ctrl-c))
        (expect "echo original " :to-equal
                (nshell.presentation:input-state-buffer new-state))
        (expect nil :to-be
                (nshell.presentation::input-state-completion-pager new-state))
        (expect nil :to-be
                (nshell.presentation:input-state-last-candidates new-state))
        (expect :redraw :to-be output))))
  (it "completion-pager-reducer-down-moves-selection"
    (let ((state (input-state
                  :buffer "echo "
                  :cursor-pos 5
                  :completion-base-buffer "echo "
                  :completion-base-cursor 5
                  :last-candidates '("alpha" "beta")
                  :completion-pager (list :query "" :index 0))))
      (multiple-value-bind (new-state output)
          (nshell.presentation:reduce-input-state
           state
           (input-key-event :down))
        (expect 1 :to-equal
                (getf (nshell.presentation::input-state-completion-pager new-state)
                      :index))
        (expect "echo " :to-equal
                (nshell.presentation:input-state-buffer new-state))
        (expect :redraw :to-be output))))
  (it "completion-pager-reducer-moves-vertically-by-displayed-row"
    (let ((state (input-state
                  :buffer "echo "
                  :cursor-pos 5
                  :completion-base-buffer "echo "
                  :completion-base-cursor 5
                  :last-candidates
                    (list
                     (nshell.domain.completion:make-candidate "a" :kind :file)
                     (nshell.domain.completion:make-candidate "b" :kind :file)
                     (nshell.domain.completion:make-candidate "c" :kind :file)
                     (nshell.domain.completion:make-candidate "d" :kind :file))
                  :completion-pager (list :query "" :index 0))))
      (with-fixed-terminal-size (24 10)
        (multiple-value-bind (down-state down-output)
            (nshell.presentation:reduce-input-state
             state
             (input-key-event :down))
          (expect 2 :to-equal
                  (getf (nshell.presentation::input-state-completion-pager down-state)
                        :index))
          (expect :redraw :to-be down-output)
          (multiple-value-bind (up-state up-output)
              (nshell.presentation:reduce-input-state
               down-state
               (input-key-event :up))
            (expect 0 :to-equal
                    (getf (nshell.presentation::input-state-completion-pager up-state)
                          :index))
            (expect :redraw :to-be up-output))))
      (with-fixed-terminal-size (24 10)
        (let ((partial-row-state
                (input-state
                 :buffer "echo "
                 :cursor-pos 5
                 :completion-base-buffer "echo "
                 :completion-base-cursor 5
                 :last-candidates
                   (list
                    (nshell.domain.completion:make-candidate "a" :kind :file)
                    (nshell.domain.completion:make-candidate "b" :kind :file)
                    (nshell.domain.completion:make-candidate "c" :kind :file)
                    (nshell.domain.completion:make-candidate "d" :kind :file)
                    (nshell.domain.completion:make-candidate "e" :kind :file))
                 :completion-pager (list :query "" :index 4))))
          (multiple-value-bind (new-state output)
              (nshell.presentation:reduce-input-state
               partial-row-state
               (input-key-event :down))
            (expect 4 :to-equal
                    (getf (nshell.presentation::input-state-completion-pager new-state)
                          :index))
            (expect :redraw :to-be output))))))
  (it "completion-pager-reducer-character-filters-without-editing-input"
    (let ((state (input-state
                  :buffer "echo "
                  :cursor-pos 5
                  :completion-base-buffer "echo "
                  :completion-base-cursor 5
                  :last-candidates '("alpha" "beta")
                  :completion-pager (list :query "" :index 0))))
      (multiple-value-bind (new-state output)
          (nshell.presentation:reduce-input-state
           state
           (input-key-event :char #\b))
        (expect "b" :to-equal
                (getf (nshell.presentation::input-state-completion-pager new-state)
                      :query))
        (expect "echo " :to-equal
                (nshell.presentation:input-state-buffer new-state))
        (expect :redraw :to-be output)))))
