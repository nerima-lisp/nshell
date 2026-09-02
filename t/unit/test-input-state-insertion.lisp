(in-package #:nshell/test)

(describe "input-state-tests"
  (it "input-state-inserting-char-updates-buffer"
    (with-expected-input-state-reduction (new-state output)
        (input-state)
        (reduce-once (input-state) :char #\a)
        :suggest-update
        (:buffer "a" :cursor-pos 1)))

  (it "input-state-reducer-accepts-domain-key-events-directly"
    (let ((event (nshell.domain.input:make-key-event :char #\x)))
      (with-expected-input-state-reduction (new-state output)
          (input-state)
          (nshell.presentation:reduce-input-state (input-state) event)
          :suggest-update
          (:buffer "x" :cursor-pos 1))))

  (it "key-event-constructor-exposes-the-value-contract"
    (let ((event (nshell.domain.input:make-key-event :char #\x)))
      (expect (nshell.domain.input:key-event-p event) :to-be-truthy)
      (expect :char :to-be (nshell.domain.input:key-event-type event))
      (expect #\x :to-equal (nshell.domain.input:key-event-char event))
      (expect (fboundp 'nshell.domain.input:make-key-event) :to-be-truthy)
      (expect (fboundp 'nshell.domain.input::%make-key-event) :to-be-falsy)
      (expect (fboundp 'nshell.domain.input::copy-key-event) :to-be-falsy)))

  (it "key-event-constructor-applies-data-defaults"
    (let ((event (nshell.domain.input:make-key-event :char nil)))
      (expect :char :to-be (nshell.domain.input:key-event-type event))
      (expect nil :to-be (nshell.domain.input:key-event-char event))
      (expect nil :to-be (nshell.domain.input:key-event-number event))
      (expect nil :to-be (nshell.domain.input:key-event-data event))))

  (it "key-event-preserves-structured-payload"
    (let ((event (nshell.domain.input:make-key-event
                  :mouse nil 7 '(:button 1 :shift-p t))))
      (expect :mouse :to-be (nshell.domain.input:key-event-type event))
      (expect 7 :to-equal (nshell.domain.input:key-event-number event))
      (expect '(:button 1 :shift-p t)
              :to-equal
              (nshell.domain.input:key-event-data event))))

  (it "input-state-inserting-unicode-char-updates-buffer"
    (let ((state (input-state :buffer "xy" :cursor-pos 1))
          (ch (char "あ" 0)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :char ch)
          :suggest-update
          (:buffer "xあy" :cursor-pos 2))))

  (it "input-state-buffer-splice-projects-insertion-result-and-cursor"
    (let ((splice (nshell.presentation::make-buffer-splice 5 5 "hello ")))
      (expect "echo hello done" :to-equal (nshell.presentation::buffer-splice-result splice "echo done"))
      (expect 11 :to-equal (nshell.presentation::buffer-splice-cursor-pos splice))))

  (it "input-state-buffer-splice-projects-deletion-result-and-cursor"
    (let ((splice (nshell.presentation::make-buffer-splice 4 8)))
      (expect "git main" :to-equal (nshell.presentation::buffer-splice-result splice "git old main"))
      (expect 4 :to-equal (nshell.presentation::buffer-splice-cursor-pos splice))))

  (it "input-state-constructor-retains-data-fields-and-defaults"
    (let ((state (input-state :buffer "echo"
                              :cursor-pos 2
                              :completion-index 1
                              :completion-base-buffer "ec"
                              :completion-base-cursor 2
                              :last-candidates '("echo")
                              :suggestion "echo"
                              :mode :vi-c
                              :vi-count 3
                              :search-query "ec"
                              :search-index 1
                              :undo-stack '(:before)
                              :redo-stack '(:after))))
      (expect "echo" :to-be (nshell.presentation:input-state-buffer state))
      (expect 2 :to-be (nshell.presentation:input-state-cursor-pos state))
      (expect 1 :to-be (nshell.presentation:input-state-completion-index state))
      (expect "ec" :to-be (nshell.presentation:input-state-completion-base-buffer state))
      (expect 2 :to-be (nshell.presentation:input-state-completion-base-cursor state))
      (expect '("echo") :to-equal (nshell.presentation:input-state-last-candidates state))
      (expect :vi-c :to-be (nshell.presentation:input-state-mode state))
      (expect 3 :to-be (nshell.presentation::input-state-vi-count state))
      (expect "ec" :to-be (nshell.presentation:input-state-search-query state))
      (expect 1 :to-be (nshell.presentation:input-state-search-index state))
      (expect '(:before) :to-equal (nshell.presentation::input-state-undo-stack state))
      (expect '(:after) :to-equal (nshell.presentation::input-state-redo-stack state))
      (expect nil :to-be (nshell.presentation:input-state-kill-ring state))))

  (it "input-state-buffer-insertion-projects-capped-result-and-cursor"
    (let* ((buffer "echo  done")
           (insertion (nshell.presentation::buffer-insertion-at-cursor
                       buffer 5 "hello")))
      (expect (nshell.presentation::%buffer-insertion-p insertion) :to-be-truthy)
      (expect (nshell.presentation::%buffer-insertion-plan-p
           (nshell.presentation::%buffer-insertion-plan insertion)) :to-be-truthy)
      (assert-symbol-boundaries
          :present (nshell.presentation::%make-buffer-insertion-plan
                    nshell.presentation::%buffer-insertion-plan-splice)
          :absent (nshell.presentation::make-buffer-insertion
                   nshell.presentation::make-buffer-insertion-plan
                   nshell.presentation::buffer-insertion-plan
                   nshell.presentation::buffer-insertion-plan-splice
                   nshell.presentation::buffer-insertion-p
                   nshell.presentation::buffer-insertion-plan-p))
      (expect "echo hello done" :to-equal (nshell.presentation::buffer-insertion-result
                    insertion
                    buffer))
      (expect 10 :to-equal (nshell.presentation::buffer-insertion-cursor-pos
                 insertion)))
    (let* ((limit 4096)
           (buffer (make-string 4094 :initial-element #\x))
           (insertion (nshell.presentation::buffer-insertion-at-cursor
                       buffer
                       4094
                       "abcdef")))
      (expect (concatenate 'string buffer "ab") :to-equal (nshell.presentation::buffer-insertion-result
                    insertion
                    buffer))
      (expect limit :to-equal (nshell.presentation::buffer-insertion-cursor-pos
                    insertion))))

  (it "input-state-buffer-insertion-rejects-non-insertions"
    (let ((buffer (make-string 4096 :initial-element #\x)))
      (expect (nshell.presentation::buffer-insertion-at-cursor
                 "echo" 4 "") :to-be-null)
      (expect (nshell.presentation::buffer-insertion-at-cursor
                 "echo" 4 :not-a-string) :to-be-null)
      (expect (nshell.presentation::buffer-insertion-at-cursor
                 buffer 4096 "x") :to-be-null)))

  (it "input-state-buffer-deletion-projects-result-and-cursor"
    (let* ((buffer "abcd")
           (before-request
             (nshell.presentation::buffer-deletion-request-before-cursor 2))
           (at-request
             (nshell.presentation::buffer-deletion-request-at-cursor 1))
           (before (nshell.presentation::buffer-deletion-for-request
                    before-request
                    buffer))
           (at (nshell.presentation::buffer-deletion-for-request
                at-request
                buffer)))
      (expect (nshell.presentation::%buffer-deletion-request-p before-request) :to-be-truthy)
      (expect (nshell.presentation::%buffer-deletion-request-p at-request) :to-be-truthy)
      (expect :before-cursor :to-be (nshell.presentation::%buffer-deletion-request-kind
               before-request))
      (expect :at-cursor :to-be (nshell.presentation::%buffer-deletion-request-kind
               at-request))
      (expect 2 :to-equal (nshell.presentation::%buffer-deletion-request-cursor
                before-request))
      (expect 1 :to-equal (nshell.presentation::%buffer-deletion-request-cursor
                at-request))
      (expect (nshell.presentation::%buffer-deletion-p before) :to-be-truthy)
      (expect (nshell.presentation::%buffer-deletion-p at) :to-be-truthy)
      (expect (nshell.presentation::%buffer-deletion-plan-p
           (nshell.presentation::%buffer-deletion-plan before)) :to-be-truthy)
      (expect (nshell.presentation::%buffer-deletion-plan-p
           (nshell.presentation::%buffer-deletion-plan at)) :to-be-truthy)
      (assert-symbol-boundaries
          :present (nshell.presentation::%make-buffer-deletion-request
                    nshell.presentation::%buffer-deletion-request-kind
                    nshell.presentation::%buffer-deletion-request-cursor
                    nshell.presentation::%make-buffer-deletion
                    nshell.presentation::%make-buffer-deletion-plan
                    nshell.presentation::%buffer-deletion-plan-splice)
          :absent (nshell.presentation::make-buffer-deletion-request
                   nshell.presentation::buffer-deletion-before-cursor
                   nshell.presentation::buffer-deletion-at-cursor
                   nshell.presentation::make-buffer-deletion
                   nshell.presentation::make-buffer-deletion-plan
                   nshell.presentation::buffer-deletion-plan
                   nshell.presentation::buffer-deletion-plan-splice
                   nshell.presentation::buffer-deletion-request-kind
                   nshell.presentation::buffer-deletion-request-cursor
                   nshell.presentation::buffer-deletion-request-p
                   nshell.presentation::buffer-deletion-p
                   nshell.presentation::buffer-deletion-plan-p))
      (expect "acd" :to-equal (nshell.presentation::buffer-deletion-result before buffer))
      (expect 1 :to-equal (nshell.presentation::buffer-deletion-cursor-pos before))
      (expect "acd" :to-equal (nshell.presentation::buffer-deletion-result at buffer))
      (expect 1 :to-equal (nshell.presentation::buffer-deletion-cursor-pos at))))

  (it "input-state-buffer-deletion-rejects-empty-ranges"
    (expect (nshell.presentation::buffer-deletion-for-request
               (nshell.presentation::buffer-deletion-request-before-cursor 0)
               "abc") :to-be-null)
    (expect (nshell.presentation::buffer-deletion-for-request
               (nshell.presentation::buffer-deletion-request-at-cursor 0)
               "") :to-be-null)
    (expect (nshell.presentation::buffer-deletion-for-request
               (nshell.presentation::buffer-deletion-request-at-cursor 3)
               "abc") :to-be-null))

  (it "input-state-cursor-move-edit-projects-position-through-commit"
    (let* ((state (input-state :buffer "abcdef"
                               :cursor-pos 3
                               :suggestion "def"))
           (request (nshell.presentation::cursor-move-request-by 3 2))
           (edit (nshell.presentation::cursor-move-edit-for-request request))
           (committed (nshell.presentation::commit-cursor-move-edit state edit)))
      (assert-symbol-boundaries
          :present (nshell.presentation::%make-cursor-move-request
                    nshell.presentation::%cursor-move-request-kind
                    nshell.presentation::%cursor-move-request-cursor
                    nshell.presentation::%cursor-move-request-delta
                    nshell.presentation::%cursor-move-request-position
                    nshell.presentation::%make-cursor-move-edit
                    nshell.presentation::%cursor-move-edit-cursor-pos)
          :absent (nshell.presentation::make-cursor-move-request
                   nshell.presentation::make-cursor-move-edit
                   nshell.presentation::cursor-move-request-kind
                   nshell.presentation::cursor-move-request-cursor
                   nshell.presentation::cursor-move-request-delta
                   nshell.presentation::cursor-move-request-position
                   nshell.presentation::cursor-move-edit-by
                   nshell.presentation::cursor-move-edit-to
                   nshell.presentation::cursor-move-edit-cursor-pos
                   nshell.presentation::cursor-move-request-p
                   nshell.presentation::cursor-move-edit-p))
      (expect (nshell.presentation::%cursor-move-request-p request) :to-be-truthy)
      (expect :by :to-be (nshell.presentation::%cursor-move-request-kind request))
      (expect 3 :to-equal (nshell.presentation::%cursor-move-request-cursor request))
      (expect 2 :to-equal (nshell.presentation::%cursor-move-request-delta request))
      (expect 5 :to-equal (nshell.presentation::%cursor-move-edit-cursor-pos edit))
      (is-input-state committed
                      :buffer "abcdef"
                      :cursor-pos 5
                      :suggestion nil))
    (let* ((state (input-state :buffer "abcdef"
                               :cursor-pos 3
                               :suggestion "def"))
           (request (nshell.presentation::cursor-move-request-to 99))
           (edit (nshell.presentation::cursor-move-edit-for-request request))
           (committed (nshell.presentation::commit-cursor-move-edit state edit)))
      (expect (nshell.presentation::%cursor-move-request-p request) :to-be-truthy)
      (expect (nshell.presentation::%cursor-move-edit-p edit) :to-be-truthy)
      (expect :to :to-be (nshell.presentation::%cursor-move-request-kind request))
      (expect 99 :to-equal (nshell.presentation::%cursor-move-request-position request))
      (expect 99 :to-equal (nshell.presentation::%cursor-move-edit-cursor-pos edit))
      (is-input-state committed
                      :buffer "abcdef"
                      :cursor-pos 6
                      :suggestion nil)))

  (it "input-state-buffer-clear-edit-resets-editing-session"
    (let* ((state (completion-session-state
                   :buffer "abcdef"
                   :cursor-pos 3
                   :mode :search
                   :vi-count 4
                   :vi-visual-anchor 2
                   :search-query "abc"
                   :search-original-buffer "original"
                   :search-original-cursor 5
                   :search-index 2
                   :completion-index 1
                   :completion-base-buffer "abc"
                   :completion-base-cursor 3
                   :last-candidates (list "abcdef")
                   :suggestion "def"))
           (edit (nshell.presentation::make-buffer-clear-edit))
           (plan (nshell.presentation::%buffer-clear-edit-plan edit))
           (committed (nshell.presentation::commit-buffer-clear-edit state edit)))
      (expect (nshell.presentation::%buffer-clear-edit-p edit) :to-be-truthy)
      (expect (nshell.presentation::%buffer-clear-plan-p plan) :to-be-truthy)
      (expect plan :to-be (nshell.presentation::%buffer-clear-edit-plan edit))
      (assert-symbol-boundaries
          :present (nshell.presentation::%make-buffer-clear-edit
                    nshell.presentation::%make-buffer-clear-plan)
          :absent (nshell.presentation::buffer-clear-edit-plan
                   nshell.presentation::buffer-clear-edit-p
                   nshell.presentation::buffer-clear-plan-buffer
                   nshell.presentation::buffer-clear-plan-cursor-pos
                   nshell.presentation::buffer-clear-plan-mode
                   nshell.presentation::buffer-clear-plan-vi-count
                   nshell.presentation::buffer-clear-plan-vi-visual-anchor
                   nshell.presentation::buffer-clear-plan-clear-completion-p
                   nshell.presentation::buffer-clear-plan-clear-history-search-p
                   nshell.presentation::buffer-clear-plan-p))
      (expect "" :to-equal (nshell.presentation::%buffer-clear-plan-buffer plan))
      (expect 0 :to-equal (nshell.presentation::%buffer-clear-plan-cursor-pos plan))
      (expect :insert :to-be (nshell.presentation::%buffer-clear-plan-mode plan))
      (expect (nshell.presentation::%buffer-clear-plan-vi-count plan) :to-be-null)
      (expect :clear :to-be (nshell.presentation::%buffer-clear-plan-vi-visual-anchor plan))
      (expect (nshell.presentation::%buffer-clear-plan-clear-completion-p plan) :to-be-truthy)
      (expect (nshell.presentation::%buffer-clear-plan-clear-history-search-p plan) :to-be-truthy)
      (is-input-state-with-completion-cleared committed
                                              :buffer ""
                                              :cursor-pos 0
                                              :mode :insert
                                              :vi-visual-anchor nil)
      (expect (nshell.presentation::input-state-vi-count committed) :to-be-null)
      (is-search-session-cleared committed)))

  (it "input-state-space-expands-abbreviation-before-cursor"
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
          (reduce-once state :char #\Space)
          :suggest-update
          (:buffer "git checkout " :cursor-pos 13)
        (is-input-state-with-completion-cleared new-state
                                                :buffer "git checkout "
                                                :cursor-pos 13))))

  (it "input-state-space-keeps-quoted-abbreviation-literal"
    (let ((state (input-state
                  :buffer "echo \"gco\""
                  :cursor-pos 10
                  :abbreviation-expander
                  (lambda (token)
                    (when (string= token "\"gco\"")
                      "git checkout")))))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :char #\Space)
          :suggest-update
          (:buffer "echo \"gco\" " :cursor-pos 11))))

  (it "input-state-operator-expands-abbreviation-before-cursor"
    (let ((state (input-state
                  :buffer "gco"
                  :cursor-pos 3
                  :abbreviation-expander
                  (lambda (token)
                    (when (string= token "gco")
                      "git checkout")))))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :char #\|)
          :suggest-update
          (:buffer "git checkout|" :cursor-pos 13))))

  (it "input-state-abbreviation-expansion-treats-operators-as-token-boundaries"
    (let ((state (input-state
                  :buffer "echo|ec"
                  :cursor-pos 7
                  :abbreviation-expander
                  (lambda (token)
                    (when (string= token "ec")
                      "echo")))))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :char #\Space)
          :suggest-update
          (:buffer "echo|echo " :cursor-pos 10))))

  (it "input-state-abbreviation-expansion-targets-current-token-only"
    (let ((state (input-state
                  :buffer "echo gco tail"
                  :cursor-pos 8
                  :abbreviation-expander
                  (lambda (token)
                    (when (string= token "gco")
                      "git checkout")))))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :char #\Space)
          :suggest-update
          (:buffer "echo git checkout  tail" :cursor-pos 18))))

  (it "input-state-abbreviation-expansion-respects-escaped-space-token"
    (let ((state (input-state
                  :buffer "echo foo\\ gco"
                  :cursor-pos 13
                  :abbreviation-expander
                  (lambda (token)
                    (when (string= token "gco")
                      "git checkout")))))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :char #\Space)
          :suggest-update
          (:buffer "echo foo\\ gco " :cursor-pos 14))))

  (it "pbt-input-state-space-expands-current-abbreviation-token-only"
    (check-property (:trials 50)
        ((token (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
         (tail (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word))
      (let* ((prefix "echo ")
             (suffix (concatenate 'string " --" tail))
             (expansion (concatenate 'string "expanded-" token))
             (buffer (concatenate 'string prefix token suffix))
             (cursor (+ (length prefix) (length token)))
              (state (completion-session-state
                      :buffer buffer
                      :cursor-pos cursor
                      :completion-index 2
                     :suggestion " ignored"
                     :abbreviation-expander
                     (lambda (candidate)
                       (when (string= candidate token)
                         expansion)))))
         (with-expected-input-state-reduction (new-state output)
             state
             (reduce-once state :char #\Space)
             :suggest-update
             (:buffer (concatenate 'string prefix expansion " " suffix)
              :cursor-pos (+ (length prefix) (length expansion) 1))
           (progn
             (is-completion-session-cleared new-state)
             t)))))

  (it "input-state-paste-inserts-text-at-cursor"
    (let ((state (completion-session-state
                  :buffer "echo  done"
                  :cursor-pos 5
                  :completion-index 1
                  :suggestion "ignored")))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :paste nil nil
                       (list :protocol :bracketed
                             :text (format nil "hello~%world")))
          :suggest-update
          (:buffer (format nil "echo hello~%world done")
           :cursor-pos 16)
        (is-input-state-with-completion-cleared new-state
                                                :buffer (format nil "echo hello~%world done")
                                                :cursor-pos 16))))

  (it "input-state-paste-normalizes-crlf-and-cr-newlines"
    (let* ((paste-text (format nil "git status~C~Cpwd~Cls"
                               #\Return #\Newline #\Return))
           (state (input-state :buffer "echo  done" :cursor-pos 5)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :paste nil nil
                       (list :protocol :bracketed :text paste-text))
          :suggest-update
          (:buffer (format nil "echo git status~%pwd~%ls done")
           :cursor-pos 22))))

  (it "input-state-paste-does-not-expand-abbreviation-and-undoes-once"
    (let ((state (input-state
                  :buffer "echo "
                  :cursor-pos 5
                  :abbreviation-expander
                  (lambda (token)
                    (when (string= token "gco")
                      "git checkout")))))
      (with-reduced-input-state (pasted paste-output)
          (reduce-once state :paste nil nil
                       '(:protocol :bracketed :text "gco "))
        (is-input-state pasted :buffer "echo gco " :cursor-pos 9)
        (expect :suggest-update :to-be paste-output)
        (with-reduced-input-state (undone undo-output)
            (reduce-once pasted :ctrl-underscore)
          (is-input-state undone :buffer "echo " :cursor-pos 5)
          (expect :suggest-update :to-be undo-output)))))

  (it "normalize-paste-text-normalizes-line-endings"
    (let ((text (format nil "a~C~Cb~Cc~C"
                        #\Return #\Newline #\Return #\Newline)))
      (expect (format nil "a~%b~%c~%") :to-equal (nshell.presentation::normalize-paste-text text))
      (expect (nshell.presentation::normalize-paste-text nil) :to-be-null)
      (expect (nshell.presentation::normalize-paste-text :not-a-string) :to-be-null)))

  (it "pbt-input-state-paste-normalizes-newlines-at-cursor"
    (check-property (:trials 50)
        ((prefix (gen-prompt-text :max-length 16) #'shrink-prompt-text)
         (suffix (gen-prompt-text :max-length 16) #'shrink-prompt-text)
         (left (gen-shell-word :min-length 1 :max-length 8)
               #'shrink-shell-word)
         (right (gen-shell-word :min-length 1 :max-length 8)
                #'shrink-shell-word)
         (separator-seed (gen-in-range 0 2) nil))
      (let* ((separator (case separator-seed
                          (0 (format nil "~C~C" #\Return #\Newline))
                          (1 (string #\Return))
                          (otherwise (string #\Newline))))
             (paste-text (concatenate 'string left separator right))
             (normalized-paste (concatenate 'string left
                                            (string #\Newline)
                                            right))
             (buffer (concatenate 'string prefix suffix))
             (state (input-state
                     :buffer buffer
                     :cursor-pos (length prefix))))
        (with-reduced-input-state (new-state output)
            (reduce-once state :paste nil nil
                         (list :protocol :bracketed :text paste-text))
          (and (eq :suggest-update output)
               (string= (concatenate 'string prefix normalized-paste suffix)
                        (nshell.presentation:input-state-buffer new-state))
               (= (+ (length prefix) (length normalized-paste))
                  (nshell.presentation:input-state-cursor-pos new-state)))))))

  (it "input-state-paste-is-capped-at-buffer-limit"
    (let* ((limit 4096)
           (buffer (make-string 4094 :initial-element #\x))
           (state (input-state
                   :buffer buffer
                   :cursor-pos 4094)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :paste nil nil
                       '(:protocol :bracketed :text "abcdef"))
          :suggest-update
          (:buffer (concatenate 'string buffer "ab")
           :cursor-pos limit)
        (expect limit :to-equal (length (nshell.presentation:input-state-buffer new-state)))))))
