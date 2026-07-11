(in-package #:nshell/test)

(in-suite input-state-tests)

(test pbt-input-state-ctrl-u-then-yank-restores-buffer
  "Killing the prefix and yanking it back preserves generated line text."
  (check-property (:trials 50)
      ((line (gen-prompt-text :max-length 24) #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil))
    (let* ((cursor (min cursor-seed (length line)))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor)))
      (with-kill-then-yank (killed yanked) state :ctrl-u
        (declare (ignore killed))
        (and (string= line (nshell.presentation:input-state-buffer yanked))
             (= cursor
                (nshell.presentation:input-state-cursor-pos yanked)))))))

(test pbt-input-state-ctrl-k-then-yank-restores-buffer
  "Killing the suffix and yanking it back preserves generated line text."
  (check-property (:trials 50)
      ((line (gen-prompt-text :max-length 24) #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil))
    (let* ((cursor (min cursor-seed (length line)))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor)))
      (with-kill-then-yank (killed yanked) state :ctrl-k
        (let ((killed-text
                (first (nshell.presentation:input-state-kill-ring killed))))
          (and (string= line (nshell.presentation:input-state-buffer yanked))
               (= (+ cursor (length (or killed-text "")))
                  (nshell.presentation:input-state-cursor-pos yanked))))))))

(test pbt-input-state-alt-backspace-then-yank-restores-buffer
  "Meta-backspace kills a suffix of the prefix and yank restores it."
  (check-property (:trials 50)
      ((line (gen-prompt-text :max-length 24) #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil))
    (let* ((cursor (min cursor-seed (length line)))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor)))
      (with-kill-then-yank (killed yanked) state :alt-backspace
        (declare (ignore killed))
        (and (string= line (nshell.presentation:input-state-buffer yanked))
             (= cursor
                (nshell.presentation:input-state-cursor-pos yanked)))))))

(test pbt-input-state-alt-d-then-yank-restores-buffer
  "Meta-D kills a prefix of the suffix and yank restores it."
  (check-property (:trials 50)
      ((line (gen-prompt-text :max-length 24) #'shrink-prompt-text)
       (cursor-seed (gen-in-range 0 24) nil))
    (let* ((cursor (min cursor-seed (length line)))
           (state (input-state
                   :buffer line
                   :cursor-pos cursor)))
      (with-kill-then-yank (killed yanked) state :alt-d
        (let ((killed-text
                (first (nshell.presentation:input-state-kill-ring killed))))
          (and (string= line (nshell.presentation:input-state-buffer yanked))
               (= (+ cursor (length (or killed-text "")))
                  (nshell.presentation:input-state-cursor-pos yanked))))))))

(test pbt-input-state-alt-d-kills-one-escaped-space-token
  "Meta-D treats an escaped space as token content instead of splitting the token."
  (check-property (:trials 50)
      ((left (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
       (right (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
       (tail (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word))
    (let* ((token (format nil "~a\\ ~a" left right))
           (line (format nil "echo ~a ~a" token tail))
           (state (input-state :buffer line :cursor-pos 4)))
      (multiple-value-bind (killed output) (reduce-once state :alt-d)
        (and (eq :suggest-update output)
             (string= (format nil "echo ~a" tail)
                      (nshell.presentation:input-state-buffer killed))
             (equal (list (format nil " ~a" token))
                    (nshell.presentation:input-state-kill-ring killed)))))))

(test pbt-input-state-alt-d-then-yank-restores-operator-token
  "Meta-D at a shell operator kills through the following token and yank restores it."
  (check-property (:trials 50)
      ((left (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
       (right (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
       (operator-seed (gen-in-range 0 4) nil))
    (let* ((operators "|;&<>")
           (operator (char operators operator-seed))
           (line (format nil "~a~a~a" left operator right))
           (cursor (length left))
           (state (input-state :buffer line :cursor-pos cursor)))
      (with-kill-then-yank (killed yanked output yank-output) state :alt-d
        (let ((killed-text
                (first (nshell.presentation:input-state-kill-ring killed))))
          (and (eq :suggest-update output)
               (eq :suggest-update yank-output)
               (string= (format nil "~a~a" operator right)
                        killed-text)
               (string= line
                        (nshell.presentation:input-state-buffer yanked))
               (= (+ cursor (length killed-text))
                  (nshell.presentation:input-state-cursor-pos yanked))))))))

(test pbt-input-state-alt-y-replaces-last-yank-with-next-kill
  "Yank-pop replaces the recorded yank range with the next kill-ring entry."
  (check-property (:trials 50)
      ((prefix (gen-prompt-text :min-length 0 :max-length 12)
               #'shrink-prompt-text)
       (first-kill (gen-shell-word :min-length 1 :max-length 10)
                   #'shrink-prompt-text)
       (second-kill (gen-shell-word :min-length 1 :max-length 10)
                    #'shrink-prompt-text))
    (let ((state (input-state
                  :buffer prefix
                  :cursor-pos (length prefix)
                  :kill-ring (list first-kill second-kill))))
      (multiple-value-bind (yanked) (reduce-once state :ctrl-y)
        (multiple-value-bind (popped output) (reduce-once yanked :alt-y)
          (and (eq :suggest-update output)
               (string= (concatenate 'string prefix second-kill)
                        (nshell.presentation:input-state-buffer popped))
               (= (+ (length prefix) (length second-kill))
                  (nshell.presentation:input-state-cursor-pos popped))))))))
