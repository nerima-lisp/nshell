(in-package #:nshell/test)

(in-suite input-state-tests)

(test input-state-edit-after-completion-list-clears-stale-candidates
  (let ((state (completion-session-state
                :buffer "g"
                :cursor-pos 1
                :completion-index -1
                :last-candidates '("git" "grep"))))
    (multiple-value-bind (edited edit-output) (reduce-once state :char #\x)
      (is-input-state-with-completion-cleared edited
                                              :buffer "gx"
                                              :cursor-pos 2)
      (is (eq :suggest-update edit-output))
      (multiple-value-bind (tabbed tab-output) (reduce-once edited :tab)
        (is-input-state-with-completion-cleared tabbed
                                                :buffer "gx")
        (is (eq :complete tab-output))))))

(test input-state-copy-clearing-completion-with-buffer-replaces-buffer-and-clears-session
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

(test input-state-escape-clears-completion-session-without-editing
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
      (is (eq :redraw output)))))

(test input-state-ctrl-g-clears-completion-session-without-editing
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
      (is (eq :redraw output)))))

(test input-state-ctrl-c-clears-completion-session-on-empty-buffer
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
      (is (eq :redraw output)))))

(test input-state-ctrl-l-preserves-completion-session
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
      (is (eq :clear-screen output)))))

(test completion-output-helper-validates-rendered-completion-session
  (let ((state (completion-session-state
                :buffer "git status"
                :cursor-pos 10
                :completion-index 0
                :completion-base-buffer "git st"
                :completion-base-cursor 6
                :last-candidates '("status" "stash"))))
    (is (nshell.presentation::%completion-session-valid-p state))
    (is (not (nshell.presentation::%completion-session-valid-p
              (nshell.presentation::copy-input-state-with
               state :buffer "git stash"))))))
