(in-package #:nshell/test)

(describe "key-event-value-tests"
  (it "constructs decoded events with defaults and structured payloads"
    (let ((default (nshell.domain.input:make-key-event :char))
          (event (nshell.domain.input:make-key-event
                  :mouse #\x 7 '(:button 1))))
      (expect :char :to-be
              (nshell.domain.input:key-event-type default))
      (expect (nshell.domain.input:key-event-data default)
              :to-be-null)
      (expect :mouse :to-be
              (nshell.domain.input:key-event-type event))
      (expect #\x :to-be
              (nshell.domain.input:key-event-char event))
      (expect 7 :to-be
              (nshell.domain.input:key-event-number event))
      (expect '(:button 1) :to-equal
              (nshell.domain.input:key-event-data event))))

  (it "rejects non-character key payloads"
    (let ((invalid-value (read-from-string "\"x\"")))
      (expect (lambda ()
                (nshell.domain.input:make-key-event :char invalid-value))
              :to-throw 'type-error))))

(describe "input-state-tests"
  (it "input-state-constructor-macro-expands-defaults-and-keywords"
    (let ((expansion
            (macroexpand-1
             '(nshell.presentation::define-input-state-constructor
                ((alpha nil) (beta 42))))))
      (expect 'defun :to-be (first expansion))
      (expect 'nshell.presentation::make-input-state :to-be (second expansion))
      (expect '(&key alpha (beta 42)) :to-equal (third expansion))
      (expect (fourth expansion)
              :to-equal
              '(nshell.presentation::%make-input-state
                :alpha alpha :beta beta))))

  (it "input-state-constructor-preserves-the-complete-data-record"
    (let ((expander (lambda (text) (concatenate 'string text "!")))
          (values '((:buffer . "line")
                    (:cursor-pos . 2)
                    (:completion-index . 4)
                    (:completion-base-buffer . "prefix")
                    (:completion-base-cursor . 1)
                    (:last-candidates . ("one" "two"))
                    (:suggestion . "suggested")
                    (:mode . :vi-c)
                    (:vi-count . 3)
                    (:vi-visual-anchor . 1)
                    (:mouse-selection-anchor . 0)
                    (:mouse-selection-end . 2)
                    (:abbreviation-expander . :expander)
                    (:kill-ring . ("cut"))
                    (:last-yank-start . 1)
                    (:last-yank-end . 2)
                    (:last-yank-index . 0)
                    (:last-argument-start . 3)
                    (:last-argument-end . 4)
                    (:last-argument-index . 1)
                    (:search-query . "query")
                    (:search-original-buffer . "origin")
                    (:search-original-cursor . 5)
                    (:search-index . 6)
                    (:undo-stack . (:undo))
                    (:redo-stack . (:redo)))))
      (let ((state (apply #'nshell.presentation:make-input-state
                          (loop for (key . value) in values
                                append (list key (if (eq value :expander)
                                                     expander
                                                     value))))))
        (dolist (entry values)
          (let* ((key (car entry))
                 (expected (if (eq (cdr entry) :expander)
                               expander
                               (cdr entry)))
                 (accessor (find-symbol
                            (format nil "INPUT-STATE-~A"
                                    (substitute #\- #\_ (symbol-name key)))
                            '#:nshell.presentation)))
            (expect expected :to-equal (funcall accessor state)))))
      (let ((defaults (nshell.presentation:make-input-state)))
        (expect "" :to-equal (nshell.presentation:input-state-buffer defaults))
        (expect 0 :to-equal (nshell.presentation:input-state-cursor-pos defaults))
        (expect -1 :to-equal (nshell.presentation:input-state-completion-index defaults))
        (expect :insert :to-be (nshell.presentation:input-state-mode defaults))
        (expect "" :to-equal (nshell.presentation:input-state-search-query defaults))
        (expect 0 :to-equal (nshell.presentation:input-state-search-index defaults)))))

  (it "input-state-raw-constructor-is-internal-boundary"
    (let ((state (nshell.presentation:make-input-state :buffer "abc" :cursor-pos 2)))
      (expect (nshell.presentation:input-state-p state) :to-be-truthy)
      (expect "abc" :to-equal (nshell.presentation:input-state-buffer state))
      (expect 2 :to-equal (nshell.presentation:input-state-cursor-pos state))
      (expect :insert :to-be (nshell.presentation:input-state-mode state))
      (expect (fboundp 'nshell.presentation::%make-input-state) :to-be-truthy)))

  (it "input-state-normalization-clamps-cursor-to-buffer"
    (dolist (case '(("abc" . -1) ("abc" . 99) ("" . 4)))
      (let* ((buffer (car case))
             (cursor (cdr case))
             (state (nshell.presentation:make-input-state
                     :buffer buffer :cursor-pos cursor))
             (normalized (nshell.presentation::normalize-input-state state)))
        (expect buffer :to-equal
                (nshell.presentation:input-state-buffer normalized))
        (expect (max 0 (min cursor (length buffer))) :to-equal
                (nshell.presentation:input-state-cursor-pos normalized)))))

  (it "input-state-copy-groups-resolve-overrides-into-initargs"
    "The copy machinery is exactly override helpers plus per-group initarg
builders: it resolves each (SUPPLIED-P VALUE) override against the current state
and returns MAKE-INPUT-STATE plists directly, with no intermediate value record."
    (flet ((present-p (name)
             (multiple-value-bind (symbol status)
                 (find-symbol name '#:nshell.presentation)
               (and status symbol (or (fboundp symbol)
                                      (find-class symbol nil))))))
      (dolist (absent-name '(;; earlier hand-rolled plist/resolver names
                             "%COPY-INPUT-STATE-COMPLETION-PLIST"
                             "%COPY-INPUT-STATE-TRANSIENT-PLIST"
                             "%COPY-INPUT-STATE-SESSION-PLIST"
                             "%COPY-INPUT-STATE-OR-CURRENT"
                             "%COPY-INPUT-STATE-CLEARABLE-OR-CURRENT"
                             "%COPY-INPUT-STATE-CLEARABLE-VALUE-OR-CURRENT"
                             "%COPY-INPUT-STATE-CLAMPED-ANCHOR-OR-CURRENT"
                             "INPUT-STATE-COPY-OVERRIDE"
                             ;; the intermediate value records and their builders,
                             ;; now collapsed straight into the initarg builders
                             "%COPY-INPUT-STATE-COMPLETION-VALUES"
                             "%COPY-INPUT-STATE-TRANSIENT-VALUES"
                             "%COPY-INPUT-STATE-SESSION-VALUES"
                             "%COPY-INPUT-STATE-INITARGS"
                             "%INPUT-STATE-COPY-SPEC"
                             "%INPUT-STATE-COMPLETION-COPY"
                             "%INPUT-STATE-TRANSIENT-COPY"
                             "%INPUT-STATE-SESSION-COPY"))
        (expect (present-p absent-name) :to-be-falsy))
      (dolist (present-name '("%COPY-INPUT-STATE-COMPLETION-INITARGS"
                              "%COPY-INPUT-STATE-TRANSIENT-INITARGS"
                              "%COPY-INPUT-STATE-SESSION-INITARGS"
                              "%INPUT-STATE-COPY-OVERRIDE"
                              "%MAKE-INPUT-STATE-COPY-OVERRIDE"
                              "INPUT-STATE-COPY-OVERRIDE-KIND"
                              "INPUT-STATE-COPY-OVERRIDE-VALUE"
                              "INPUT-STATE-COPY-OVERRIDE-FOR"
                              "INPUT-STATE-COPY-OPTIONAL-VALUE-OVERRIDE"
                              "INPUT-STATE-COPY-OVERRIDE-RESOLVE"
                              "INPUT-STATE-COPY-ANCHOR-OVERRIDE-RESOLVE"))
        (expect (present-p present-name) :to-be-truthy))))

  (it "input-state-copy-override-values-resolve-copy-decisions"
    (let ((current (nshell.presentation::input-state-copy-override-for nil "ignored"))
          (clear (nshell.presentation::input-state-copy-override-for t :clear))
          (value (nshell.presentation::input-state-copy-override-for t "new"))
          (optional-current
            (nshell.presentation::input-state-copy-optional-value-override nil)))
      (expect (nshell.presentation::%input-state-copy-override-p current) :to-be-truthy)
      (expect (fboundp 'nshell.presentation::input-state-copy-override-p) :to-be-falsy)
      (expect :current :to-be (nshell.presentation::input-state-copy-override-kind current))
      (expect :clear :to-be (nshell.presentation::input-state-copy-override-kind clear))
      (expect :value :to-be (nshell.presentation::input-state-copy-override-kind value))
      (expect "old" :to-equal (nshell.presentation::input-state-copy-override-resolve
                    current
                    "old"))
      (expect (nshell.presentation::input-state-copy-override-resolve
                 clear
                 "old") :to-be-null)
      (expect "new" :to-equal (nshell.presentation::input-state-copy-override-resolve
                    value
                    "old"
                    :acceptp #'stringp))
      (expect "old" :to-equal (nshell.presentation::input-state-copy-override-resolve
                    value
                    "old"
                    :acceptp #'integerp))
      (expect "new" :to-equal (nshell.presentation::input-state-copy-override-resolve
                    value
                    "old"))
      (expect :fallback :to-be
              (nshell.presentation::input-state-copy-override-resolve
               clear
               "old"
               :clear-value :fallback))
      (expect "old" :to-equal (nshell.presentation::input-state-copy-override-resolve
                    optional-current
                    "old"))
      (expect 3 :to-equal (nshell.presentation::input-state-copy-anchor-override-resolve
              (nshell.presentation::input-state-copy-override-for t 99)
              0
              "abc"))
      (expect 0 :to-equal (nshell.presentation::input-state-copy-anchor-override-resolve
              (nshell.presentation::input-state-copy-override-for t -1)
              0
              "abc"))
      (expect nil :to-be (nshell.presentation::input-state-copy-anchor-override-resolve
                           (nshell.presentation::input-state-copy-override-for nil 99)
                           nil
                           "abc"))))

  (it "input-state-copy-with-assembles-all-overridable-fields"
    "Every overridable field handed to COPY-INPUT-STATE-WITH flows through to the
rebuilt state, so the completion, transient, and session groups each assemble.
(VI-VISUAL-ANCHOR is clamped to the new buffer, unlike the raw internal record.)"
    (let* ((expander (lambda (value) value))
           (copy (nshell.presentation::copy-input-state-with
                  (input-state :buffer "abc" :cursor-pos 1)
                  :buffer "text"
                  :cursor-pos 2
                  :completion-index 3
                  :completion-base-buffer "base"
                  :completion-base-cursor 4
                  :last-candidates '("one" "two")
                  :suggestion "suggest"
                  :mode :vi-c
                  :vi-count 9
                  :vi-visual-anchor 3
                  :abbreviation-expander expander
                  :kill-ring '("kill")
                  :last-yank-start 1
                  :last-yank-end 2
                  :last-yank-index 3
                  :last-argument-start 4
                  :last-argument-end 5
                  :last-argument-index 6
                  :search-query "query"
                  :search-original-buffer "original"
                  :search-original-cursor 8
                  :search-index 11
                  :undo-stack '(:undo)
                  :redo-stack '(:redo))))
      (is-input-state copy
                      :buffer "text"
                      :cursor-pos 2
                      :completion-index 3
                      :completion-base-buffer "base"
                      :completion-base-cursor 4
                      :last-candidates '("one" "two")
                      :suggestion "suggest"
                      :mode :vi-c
                      :vi-visual-anchor 3
                      :kill-ring '("kill")
                      :last-argument-start 4
                      :last-argument-end 5
                      :last-argument-index 6
                      :search-query "query"
                      :search-original-buffer "original"
                      :search-original-cursor 8
                      :search-index 11)
      (expect 9 :to-equal (nshell.presentation::input-state-vi-count copy))
      (expect expander :to-equal
              (nshell.presentation::input-state-abbreviation-expander copy))
      (expect 1 :to-equal (nshell.presentation::input-state-last-yank-start copy))
      (expect 2 :to-equal (nshell.presentation::input-state-last-yank-end copy))
      (expect 3 :to-equal (nshell.presentation::input-state-last-yank-index copy))
      (expect '(:undo) :to-equal (nshell.presentation::input-state-undo-stack copy))
      (expect '(:redo) :to-equal (nshell.presentation::input-state-redo-stack copy))))

  (it "input-state-copy-with-preserves-and-clears-optional-fields"
    (let ((state (input-state
                  :buffer "abc"
                  :cursor-pos 1
                  :completion-index 2
                  :completion-base-buffer "base"
                  :completion-base-cursor 2
                  :last-candidates '("one" "two")
                  :suggestion "hint"
                  :mode :search
                  :vi-visual-anchor 3
                  :kill-ring '("kill")
                  :search-query "query"
                  :search-original-buffer "origin"
                  :search-original-cursor 4
                  :search-index 9)))
      (let ((preserved (nshell.presentation::copy-input-state-with
                        state
                        :search-index 10))
            (cleared (nshell.presentation::copy-input-state-with
                      state
                      :completion-base-buffer :clear
                      :completion-base-cursor :clear
                      :last-candidates :clear
                      :suggestion :clear
                      :vi-visual-anchor :clear
                      :kill-ring :clear
                      :search-query :clear
                      :search-original-buffer :clear
                      :search-original-cursor :clear)))
        (is-input-state preserved
                        :buffer "abc"
                        :cursor-pos 1
                        :completion-index 2
                        :completion-base-buffer "base"
                        :completion-base-cursor 2
                        :last-candidates '("one" "two")
                        :suggestion "hint"
                        :mode :search
                        :vi-visual-anchor 3
                        :kill-ring '("kill")
                        :search-query "query"
                        :search-original-buffer "origin"
                        :search-original-cursor 4
                        :search-index 10)
        (is-input-state cleared
                        :buffer "abc"
                        :cursor-pos 1
                        :completion-index 2
                        :completion-base-buffer nil
                        :completion-base-cursor nil
                        :last-candidates nil
                        :suggestion nil
                        :mode :search
                        :vi-visual-anchor nil
                        :kill-ring nil
                        :search-query ""
                        :search-original-buffer ""
                        :search-original-cursor nil
                        :search-index 9))))

  (it "input-state-copy-with-resets-completion-and-clamps-selection"
    (let* ((expander (lambda (text) text))
           (state (input-state
                   :buffer "abcdef"
                   :cursor-pos 6
                   :completion-index 2
                   :completion-base-buffer "prefix"
                   :completion-base-cursor 3
                   :mouse-selection-anchor 4
                   :mouse-selection-end 5
                   :abbreviation-expander expander))
           (copy (nshell.presentation::copy-input-state-with
                  state
                  :buffer "xy"
                  :completion-index -1
                  :mouse-selection-anchor 99
                  :mouse-selection-end -1)))
      (expect -1 :to-equal
              (nshell.presentation::input-state-completion-index copy))
      (expect nil :to-be
              (nshell.presentation::input-state-completion-base-buffer copy))
      (expect nil :to-be
              (nshell.presentation::input-state-completion-base-cursor copy))
      (expect 2 :to-equal
              (nshell.presentation::input-state-mouse-selection-anchor copy))
      (expect 0 :to-equal
              (nshell.presentation::input-state-mouse-selection-end copy))
      (expect expander :to-be
              (nshell.presentation::input-state-abbreviation-expander copy))))

  (it "input-edit-snapshot-is-private-value"
    (let* ((state (nshell.presentation:make-input-state :buffer "abc"
                                                        :cursor-pos 2))
           (snapshot (nshell.presentation::input-edit-snapshot state)))
      (expect (nshell.presentation::%input-edit-snapshot-p snapshot) :to-be-truthy)
      (expect (listp snapshot) :to-be-falsy)
      (expect "abc" :to-equal (nshell.presentation::%input-edit-snapshot-buffer snapshot))
      (expect 2 :to-equal (nshell.presentation::%input-edit-snapshot-cursor-pos snapshot))))

  (it "input-undo-stack-step-is-private-value"
    (let* ((base (nshell.presentation:make-input-state :buffer "ab"
                                                       :cursor-pos 2))
           (previous-state (nshell.presentation:make-input-state :buffer "a"
                                                                 :cursor-pos 1))
           (next-state (nshell.presentation:make-input-state :buffer "abc"
                                                             :cursor-pos 3))
           (previous (nshell.presentation::input-edit-snapshot previous-state))
           (next (nshell.presentation::input-edit-snapshot next-state))
           (undo-state (nshell.presentation::copy-input-state-with
                        base
                        :undo-stack (list previous)
                        :redo-stack nil))
           (redo-state (nshell.presentation::copy-input-state-with
                        base
                        :undo-stack nil
                        :redo-stack (list next)))
           (undo-step (nshell.presentation::undo-stack-step-for-direction
                       undo-state
                       :undo))
           (redo-step (nshell.presentation::undo-stack-step-for-direction
                       redo-state
                       :redo)))
      (expect (nshell.presentation::%undo-stack-step-p undo-step) :to-be-truthy)
      (expect (listp undo-step) :to-be-falsy)
      (expect previous :to-be (nshell.presentation::%undo-stack-step-snapshot undo-step))
      (expect (nshell.presentation::%undo-stack-step-undo-stack undo-step) :to-be-null)
      (expect 1 :to-equal (length (nshell.presentation::%undo-stack-step-redo-stack
                      undo-step)))
      (expect (nshell.presentation::%input-edit-snapshot-p
           (first (nshell.presentation::%undo-stack-step-redo-stack
                   undo-step))) :to-be-truthy)
      (expect (nshell.presentation::%undo-stack-step-p redo-step) :to-be-truthy)
      (expect (listp redo-step) :to-be-falsy)
      (expect next :to-be (nshell.presentation::%undo-stack-step-snapshot redo-step))
      (expect 1 :to-equal (length (nshell.presentation::%undo-stack-step-undo-stack
                      redo-step)))
      (expect (nshell.presentation::%undo-stack-step-redo-stack redo-step) :to-be-null)
      (expect (fboundp 'nshell.presentation::make-undo-stack-step) :to-be-falsy)))

  (it "input-undo-recording-step-is-private-value"
    (let* ((old-state (nshell.presentation:make-input-state :buffer "ab"
                                                            :cursor-pos 2))
           (new-state (nshell.presentation:make-input-state :buffer "abc"
                                                            :cursor-pos 3))
           (existing-state (nshell.presentation:make-input-state :buffer "a"
                                                                 :cursor-pos 1))
           (redo-state (nshell.presentation:make-input-state :buffer "abcd"
                                                             :cursor-pos 4))
           (existing (nshell.presentation::input-edit-snapshot existing-state))
           (redo (nshell.presentation::input-edit-snapshot redo-state))
           (new-state-with-history
             (nshell.presentation::copy-input-state-with
              new-state
              :undo-stack (list existing)
              :redo-stack (list redo)))
           (recorded-transition
             (nshell.presentation::undo-recording-transition
              old-state
              new-state-with-history
              :suggest-update
              (input-key-event :char #\c)))
           (ignored-transition
             (nshell.presentation::undo-recording-transition
              old-state
              new-state-with-history
              :suggest-update
              (input-key-event :ctrl-underscore)))
           (step (nshell.presentation::undo-recording-step-for-transition
                  recorded-transition))
           (recorded (nshell.presentation::apply-undo-recording-step
                       new-state-with-history
                       step))
           (ignored (nshell.presentation::undo-recording-step-for-transition
                     ignored-transition)))
      (expect (nshell.presentation::%undo-recording-transition-p
           recorded-transition) :to-be-truthy)
      (expect (listp recorded-transition) :to-be-falsy)
      (expect (nshell.presentation::%undo-recording-step-p step) :to-be-truthy)
      (expect (listp step) :to-be-falsy)
      (expect 2 :to-equal (length (nshell.presentation::%undo-recording-step-undo-stack
                      step)))
      (expect "ab" :to-equal (nshell.presentation::%input-edit-snapshot-buffer
                    (first (nshell.presentation::%undo-recording-step-undo-stack
                            step))))
      (expect existing :to-be (second (nshell.presentation::%undo-recording-step-undo-stack
                       step)))
      (expect (nshell.presentation::%undo-recording-step-redo-stack step) :to-be-null)
      (expect 2 :to-equal (length (nshell.presentation::input-state-undo-stack recorded)))
      (expect (nshell.presentation::input-state-redo-stack recorded) :to-be-null)
      (expect ignored :to-be-null)
      (expect (fboundp 'nshell.presentation::make-undo-recording-transition) :to-be-falsy)
      (expect (fboundp 'nshell.presentation::make-undo-recording-step) :to-be-falsy)))
  (it "input-state-defaults-are-stable"
    "Calling the public constructor and copy operation without overrides supplies a usable empty editing state."
    (let* ((state (nshell.presentation:make-input-state))
           (copy (nshell.presentation::copy-input-state-with state)))
      (expect "" :to-equal
              (nshell.presentation:input-state-buffer state))
      (expect 0 :to-equal
              (nshell.presentation:input-state-cursor-pos state))
      (expect -1 :to-equal
              (nshell.presentation::input-state-completion-index state))
      (expect :insert :to-be
              (nshell.presentation:input-state-mode state))
      (expect "" :to-equal
              (nshell.presentation::input-state-search-query state))
      (expect "" :to-equal
              (nshell.presentation::input-state-search-original-buffer state))
      (expect 0 :to-equal
              (nshell.presentation::input-state-search-index state))
      (expect (eq state copy) :to-be-falsy)
      (expect "" :to-equal
              (nshell.presentation:input-state-buffer copy))
      (expect 0 :to-equal
              (nshell.presentation:input-state-cursor-pos copy))
      (expect :insert :to-be
              (nshell.presentation:input-state-mode copy)))))
