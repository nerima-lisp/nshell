(in-package #:nshell/test)
(in-suite input-state-tests)

(test pbt-input-state-end-and-ctrl-e-only-accept-suggestion-at-eol
  "End and Ctrl-E preserve autosuggestions until the cursor is already at EOL."
  (check-property (:trials 50)
      ((line (gen-prompt-text :min-length 1 :max-length 24)
             #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil)
       (suggestion (gen-prompt-text :min-length 1 :max-length 12)
                   #'shrink-prompt-text))
    (let* ((cursor (min cursor-seed (length line)))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor
                   :suggestion suggestion)))
      (with-reduced-input-state (end-state end-output) (reduce-once state :end)
        (with-reduced-input-state (ctrl-e-state ctrl-e-output)
            (reduce-once state :ctrl-e)
          (let ((at-eol (= cursor (length line))))
            (and (eq end-output ctrl-e-output)
                 (string= (nshell.presentation:input-state-buffer end-state)
                          (nshell.presentation:input-state-buffer ctrl-e-state))
                 (if at-eol
                     (and (= (length (concatenate 'string line suggestion))
                             (nshell.presentation:input-state-cursor-pos end-state))
                          (= (nshell.presentation:input-state-cursor-pos end-state)
                             (nshell.presentation:input-state-cursor-pos ctrl-e-state))
                          (null (nshell.presentation:input-state-suggestion end-state))
                          (null (nshell.presentation:input-state-suggestion ctrl-e-state))
                          (string= (concatenate 'string line suggestion)
                                   (nshell.presentation:input-state-buffer end-state)))
                     (and (= (length line)
                             (nshell.presentation:input-state-cursor-pos end-state))
                          (= (nshell.presentation:input-state-cursor-pos end-state)
                             (nshell.presentation:input-state-cursor-pos ctrl-e-state))
                          (string= line
                                   (nshell.presentation:input-state-buffer end-state))
                          (string= line
                                   (nshell.presentation:input-state-buffer ctrl-e-state))
                          (equal suggestion
                                 (nshell.presentation:input-state-suggestion end-state))
                          (equal suggestion
                                 (nshell.presentation:input-state-suggestion ctrl-e-state))))))))))

(test pbt-input-state-alt-right-accepts-compact-redirection
  "Autosuggestion word acceptance keeps compact redirections atomic."
  (check-property (:trials 50)
      ((prefix (gen-shell-command :min-words 1 :max-words 3
                                  :max-word-length 8)
               #'shrink-prompt-text)
       (fd (gen-in-range 0 9) nil)
       (target-fd (gen-in-range 0 9) nil)
       (target (gen-shell-word :min-length 1 :max-length 8)
               #'shrink-prompt-text)
       (style (gen-in-range 0 1) nil))
    (let* ((redirection
             (if (zerop style)
                 (format nil " ~d>&~d" fd target-fd)
                 (format nil " ~d>~a" fd target)))
           (tail " | cat")
           (suggestion (concatenate 'string redirection tail))
           (state (input-state
                   :buffer prefix
                   :cursor-pos (length prefix)
                   :suggestion suggestion)))
      (let ((expected (concatenate 'string prefix redirection)))
        (with-expected-input-state-reduction (new-state output)
            state
            (reduce-once state :alt-right)
            :suggest-update
            (:buffer expected
             :cursor-pos (length expected)
             :suggestion tail)))))

(test pbt-input-state-alt-s-twice-restores-buffer
  "Meta-S toggles a sudo command prefix without changing the command text after two presses."
  (check-property (:trials 50)
      ((line (gen-prompt-text :max-length 24) #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil))
    (if (string= line "sudo")
        t
        (let* ((cursor (min cursor-seed (length line)))
               (state (input-state
                       :buffer line
                       :cursor-pos cursor)))
          (with-reduced-input-states state
              (((prefixed) :alt-s)
               ((restored) :alt-s))
            (string= line
                     (nshell.presentation:input-state-buffer restored))))))))

(test pbt-input-state-ctrl-t-preserves-length-and-characters
  "Transpose edits only character order and keeps the cursor within the line."
  (check-property (:trials 50)
      ((line (gen-prompt-text :min-length 2 :max-length 24
                              :cjk-probability 0.15)
             #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil))
    (let* ((cursor (max 1 (min cursor-seed (length line))))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor)))
      (with-reduced-input-state (new-state output)
          (reduce-once state :ctrl-t)
        (let ((new-line (nshell.presentation:input-state-buffer new-state)))
          (and (eq :suggest-update output)
               (= (length line) (length new-line))
               (string= (sort (copy-seq line) #'char<)
                        (sort (copy-seq new-line) #'char<))
               (<= 0 (nshell.presentation:input-state-cursor-pos new-state))
               (<= (nshell.presentation:input-state-cursor-pos new-state)
                   (length new-line))))))))

(test pbt-input-state-alt-t-preserves-length-and-characters
  "Word transpose reorders existing characters and keeps the cursor in bounds."
  (check-property (:trials 50)
      ((line (gen-shell-command :min-words 2 :max-words 5
                                :max-word-length 8)
             #'shrink-prompt-text))
    (let ((state (input-state
                  :buffer line
                  :cursor-pos (length line))))
      (with-reduced-input-state (new-state output)
          (reduce-once state :alt-t)
        (let ((new-line (nshell.presentation:input-state-buffer new-state)))
          (and (eq :suggest-update output)
               (= (length line) (length new-line))
               (string= (sort (copy-seq line) #'char<)
                        (sort (copy-seq new-line) #'char<))
               (<= 0 (nshell.presentation:input-state-cursor-pos new-state))
               (<= (nshell.presentation:input-state-cursor-pos new-state)
                   (length new-line))))))))

(test pbt-input-state-alt-case-preserves-length-and-cursor-bounds
  "Word case transforms keep the line shape stable and the cursor in bounds."
  (check-property (:trials 50)
      ((line (gen-shell-command :min-words 1 :max-words 5
                                :max-word-length 8)
             #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 64) nil))
    (let* ((cursor (min cursor-seed (length line)))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor)))
      (loop :for key :in '(:alt-u :alt-l :alt-c)
            :always
            (with-reduced-input-state (new-state output)
                (reduce-once state key)
              (let ((new-line (nshell.presentation:input-state-buffer new-state))
                    (new-cursor
                      (nshell.presentation:input-state-cursor-pos new-state)))
                (and (member output '(:suggest-update :none) :test #'eq)
                     (= (length line) (length new-line))
                     (<= 0 new-cursor)
                     (<= new-cursor (length new-line)))))))))

(test pbt-input-state-undo-redo-roundtrips-typed-line
  "Undo walks typed edits back to an empty line; redo restores the line."
  (check-property (:trials 50)
      ((line (gen-prompt-text :max-length 24
                              :cjk-probability 0.15)
             #'shrink-prompt-text))
    (let* ((events (map 'list
                        (lambda (ch)
                          (input-key-event :char ch))
                        line))
           (typed (apply-key-events-to-input-state (input-state) events))
           (undone typed))
      (dotimes (_ (length line))
        (setf undone (reduce-once-state undone :ctrl-underscore)))
      (let ((redone undone))
        (dotimes (_ (length line))
          (setf redone (reduce-once-state redone :alt-r)))
        (and (string= "" (nshell.presentation:input-state-buffer undone))
             (= 0 (nshell.presentation:input-state-cursor-pos undone))
             (string= line (nshell.presentation:input-state-buffer redone))
             (= (length line)
                (nshell.presentation:input-state-cursor-pos redone)))))))

(test pbt-terminal-control-h-matches-backspace-edit
  "ASCII BS decoded from terminal input behaves like the reducer backspace key."
  (check-property (:trials 50)
      ((line (gen-prompt-text :max-length 24
                              :cjk-probability 0.15)
             #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil))
    (let* ((cursor (min cursor-seed (length line)))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor))
           (event (first (read-key-events-from-string
                          (string (code-char 8))))))
      (with-reduced-input-state (expected-state expected-output)
          (reduce-once state :backspace)
        (with-reduced-input-state (actual-state actual-output)
            (nshell.presentation:reduce-input-state state event)
          (and (eq expected-output actual-output)
               (string= (nshell.presentation:input-state-buffer expected-state)
                        (nshell.presentation:input-state-buffer actual-state))
               (= (nshell.presentation:input-state-cursor-pos expected-state)
                  (nshell.presentation:input-state-cursor-pos actual-state))))))))

(test pbt-terminal-ctrl-d-delete-or-quit-contract
  "Ctrl-D quits an empty prompt, otherwise it deletes the character under the cursor."
  (check-property (:trials 50)
      ((line (gen-prompt-text :max-length 24
                              :cjk-probability 0.15)
             #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil))
    (let* ((cursor (min cursor-seed (length line)))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor))
           (event (first (read-key-events-from-string
                          (string (code-char 4))))))
      (with-reduced-input-state (new-state output)
          (nshell.presentation:reduce-input-state state event)
        (cond
          ((zerop (length line))
           (and (eq :quit output)
                (string= "" (nshell.presentation:input-state-buffer new-state))
                (= 0 (nshell.presentation:input-state-cursor-pos new-state))))
          ((< cursor (length line))
           (let ((expected (concatenate 'string
                                        (subseq line 0 cursor)
                                        (subseq line (1+ cursor)))))
             (and (eq :suggest-update output)
                  (string= expected
                           (nshell.presentation:input-state-buffer new-state))
                  (= cursor
                     (nshell.presentation:input-state-cursor-pos new-state)))))
          (t
           (and (eq :none output)
                 (string= line (nshell.presentation:input-state-buffer new-state))
                 (= cursor
                    (nshell.presentation:input-state-cursor-pos new-state))))))))))
