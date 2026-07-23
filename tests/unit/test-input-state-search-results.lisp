(in-package #:nshell/test)

(describe "input-state-tests"
  (it "input-state-history-search-escape-restores-original-buffer"
    (let ((state (history-search-state
                  :buffer "git status"
                  :query "status"
                  :original-buffer "git"
                  :index 0)))
      (with-reduced-input-state (restored output) (reduce-once state :ctrl-g)
        (expect "git" :to-equal (nshell.presentation:input-state-buffer restored))
        (expect 3 :to-equal (nshell.presentation:input-state-cursor-pos restored))
        (is-search-session-cleared restored)
        (expect :suggest-update :to-be output))))

  (it "input-state-history-search-escape-restores-original-cursor-position"
    (let ((state (history-search-state
                  :buffer "git status"
                  :query "status"
                  :original-buffer "git status"
                  :original-cursor 4
                  :index 0)))
      (with-reduced-input-state (restored output) (reduce-once state :ctrl-g)
        (expect "git status" :to-equal (nshell.presentation:input-state-buffer restored))
        (expect 4 :to-equal (nshell.presentation:input-state-cursor-pos restored))
        (is-search-session-cleared restored)
        (expect :suggest-update :to-be output))))

  (it "input-state-history-search-backspace-empty-query-restores-original-buffer"
    (let ((state (history-search-state
                  :buffer "git status"
                  :query ""
                  :original-buffer "git"
                  :index 2
                  :completion-index 0
                  :completion-base-buffer "gi"
                  :completion-base-cursor 2
                  :last-candidates '("git" "grep")
                  :suggestion " --short")))
      (with-reduced-input-state (restored output) (reduce-once state :backspace)
        (expect "git" :to-equal (nshell.presentation:input-state-buffer restored))
        (expect 3 :to-equal (nshell.presentation:input-state-cursor-pos restored))
        (is-search-session-with-completion-cleared restored)
        (expect :suggest-update :to-be output))))

  (it "input-state-history-search-enter-executes-selected-buffer"
    (let ((state (history-search-state
                  :buffer "git status"
                  :query "status"
                  :original-buffer ""
                  :index 0)))
      (with-reduced-input-state (finished output) (reduce-once state :enter)
        (expect "git status" :to-equal (nshell.presentation:input-state-buffer finished))
        (is-search-session-cleared finished)
        (expect :execute :to-be output))))

  (it "input-state-history-search-right-accepts-selected-buffer-for-editing"
    (let ((state (history-search-state
                  :buffer "git status"
                  :query "status"
                  :original-buffer "git"
                  :index 2
                  :completion-index 0
                  :completion-base-buffer "gi"
                  :completion-base-cursor 2
                  :last-candidates '("git" "grep")
                  :suggestion " --short")))
      (with-reduced-input-state (accepted output) (reduce-once state :right)
        (expect "git status" :to-equal (nshell.presentation:input-state-buffer accepted))
        (expect 10 :to-equal (nshell.presentation:input-state-cursor-pos accepted))
        (is-search-session-with-completion-cleared accepted)
        (expect :suggest-update :to-be output)
        (with-reduced-input-state (edited edit-output) (reduce-once accepted :char #\!)
          (expect "git status!" :to-equal (nshell.presentation:input-state-buffer edited))
          (expect :suggest-update :to-be edit-output)))))

  (it "input-state-history-search-ctrl-f-accepts-selected-buffer-for-editing"
    (let ((state (history-search-state
                  :buffer "docker ps"
                  :query "ps"
                  :original-buffer ""
                  :index 0)))
      (with-reduced-input-state (accepted output) (reduce-once state :ctrl-f)
        (expect "docker ps" :to-equal (nshell.presentation:input-state-buffer accepted))
        (is-search-session-cleared accepted)
        (expect :suggest-update :to-be output))))

  (it "input-state-ctrl-c-clears-buffer"
    (let ((state (input-state
                  :buffer "abc"
                  :cursor-pos 2
                  :completion-index 1
                  :completion-base-buffer "a"
                  :completion-base-cursor 1
                  :last-candidates '("abc" "awk")
                  :suggestion "def")))
      (with-reduced-input-state (new-state output) (reduce-once state :ctrl-c)
        (expect "" :to-equal (nshell.presentation:input-state-buffer new-state))
        (expect 0 :to-equal (nshell.presentation:input-state-cursor-pos new-state))
        (expect -1 :to-equal (nshell.presentation:input-state-completion-index new-state))
        (expect (nshell.presentation:input-state-completion-base-buffer new-state) :to-be-null)
        (expect (nshell.presentation:input-state-completion-base-cursor new-state) :to-be-null)
        (expect (nshell.presentation:input-state-last-candidates new-state) :to-be-null)
        (expect (nshell.presentation:input-state-suggestion new-state) :to-be-null)
        (expect :redraw :to-be output))))

  (it "input-state-history-search-ctrl-c-clears-and-exits-search-mode"
    (let ((state (history-search-state
                  :buffer "git status"
                  :query "status"
                  :original-buffer "git"
                  :index 2
                  :completion-index 0
                  :completion-base-buffer "gi"
                  :completion-base-cursor 2
                  :last-candidates '("git" "grep")
                  :suggestion " --short")))
      (with-reduced-input-state (new-state output) (reduce-once state :ctrl-c)
        (expect "" :to-equal (nshell.presentation:input-state-buffer new-state))
        (expect 0 :to-equal (nshell.presentation:input-state-cursor-pos new-state))
        (is-search-session-cleared new-state)
        (expect -1 :to-equal (nshell.presentation:input-state-completion-index new-state))
        (expect (nshell.presentation:input-state-completion-base-buffer new-state) :to-be-null)
        (expect (nshell.presentation:input-state-completion-base-cursor new-state) :to-be-null)
        (expect (nshell.presentation:input-state-last-candidates new-state) :to-be-null)
        (expect (nshell.presentation:input-state-suggestion new-state) :to-be-null)
        (expect :redraw :to-be output))))

  (it "input-state-ctrl-l-requests-screen-clear-without-editing"
    (let ((state (input-state
                  :buffer "abc"
                  :cursor-pos 2
                  :completion-index 1
                  :suggestion "def")))
      (with-reduced-input-state (new-state output) (reduce-once state :ctrl-l)
        (expect "abc" :to-equal (nshell.presentation:input-state-buffer new-state))
        (expect 2 :to-equal (nshell.presentation:input-state-cursor-pos new-state))
        (expect 1 :to-equal (nshell.presentation:input-state-completion-index new-state))
        (expect "def" :to-equal (nshell.presentation:input-state-suggestion new-state))
        (expect :clear-screen :to-be output))))

  (it "input-state-history-search-ctrl-l-clears-screen-without-editing"
    (let ((state (history-search-state
                  :buffer "git status"
                  :query "status"
                  :original-buffer "git"
                  :index 2
                  :suggestion " --short")))
      (with-reduced-input-state (new-state output) (reduce-once state :ctrl-l)
        (is-search-state new-state
                         :mode :search
                         :query "status"
                         :original-buffer "git"
                         :index 2)
        (expect "git status" :to-equal (nshell.presentation:input-state-buffer new-state))
        (expect 10 :to-equal (nshell.presentation:input-state-cursor-pos new-state))
        (expect " --short" :to-equal (nshell.presentation:input-state-suggestion new-state))
        (expect :clear-screen :to-be output)))))
