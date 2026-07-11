;;; Vi edit/reduction logic split out from the base vi input state helpers.

(in-package #:nshell.presentation)

(defun %vi-enter-insert (state &optional position)
  (%vi-insert-state state :cursor-pos position))

(defun %vi-kill-into (state start end cursor end-mode)
  "Kill the buffer span [START, END) (recording it on the kill ring), leave the
cursor at CURSOR, and switch to END-MODE (:vi-command for d, :insert for c)."
  (multiple-value-bind (killed-state output)
      (%kill-range state (max 0 (min start end)) (max start end) cursor)
    (declare (ignore output))
    (values (if (eq end-mode :vi-command)
                (%vi-command-state killed-state :cursor-pos cursor)
                (%vi-insert-state killed-state :cursor-pos cursor))
            :redraw)))

(defun commit-vi-visual-kill-selection (state selection end-mode)
  (%vi-kill-into state
                 (vi-visual-selection-start selection)
                 (vi-visual-selection-end selection)
                 (vi-visual-selection-cursor selection)
                 end-mode))

(defun vi-operator-edit-for-motion (state ch op)
  (let* ((buffer (input-state-buffer state))
         (pos (input-state-cursor-pos state))
         (len (length buffer))
         (count (%vi-count state))
         (end-mode (if (eq op :c) :insert :vi-command))
         (self (if (eq op :c) #\c #\d)))
    (cond
      ((char= ch self)
       (%make-vi-operator-edit 0 len 0 end-mode))
      ((char= ch #\w)
       (%make-vi-operator-edit
        pos (%vi-counted-kill-word-end buffer pos count) pos end-mode))
      ((char= ch #\b)
       (let ((start (%vi-counted-kill-word-start buffer pos count)))
         (%make-vi-operator-edit start pos start end-mode)))
      ((char= ch #\$)
       (%make-vi-operator-edit
        pos len (if (eq op :c) pos (max 0 (1- pos))) end-mode))
      ((char= ch #\0)
       (%make-vi-operator-edit 0 pos 0 end-mode))
      (t nil))))

(defun commit-vi-operator-edit (state edit)
  (%vi-kill-into state
                 (vi-operator-edit-start edit)
                 (vi-operator-edit-end edit)
                 (vi-operator-edit-cursor edit)
                 (vi-operator-edit-end-mode edit)))

(defun %reduce-vi-normal (state ch)
  "Handle a single character CH in vi normal mode."
  (let ((pos (input-state-cursor-pos state))
        (len (%vi-buffer-length state))
        (count (%vi-count state)))
    (%vi-with-common-motion-cases (state ch pos len count)
      ;; Visual selection.
      ((#\v) (values (%vi-enter-visual state) :redraw))
      ;; Enter insert mode.
      ((#\i) (values (%vi-enter-insert state) :redraw))
      ((#\a) (values (%vi-enter-insert state (min len (1+ pos))) :redraw))
      ((#\I) (values (%vi-enter-insert state 0) :redraw))
      ((#\A) (values (%vi-enter-insert state len) :redraw))
      ;; Single-key edits.
      ((#\x) (if (< pos len)
                 (%vi-kill-into state pos (min len (+ pos count)) pos :vi-command)
                 (values state :none)))
      ((#\D) (%vi-kill-into state pos len (max 0 (1- pos)) :vi-command))
      ((#\C) (%vi-kill-into state pos len pos :insert))
      ((#\s) (%vi-kill-into state pos (min len (+ pos count)) pos :insert))
      ;; Operators: remember via a transient mode.
      ((#\d) (values (copy-input-state-with state :mode :vi-d) :redraw))
      ((#\c) (values (copy-input-state-with state :mode :vi-c) :redraw))
      ;; History.
      ((#\j) (%vi-values-clearing-count state :history-next))
      ((#\k) (%vi-values-clearing-count state :history-prev))
      (otherwise (values state :none)))))

(defun %reduce-vi-visual (state ch)
  "Handle a single character CH in vi char-wise visual mode."
  (let ((pos (input-state-cursor-pos state))
        (len (%vi-buffer-length state))
        (count (%vi-count state)))
    (%vi-with-common-motion-cases (state ch pos len count)
      ((#\v) (values (%vi-leave-visual state) :redraw))
      ((#\o) (%vi-swap-visual-anchor state))
      ((#\d #\x)
       (commit-vi-visual-kill-selection
        state (vi-visual-selection-for-state state) :vi-command))
      ((#\c #\s)
       (commit-vi-visual-kill-selection
        state (vi-visual-selection-for-state state) :insert))
      ((#\y)
       (commit-vi-visual-yank-selection
        state (vi-visual-selection-for-state state)))
      ((#\i) (values (%vi-enter-insert (%vi-leave-visual state)) :redraw))
      ((#\a) (values (%vi-enter-insert (%vi-leave-visual state)
                                       (min len (1+ pos)))
                     :redraw))
      (otherwise (values state :none)))))

(defun %reduce-vi-operator (state ch op)
  "Apply operator OP (:d or :c) to the motion keyed by CH."
  (let ((edit (vi-operator-edit-for-motion state ch op)))
    (if edit
        (commit-vi-operator-edit state edit)
        (values (%vi-command-state state) :redraw))))

(defun reduce-vi-input-state (state key-event)
  "Reduce KEY-EVENT while STATE is in one of the vi modes."
  (let ((type (nshell.domain.input:key-event-type key-event))
        (mode (input-state-mode state)))
    (case type
      (:enter (finalize-enter-input-state (%vi-insert-state state)))
      (:ctrl-c (clear-input-state state))
      (:ctrl-l (%vi-values-clearing-count state :clear-screen))
      ((:up) (%vi-values-clearing-count state :history-prev))
      ((:down) (%vi-values-clearing-count state :history-next))
      ((:left) (%vi-values-clearing-count
                (move-cursor-clearing-suggestion state -1)
                :redraw))
      ((:right) (%vi-move-to-and-clear-count
                 state (min (%vi-last-column state)
                            (1+ (input-state-cursor-pos state)))))
      (:char
       (let ((ch (nshell.domain.input:key-event-char key-event)))
         (cond
           ((null ch) (values state :none))
           ((eq mode :vi-d) (%reduce-vi-operator state ch :d))
           ((eq mode :vi-c) (%reduce-vi-operator state ch :c))
           ((eq mode :vi-visual) (%reduce-vi-visual state ch))
           (t (%reduce-vi-normal state ch)))))
      ;; ESC in an operator-pending mode cancels back to normal mode.
      (:escape (values (%vi-command-state state) :redraw))
      (otherwise (values state :none)))))
