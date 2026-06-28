(in-package #:nshell/test)
(in-suite input-state-tests)

(test input-state-history-search-escape-restores-original-buffer
  (let ((state (history-search-state
                :buffer "git status"
                :query "status"
                :original-buffer "git"
                :index 0)))
    (with-reduced-input-state (restored output) (reduce-once state :ctrl-g)
      (is (string= "git" (nshell.presentation:input-state-buffer restored)))
      (is (= 3 (nshell.presentation:input-state-cursor-pos restored)))
      (is-search-session-cleared restored)
      (is (eq :suggest-update output)))))

(test input-state-history-search-escape-restores-original-cursor-position
  (let ((state (history-search-state
                :buffer "git status"
                :query "status"
                :original-buffer "git status"
                :original-cursor 4
                :index 0)))
    (with-reduced-input-state (restored output) (reduce-once state :ctrl-g)
      (is (string= "git status" (nshell.presentation:input-state-buffer restored)))
      (is (= 4 (nshell.presentation:input-state-cursor-pos restored)))
      (is-search-session-cleared restored)
      (is (eq :suggest-update output)))))

(test input-state-history-search-backspace-empty-query-restores-original-buffer
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
      (is (string= "git" (nshell.presentation:input-state-buffer restored)))
      (is (= 3 (nshell.presentation:input-state-cursor-pos restored)))
      (is-search-session-with-completion-cleared restored)
      (is (eq :suggest-update output)))))

(test input-state-history-search-enter-executes-selected-buffer
  (let ((state (history-search-state
                :buffer "git status"
                :query "status"
                :original-buffer ""
                :index 0)))
    (with-reduced-input-state (finished output) (reduce-once state :enter)
      (is (string= "git status"
                   (nshell.presentation:input-state-buffer finished)))
      (is-search-session-cleared finished)
      (is (eq :execute output)))))

(test input-state-history-search-right-accepts-selected-buffer-for-editing
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
      (is (string= "git status"
                   (nshell.presentation:input-state-buffer accepted)))
      (is (= 10 (nshell.presentation:input-state-cursor-pos accepted)))
      (is-search-session-with-completion-cleared accepted)
      (is (eq :suggest-update output))
      (with-reduced-input-state (edited edit-output) (reduce-once accepted :char #\!)
        (is (string= "git status!"
                     (nshell.presentation:input-state-buffer edited)))
        (is (eq :suggest-update edit-output))))))

(test input-state-history-search-ctrl-f-accepts-selected-buffer-for-editing
  (let ((state (history-search-state
                :buffer "docker ps"
                :query "ps"
                :original-buffer ""
                :index 0)))
    (with-reduced-input-state (accepted output) (reduce-once state :ctrl-f)
      (is (string= "docker ps"
                   (nshell.presentation:input-state-buffer accepted)))
      (is-search-session-cleared accepted)
      (is (eq :suggest-update output)))))

(test input-state-ctrl-c-clears-buffer
  (let ((state (input-state
                :buffer "abc"
                :cursor-pos 2
                :completion-index 1
                :completion-base-buffer "a"
                :completion-base-cursor 1
                :last-candidates '("abc" "awk")
                :suggestion "def")))
    (with-reduced-input-state (new-state output) (reduce-once state :ctrl-c)
      (is (string= "" (nshell.presentation:input-state-buffer new-state)))
      (is (= 0 (nshell.presentation:input-state-cursor-pos new-state)))
      (is (= -1 (nshell.presentation:input-state-completion-index new-state)))
      (is (null (nshell.presentation:input-state-completion-base-buffer new-state)))
      (is (null (nshell.presentation:input-state-completion-base-cursor new-state)))
      (is (null (nshell.presentation:input-state-last-candidates new-state)))
      (is (null (nshell.presentation:input-state-suggestion new-state)))
      (is (eq :redraw output)))))

(test input-state-history-search-ctrl-c-clears-and-exits-search-mode
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
      (is (string= "" (nshell.presentation:input-state-buffer new-state)))
      (is (= 0 (nshell.presentation:input-state-cursor-pos new-state)))
      (is-search-session-cleared new-state)
      (is (= -1 (nshell.presentation:input-state-completion-index new-state)))
      (is (null (nshell.presentation:input-state-completion-base-buffer new-state)))
      (is (null (nshell.presentation:input-state-completion-base-cursor new-state)))
      (is (null (nshell.presentation:input-state-last-candidates new-state)))
      (is (null (nshell.presentation:input-state-suggestion new-state)))
      (is (eq :redraw output)))))

(test input-state-ctrl-l-requests-screen-clear-without-editing
  (let ((state (input-state
                :buffer "abc"
                :cursor-pos 2
                :completion-index 1
                :suggestion "def")))
    (with-reduced-input-state (new-state output) (reduce-once state :ctrl-l)
      (is (string= "abc" (nshell.presentation:input-state-buffer new-state)))
      (is (= 2 (nshell.presentation:input-state-cursor-pos new-state)))
      (is (= 1 (nshell.presentation:input-state-completion-index new-state)))
      (is (string= "def" (nshell.presentation:input-state-suggestion new-state)))
      (is (eq :clear-screen output)))))

(test input-state-history-search-ctrl-l-clears-screen-without-editing
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
      (is (string= "git status" (nshell.presentation:input-state-buffer new-state)))
      (is (= 10 (nshell.presentation:input-state-cursor-pos new-state)))
      (is (string= " --short"
                   (nshell.presentation:input-state-suggestion new-state)))
      (is (eq :clear-screen output)))))
