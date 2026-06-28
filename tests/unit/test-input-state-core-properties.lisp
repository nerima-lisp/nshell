(in-package #:nshell/test)

(in-suite input-state-tests)

(test pbt-input-state-ctrl-l-preserves-buffer-and-cursor
  "Ctrl-L is a display request; it must not edit the current line."
  (check-property (:trials 50)
      ((line (gen-prompt-text :max-length 24) #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil))
    (let* ((cursor (min cursor-seed (length line)))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :ctrl-l)
          :clear-screen
          (:buffer line
           :cursor-pos cursor)))))

(test pbt-input-state-ctrl-l-preserves-session-state
  "Ctrl-L should preserve completion and suggestion session state while clearing the screen."
  (check-property (:trials 50)
      ((line (gen-prompt-text :max-length 24) #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil)
       (suggestion (gen-prompt-text :min-length 1 :max-length 12)
                   #'shrink-prompt-text)
       (candidate-a (gen-shell-word :min-length 1 :max-length 8)
                    #'shrink-prompt-text)
       (candidate-b (gen-shell-word :min-length 1 :max-length 8)
                    #'shrink-prompt-text)
       (candidate-c (gen-shell-word :min-length 1 :max-length 8)
                    #'shrink-prompt-text)
       (completion-index (gen-in-range 0 2) nil))
    (let* ((cursor (min cursor-seed (length line)))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor
                   :completion-index completion-index
                   :completion-base-buffer line
                   :completion-base-cursor cursor
                   :last-candidates (list candidate-a candidate-b candidate-c)
                   :suggestion suggestion)))
      (with-expected-input-state-reduction (new-state output)
          state
          (reduce-once state :ctrl-l)
          :clear-screen
          (:buffer line
           :cursor-pos cursor
           :completion-index completion-index
           :completion-base-buffer line
           :completion-base-cursor cursor
           :last-candidates (list candidate-a candidate-b candidate-c)
           :suggestion suggestion)))))

(test pbt-input-state-word-navigation-respects-shell-token-boundaries
  "Word navigation treats escaped and quoted spaces as token content."
     (check-property (:trials 50)
         ((command (gen-shell-word :min-length 1 :max-length 8)
                   #'shrink-prompt-text)
          (left (gen-shell-word :min-length 1 :max-length 8)
                #'shrink-prompt-text)
          (right (gen-shell-word :min-length 1 :max-length 8)
                 #'shrink-prompt-text)
          (tail (gen-shell-word :min-length 1 :max-length 8)
                #'shrink-prompt-text))
       (let* ((escaped-token (format nil "~a\\ ~a" left right))
              (quoted-token (format nil "\"~a ~a\"" left right))
              (escaped-line (format nil "~a ~a ~a" command escaped-token tail))
              (quoted-line (format nil "~a ~a ~a" command quoted-token tail))
              (start (1+ (length command)))
              (escaped-next-start (+ start (length escaped-token) 1))
              (quoted-next-start (+ start (length quoted-token) 1))
              (escaped-state (input-state
                              :buffer escaped-line
                              :cursor-pos start))
              (quoted-state (input-state
                             :buffer quoted-line
                             :cursor-pos start)))
         (and (with-reduced-input-states escaped-state
                  (((right-state right-output) :alt-right)
                   ((left-state left-output) :alt-left))
                (and (eq :redraw right-output)
                     (eq :redraw left-output)
                     (string= escaped-line
                              (nshell.presentation:input-state-buffer right-state))
                     (string= escaped-line
                              (nshell.presentation:input-state-buffer left-state))
                     (= escaped-next-start
                        (nshell.presentation:input-state-cursor-pos right-state))
                     (= start
                        (nshell.presentation:input-state-cursor-pos left-state))))
              (with-reduced-input-states quoted-state
                  (((right-state right-output) :alt-right)
                   ((left-state left-output) :alt-left))
                (and (eq :redraw right-output)
                     (eq :redraw left-output)
                     (string= quoted-line
                              (nshell.presentation:input-state-buffer right-state))
                     (string= quoted-line
                              (nshell.presentation:input-state-buffer left-state))
                     (= quoted-next-start
                        (nshell.presentation:input-state-cursor-pos right-state))
                     (= start
                        (nshell.presentation:input-state-cursor-pos left-state))))))))

(test pbt-input-state-word-navigation-respects-shell-operator-boundaries
  "Word navigation skips shell operators as token separators."
  (check-property (:trials 50)
      ((left (gen-shell-word :min-length 1 :max-length 8)
             #'shrink-prompt-text)
       (right (gen-shell-word :min-length 1 :max-length 8)
              #'shrink-prompt-text)
       (operator-seed (gen-in-range 0 4) nil))
    (if (or (string= left "")
            (string= right ""))
        t
        (let* ((operators "|;&<>")
               (operator (char operators operator-seed))
               (line (format nil "~a~c~a" left operator right))
               (left-end (length left))
               (right-start (1+ left-end))
               (state (input-state
                       :buffer line
                       :cursor-pos 0))
               (operator-state (input-state
                                :buffer line
                                :cursor-pos left-end)))
          (with-reduced-input-states state
              (((right-start-state right-start-output) :alt-right)
               ((left-start-state left-start-output) :alt-left))
            (with-reduced-input-state (operator-right-state operator-right-output)
                (reduce-once operator-state :alt-right)
              (and (eq :redraw right-start-output)
                   (eq :redraw operator-right-output)
                   (eq :redraw left-start-output)
                   (= right-start
                      (nshell.presentation:input-state-cursor-pos right-start-state))
                   (= right-start
                      (nshell.presentation:input-state-cursor-pos operator-right-state))
                   (= 0
                      (nshell.presentation:input-state-cursor-pos left-start-state))
                   (string= line
                            (nshell.presentation:input-state-buffer left-start-state)))))))))

(test input-state-buffer-never-exceeds-reasonable-size
  (let* ((limit 4096)
         (buffer (make-string limit :initial-element #\x))
         (state (input-state :buffer buffer :cursor-pos limit)))
    (with-expected-input-state-reduction (new-state output)
        state
        (reduce-once state :char #\y)
        :none
        (:buffer buffer
         :cursor-pos limit))))

(test pbt-input-state-end-at-eol-accepts-entire-suggestion
  "End at the line tail accepts the complete autosuggestion suffix."
  (check-property (:trials 50)
      ((prefix (gen-prompt-text :max-length 24) #'shrink-prompt-text)
       (suffix (gen-prompt-text :min-length 1 :max-length 12)
               #'shrink-prompt-text))
    (let ((state (input-state
                  :buffer prefix
                  :cursor-pos (length prefix)
                  :suggestion suffix)))
      (with-reduced-input-state (new-state output) (reduce-once state :end)
        (let ((expected (concatenate 'string prefix suffix)))
          (and (eq :suggest-update output)
               (string= expected
                        (nshell.presentation:input-state-buffer new-state))
               (= (length expected)
                  (nshell.presentation:input-state-cursor-pos new-state))
               (null (nshell.presentation:input-state-suggestion new-state))))))))

(test pbt-input-state-ctrl-e-matches-end-for-suggestion-acceptance
  "Ctrl-E and End share line-end autosuggestion behavior."
  (check-property (:trials 50)
      ((prefix (gen-prompt-text :max-length 24) #'shrink-prompt-text)
       (suffix (gen-prompt-text :min-length 1 :max-length 12)
               #'shrink-prompt-text))
    (let ((state (input-state
                  :buffer prefix
                  :cursor-pos (length prefix)
                  :suggestion suffix)))
      (with-reduced-input-state (end-state end-output) (reduce-once state :end)
        (with-reduced-input-state (ctrl-e-state ctrl-e-output)
            (reduce-once state :ctrl-e)
          (and (eq end-output ctrl-e-output)
               (string= (nshell.presentation:input-state-buffer end-state)
                        (nshell.presentation:input-state-buffer ctrl-e-state))
               (= (nshell.presentation:input-state-cursor-pos end-state)
                  (nshell.presentation:input-state-cursor-pos ctrl-e-state))
               (equal (nshell.presentation:input-state-suggestion end-state)
                      (nshell.presentation:input-state-suggestion ctrl-e-state))))))))

(test pbt-input-state-cursor-navigation-clears-autosuggestion
  "Cursor navigation clears autosuggestion state without editing the buffer."
  (check-property (:trials 50)
      ((line (gen-prompt-text :max-length 24) #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil)
       (suggestion (gen-prompt-text :min-length 1 :max-length 12)
                   #'shrink-prompt-text))
    (let* ((cursor (min cursor-seed (length line)))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor
                   :suggestion suggestion)))
      (loop :for key :in '(:left :home :ctrl-b :ctrl-a)
            :always
            (with-reduced-input-state (new-state output)
                (reduce-once state key)
              (and (member output '(:suggest-update :none :redraw) :test #'eq)
                   (string= line (nshell.presentation:input-state-buffer new-state))
                   (null (nshell.presentation:input-state-suggestion new-state))
                   (<= 0 (nshell.presentation:input-state-cursor-pos new-state))
                   (<= (nshell.presentation:input-state-cursor-pos new-state)
                       (length line))))))))

(test pbt-input-state-right-and-ctrl-f-share-insert-mode-navigation
  "Right and Ctrl-F must stay aligned in insert mode across the EOL boundary."
  (check-property (:trials 50)
      ((line (gen-prompt-text :max-length 24) #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil)
       (suggestion (gen-prompt-text :min-length 1 :max-length 12)
                   #'shrink-prompt-text))
    (let* ((cursor (min cursor-seed (length line)))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor
                   :suggestion suggestion)))
      (with-reduced-input-state (right-state right-output)
          (reduce-once state :right)
        (with-reduced-input-state (ctrl-f-state ctrl-f-output)
            (reduce-once state :ctrl-f)
          (and (eq right-output ctrl-f-output)
               (string= (nshell.presentation:input-state-buffer right-state)
                        (nshell.presentation:input-state-buffer ctrl-f-state))
               (= (nshell.presentation:input-state-cursor-pos right-state)
                  (nshell.presentation:input-state-cursor-pos ctrl-f-state))
               (equal (nshell.presentation:input-state-suggestion right-state)
                      (nshell.presentation:input-state-suggestion ctrl-f-state))))))))

