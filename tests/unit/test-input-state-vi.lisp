(in-package #:nshell/test)

(in-suite input-state-tests)

;;; Vi-mode reducer behavior. ESC only enters vi normal mode when
;;; *VI-MODE-ENABLED* is true. Most tests start from a command-mode fixture.

(test vi-escape-enters-command-mode-and-moves-left
  (with-vi-command-state (cmd (input-state :buffer "echo hi" :cursor-pos 7))
    (is-vi-command-state cmd :cursor-pos 6)))

(test vi-escape-is-inert-without-vi-mode
  (let ((state (input-state :buffer "echo hi" :cursor-pos 7)))
    (with-reduced-input-state (after) (reduce-once state :escape)
      (is-input-state after :mode :insert :cursor-pos 7))))

(test vi-hl-motion-and-bounds
  (with-vi-command-state (cmd (input-state :buffer "abc" :cursor-pos 1))
    ;; ESC moved cursor 1 -> 0; l advances, h retreats, both clamped.
    (with-reduced-input-state (r1) (reduce-once cmd :char #\l)
      (is-input-state r1 :cursor-pos 1)
      (with-reduced-input-state (r2) (reduce-once r1 :char #\l)
        (is-input-state r2 :cursor-pos 2)
        ;; last column for "abc" in command mode is 2; cannot pass it.
        (with-reduced-input-state (r3) (reduce-once r2 :char #\l)
          (is-input-state r3 :cursor-pos 2)
        (with-reduced-input-state (r4) (reduce-once r3 :char #\h)
            (is-input-state r4 :cursor-pos 1)))))))

(test vi-line-jumps-0-and-dollar
  (with-vi-command-state (cmd (input-state :buffer "hello" :cursor-pos 2))
    (with-reduced-input-state (s0) (reduce-once cmd :char #\0)
      (is-input-state s0 :cursor-pos 0))
    (with-reduced-input-state (se) (reduce-once cmd :char #\$)
      (is-input-state se :cursor-pos 4))))

(test vi-i-returns-to-insert-mode
  (with-vi-command-state (cmd (input-state :buffer "abc" :cursor-pos 0))
    (with-reduced-input-state (ins) (reduce-once cmd :char #\i)
      (is-input-state ins :mode :insert))
    ;; A enters insert at end of line.
    (with-reduced-input-state (app) (reduce-once cmd :char #\A)
      (is-input-state app :mode :insert :cursor-pos 3))))

(test vi-x-deletes-character-under-cursor
  (with-vi-command-state (cmd (input-state :buffer "abc" :cursor-pos 0))
    (with-reduced-input-state (del) (reduce-once cmd :char #\x)
      (is-input-state del :buffer "bc" :mode :vi-command))))

(test vi-counted-motion-and-delete
  (with-vi-command-state (cmd (input-state :buffer "abcdef" :cursor-pos 1))
    ;; ESC moved cursor 1 -> 0; 3l advances three columns and 2h retreats two.
    (with-reduced-input-states cmd (((right) :char #\3)
                                    ((right) :char #\l)
                                    ((left) :char #\2)
                                    ((left) :char #\h))
      (is-vi-command-state right :cursor-pos 3)
      (is-vi-command-state left :cursor-pos 1))
    (with-reduced-input-states cmd (((counted) :char #\3)
                                    ((deleted) :char #\x))
      (is-input-state deleted
                      :buffer "def"
                      :cursor-pos 0
                      :mode :vi-command))))

(test vi-counted-word-motion-and-operator
  (with-vi-command-state (cmd (input-state :buffer "one two three four"
                                            :cursor-pos 1))
    (with-reduced-input-states cmd (((counted) :char #\2)
                                    ((moved) :char #\w))
      (is-vi-command-state moved :cursor-pos 8))
    (with-reduced-input-states cmd (((counted) :char #\2)
                                    ((pending) :char #\d)
                                    ((deleted) :char #\w))
      (is-input-state deleted
                      :buffer " three four"
                      :cursor-pos 0
                      :mode :vi-command))))

(test vi-dd-clears-line-and-cc-enters-insert
  (with-vi-command-state (cmd (input-state :buffer "hello world" :cursor-pos 3))
    ;; dd : two keystrokes delete the whole line.
    (with-reduced-input-state (pend) (reduce-once cmd :char #\d)
      (is-input-state pend :mode :vi-d)
      (with-reduced-input-state (cleared) (reduce-once pend :char #\d)
        (is-vi-command-state cleared :buffer "")))
    ;; cc : clear line and drop into insert mode.
    (with-reduced-input-state (cpend) (reduce-once cmd :char #\c)
      (with-reduced-input-state (changed) (reduce-once cpend :char #\c)
        (is-input-state changed :buffer "" :mode :insert)))))

(test vi-D-kills-to-end-of-line
  (let* ((base (input-state :buffer "hello world" :cursor-pos 6))
         ;; ESC moves cursor 6 -> 5 (the space); place it on 'w' via l.
         (on-w nil))
    (with-vi-command-state (cmd base)
      (setf on-w (reduce-once-state cmd :char #\l))
      (with-reduced-input-state (killed) (reduce-once on-w :char #\D)
        (is-vi-command-state killed :buffer "hello ")))))

(test vi-j-k-emit-history-navigation
  (with-vi-command-state (cmd (input-state :buffer "x" :cursor-pos 0))
    (multiple-value-bind (s out) (reduce-once cmd :char #\k)
      (declare (ignore s))
      (is (eq :history-prev out)))
    (multiple-value-bind (s out) (reduce-once cmd :char #\j)
      (declare (ignore s))
      (is (eq :history-next out)))))

(test vi-v-enters-visual-mode-with-anchor
  (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
    (is-vi-visual-state visual
                        :cursor-pos 0
                        :vi-visual-anchor 0)))

(test vi-visual-motion-and-escape-clears-anchor
  (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
    (with-reduced-input-states visual (((counted) :char #\2)
                                       ((moved) :char #\l)
                                       ((escaped) :escape))
      (is-vi-visual-state moved
                          :cursor-pos 2
                          :vi-visual-anchor 0)
      (is-vi-command-state escaped
                           :cursor-pos 2
                           :vi-visual-anchor nil))))

(test vi-visual-delete-is-inclusive-and-populates-kill-ring
  (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
    (with-reduced-input-states visual (((counted) :char #\2)
                                       ((moved) :char #\l)
                                       ((deleted) :char #\d))
      (is-input-state deleted
                      :buffer "def"
                      :cursor-pos 0
                      :mode :vi-command
                      :vi-visual-anchor nil
                      :kill-ring '("abc")))))

(test vi-visual-change-enters-insert-mode
  (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
    (with-reduced-input-states visual (((moved) :char #\l)
                                       ((changed) :char #\c))
      (is-input-state changed
                      :buffer "cdef"
                      :cursor-pos 0
                      :mode :insert
                      :vi-visual-anchor nil
                      :kill-ring '("ab")))))

(test vi-visual-yank-preserves-buffer-and-exits
  (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
    (with-reduced-input-states visual (((counted) :char #\2)
                                       ((moved) :char #\l)
                                       ((yanked) :char #\y))
      (is-input-state yanked
                      :buffer "abcdef"
                      :cursor-pos 0
                      :mode :vi-command
                      :vi-visual-anchor nil
                      :kill-ring '("abc")))))

(test vi-visual-o-swaps-anchor-and-cursor
  (with-vi-visual-state (cmd (input-state :buffer "abcdef" :cursor-pos 1) visual)
    (with-reduced-input-states visual (((counted) :char #\2)
                                       ((moved) :char #\l)
                                       ((swapped) :char #\o))
      (is-vi-visual-state swapped
                          :cursor-pos 0
                          :vi-visual-anchor 2))))
