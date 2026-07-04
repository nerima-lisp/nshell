(in-package #:nshell/test)

(in-suite input-state-tests)

(test input-state-inserting-char-updates-buffer
  (with-expected-input-state-reduction (new-state output)
      (input-state)
      (reduce-once (input-state) :char #\a)
      :suggest-update
      (:buffer "a" :cursor-pos 1)))

(test input-state-reducer-accepts-domain-key-events-directly
  (let ((event (nshell.domain.input:make-key-event :char #\x)))
    (with-expected-input-state-reduction (new-state output)
        (input-state)
        (nshell.presentation:reduce-input-state (input-state) event)
        :suggest-update
        (:buffer "x" :cursor-pos 1))))

(test key-event-raw-constructor-is-internal-boundary
  (let ((event (nshell.domain.input:make-key-event :char #\x)))
    (is (nshell.domain.input:key-event-p event))
    (is (eq :char (nshell.domain.input:key-event-type event)))
    (is (char= #\x (nshell.domain.input:key-event-char event)))
    (is (fboundp 'nshell.domain.input::%make-key-event))))

(test input-state-inserting-unicode-char-updates-buffer
  (let ((state (input-state :buffer "xy" :cursor-pos 1))
        (ch (char "あ" 0)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :char ch)
        :suggest-update
        (:buffer "xあy" :cursor-pos 2))))

(test input-state-buffer-splice-projects-insertion-result-and-cursor
  (let ((splice (nshell.presentation::make-buffer-splice 5 5 "hello ")))
    (is (string= "echo hello done"
                 (nshell.presentation::buffer-splice-result splice "echo done")))
    (is (= 11 (nshell.presentation::buffer-splice-cursor-pos splice)))))

(test input-state-buffer-splice-projects-deletion-result-and-cursor
  (let ((splice (nshell.presentation::make-buffer-splice 4 8)))
    (is (string= "git main"
                 (nshell.presentation::buffer-splice-result splice "git old main")))
    (is (= 4 (nshell.presentation::buffer-splice-cursor-pos splice)))))

(test input-state-buffer-insertion-projects-capped-result-and-cursor
  (let* ((buffer "echo  done")
         (insertion (nshell.presentation::buffer-insertion-at-cursor
                     buffer 5 "hello")))
    (is (nshell.presentation::buffer-insertion-p insertion))
    (is (not (fboundp 'nshell.presentation::make-buffer-insertion)))
    (is (string= "echo hello done"
                 (nshell.presentation::buffer-insertion-result
                  insertion
                  buffer)))
    (is (= 10 (nshell.presentation::buffer-insertion-cursor-pos
               insertion))))
  (let* ((limit 4096)
         (buffer (make-string 4094 :initial-element #\x))
         (insertion (nshell.presentation::buffer-insertion-at-cursor
                     buffer
                     4094
                     "abcdef")))
    (is (string= (concatenate 'string buffer "ab")
                 (nshell.presentation::buffer-insertion-result
                  insertion
                  buffer)))
    (is (= limit (nshell.presentation::buffer-insertion-cursor-pos
                  insertion)))))

(test input-state-buffer-insertion-rejects-non-insertions
  (let ((buffer (make-string 4096 :initial-element #\x)))
    (is (null (nshell.presentation::buffer-insertion-at-cursor
               "echo" 4 "")))
    (is (null (nshell.presentation::buffer-insertion-at-cursor
               "echo" 4 :not-a-string)))
    (is (null (nshell.presentation::buffer-insertion-at-cursor
               buffer 4096 "x")))))

(test input-state-buffer-deletion-projects-result-and-cursor
  (let* ((buffer "abcd")
         (before (nshell.presentation::buffer-deletion-before-cursor 2))
         (at (nshell.presentation::buffer-deletion-at-cursor buffer 1)))
    (is (nshell.presentation::buffer-deletion-p before))
    (is (nshell.presentation::buffer-deletion-p at))
    (is (fboundp 'nshell.presentation::%make-buffer-deletion))
    (is (fboundp 'nshell.presentation::%buffer-deletion-splice))
    (is (not (fboundp 'nshell.presentation::make-buffer-deletion)))
    (is (string= "acd"
                 (nshell.presentation::buffer-deletion-result before buffer)))
    (is (= 1 (nshell.presentation::buffer-deletion-cursor-pos before)))
    (is (string= "acd"
                 (nshell.presentation::buffer-deletion-result at buffer)))
    (is (= 1 (nshell.presentation::buffer-deletion-cursor-pos at)))))

(test input-state-buffer-deletion-rejects-empty-ranges
  (is (null (nshell.presentation::buffer-deletion-before-cursor 0)))
  (is (null (nshell.presentation::buffer-deletion-at-cursor "" 0)))
  (is (null (nshell.presentation::buffer-deletion-at-cursor "abc" 3))))

(test input-state-cursor-move-edit-projects-position-through-commit
  (let* ((state (input-state :buffer "abcdef"
                             :cursor-pos 3
                             :suggestion "def"))
         (edit (nshell.presentation::cursor-move-edit-by 3 2))
         (committed (nshell.presentation::commit-cursor-move-edit state edit)))
    (is (fboundp 'nshell.presentation::%make-cursor-move-edit))
    (is (fboundp 'nshell.presentation::%cursor-move-edit-cursor-pos))
    (is (not (fboundp 'nshell.presentation::make-cursor-move-edit)))
    (is (= 5 (nshell.presentation::cursor-move-edit-cursor-pos edit)))
    (is-input-state committed
                    :buffer "abcdef"
                    :cursor-pos 5
                    :suggestion nil))
  (let* ((state (input-state :buffer "abcdef"
                             :cursor-pos 3
                             :suggestion "def"))
         (edit (nshell.presentation::cursor-move-edit-to 99))
         (committed (nshell.presentation::commit-cursor-move-edit state edit)))
    (is-input-state committed
                    :buffer "abcdef"
                    :cursor-pos 6
                    :suggestion nil)))

(test input-state-space-expands-abbreviation-before-cursor
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

(test input-state-space-keeps-quoted-abbreviation-literal
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

(test input-state-operator-expands-abbreviation-before-cursor
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

(test input-state-abbreviation-expansion-treats-operators-as-token-boundaries
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

(test input-state-abbreviation-expansion-targets-current-token-only
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

(test input-state-abbreviation-expansion-respects-escaped-space-token
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

(test pbt-input-state-space-expands-current-abbreviation-token-only
  (check-property (:trials 50)
      ((token (gen-shell-word :min-length 1 :max-length 8) #'shrink-prompt-text)
       (tail (gen-shell-word :min-length 1 :max-length 8) #'shrink-prompt-text))
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
         (is-completion-session-cleared new-state)))))

(test input-state-paste-inserts-text-at-cursor
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

(test input-state-paste-normalizes-crlf-and-cr-newlines
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

(test input-state-paste-does-not-expand-abbreviation-and-undoes-once
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
      (is (eq :suggest-update paste-output))
      (with-reduced-input-state (undone undo-output)
          (reduce-once pasted :ctrl-underscore)
        (is-input-state undone :buffer "echo " :cursor-pos 5)
        (is (eq :suggest-update undo-output))))))

(test normalize-paste-text-normalizes-line-endings
  (let ((text (format nil "a~C~Cb~Cc~C"
                      #\Return #\Newline #\Return #\Newline)))
    (is (string= (format nil "a~%b~%c~%")
                 (nshell.presentation::normalize-paste-text text)))
    (is (null (nshell.presentation::normalize-paste-text nil)))
    (is (null (nshell.presentation::normalize-paste-text :not-a-string)))))

(test pbt-input-state-paste-normalizes-newlines-at-cursor
  (check-property (:trials 50)
      ((prefix (gen-prompt-text :max-length 16) #'shrink-prompt-text)
       (suffix (gen-prompt-text :max-length 16) #'shrink-prompt-text)
       (left (gen-shell-word :min-length 1 :max-length 8)
             #'shrink-prompt-text)
       (right (gen-shell-word :min-length 1 :max-length 8)
              #'shrink-prompt-text)
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

(test input-state-paste-is-capped-at-buffer-limit
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
      (is (= limit (length (nshell.presentation:input-state-buffer new-state)))))))
