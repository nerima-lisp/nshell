;;; Vi-style modal key bindings for the pure REPL input reducer.
;;;
;;; When *VI-MODE-ENABLED* is true, pressing ESC in insert mode switches to vi
;;; normal (command) mode. Normal mode supports the common motions and edits;
;;; the operators d and c are modeled as transient modes (:vi-d / :vi-c), while
;;; INPUT-STATE.VI-COUNT stores pending numeric arguments. All functions here
;;; are pure.

(in-package #:nshell.presentation)

;; *VI-MODE-ENABLED* is declared in input-state-core so the dispatch table can
;; reference it before this file loads.

(defun %vi-buffer-length (state)
  (length (input-state-buffer state)))

(defun %vi-last-column (state)
  "Maximum cursor index in normal mode, where the cursor rests on a character."
  (max 0 (1- (%vi-buffer-length state))))

(defun %vi-count (state)
  (or (input-state-vi-count state) 1))

(defun %vi-clear-count (state)
  (copy-input-state-with state :vi-count nil))

(defun %vi-accumulate-count (state digit)
  (copy-input-state-with state
                         :vi-count (+ (* 10 (or (input-state-vi-count state)
                                                 0))
                                      (digit-char-p digit))))

(defun %vi-counted-position (position count step)
  (let ((current position))
    (dotimes (_ count current)
      (setf current (funcall step current)))))

(defun %vi-counted-word-right (state count)
  (let ((current state))
    (dotimes (_ count current)
      (setf current (move-word-right current)))))

(defun %vi-counted-word-left (state count)
  (let ((current state))
    (dotimes (_ count current)
      (setf current (move-word-left current)))))

(defun %vi-counted-word-end-position (buffer position count)
  (%vi-counted-position position count
                        (lambda (current)
                          (max current (1- (next-kill-word-end buffer current))))))

(defun %vi-counted-kill-word-end (buffer position count)
  (%vi-counted-position position count
                        (lambda (current)
                          (next-kill-word-end buffer current))))

(defun %vi-counted-kill-word-start (buffer position count)
  (%vi-counted-position position count
                        (lambda (current)
                          (previous-kill-word-start buffer current))))

(defun %vi-values-clearing-count (state output)
  (values (%vi-clear-count state) output))

(defun %vi-move-to-and-clear-count (state position)
  (%vi-values-clearing-count
   (move-cursor-to-clearing-suggestion state position)
   :redraw))

(defun %vi-state-with-mode (state mode &key cursor-pos anchor clear-completion-p)
  (let ((state (if clear-completion-p
                   (clear-completion-session-state state)
                   state)))
    (copy-input-state-with state
                           :mode mode
                           :vi-count nil
                           :vi-visual-anchor anchor
                           :cursor-pos (or cursor-pos (input-state-cursor-pos state)))))

(defun %vi-command-state (state &key cursor-pos clear-completion-p)
  (%vi-state-with-mode state
                       :vi-command
                       :cursor-pos cursor-pos
                       :anchor :clear
                       :clear-completion-p clear-completion-p))

(defun %vi-insert-state (state &key cursor-pos)
  (%vi-state-with-mode state
                       :insert
                       :cursor-pos cursor-pos
                       :anchor :clear))

(defun %vi-visual-state (state &key anchor clear-completion-p)
  (%vi-state-with-mode state
                       :vi-visual
                       :anchor (or anchor (input-state-cursor-pos state))
                       :clear-completion-p clear-completion-p))

(defmacro %vi-with-common-motion-cases ((state ch pos len count) &body extra-clauses)
  (declare (ignorable len))
  `(case ,ch
     ;; Numeric arguments. A leading 0 remains the line-start motion.
     ((#\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9)
      (values (%vi-accumulate-count ,state ,ch) :redraw))
     ((#\0) (if (input-state-vi-count ,state)
                (values (%vi-accumulate-count ,state ,ch) :redraw)
                (%vi-values-clearing-count
                 (move-cursor-to-clearing-suggestion ,state 0)
                 :redraw)))
     ;; Motions.
     ((#\h) (%vi-values-clearing-count
             (move-cursor-clearing-suggestion ,state (- ,count))
             :redraw))
     ((#\l) (%vi-move-to-and-clear-count
             ,state (min (%vi-last-column ,state) (+ ,pos ,count))))
     ((#\^) (%vi-move-to-and-clear-count ,state 0))
     ((#\$) (%vi-move-to-and-clear-count ,state (%vi-last-column ,state)))
     ((#\w) (%vi-values-clearing-count (%vi-counted-word-right ,state ,count) :redraw))
     ((#\b) (%vi-values-clearing-count (%vi-counted-word-left ,state ,count) :redraw))
     ((#\e) (%vi-move-to-and-clear-count
             ,state (%vi-counted-word-end-position
                     (input-state-buffer ,state) ,pos ,count)))
     ,@extra-clauses))

(defun %vi-enter-visual (state)
  (%vi-visual-state state
                    :clear-completion-p t
                    :anchor (input-state-cursor-pos state)))

(defun %vi-leave-visual (state)
  (%vi-command-state state))

(defun %vi-visual-range (state)
  (let* ((buffer (input-state-buffer state))
         (anchor (or (input-state-vi-visual-anchor state)
                     (input-state-cursor-pos state)))
         (cursor (input-state-cursor-pos state))
         (start (min anchor cursor))
         (end (min (length buffer) (1+ (max anchor cursor)))))
    (values start end)))

(defstruct (vi-visual-selection
             (:constructor %make-vi-visual-selection (start end cursor))
             (:conc-name %vi-visual-selection-))
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t)
  (cursor 0 :type fixnum :read-only t))

(defun vi-visual-selection-for-state (state)
  (multiple-value-bind (start end)
      (%vi-visual-range state)
    (%make-vi-visual-selection start end start)))

(defun vi-visual-selection-start (selection)
  (%vi-visual-selection-start selection))

(defun vi-visual-selection-end (selection)
  (%vi-visual-selection-end selection))

(defun vi-visual-selection-cursor (selection)
  (%vi-visual-selection-cursor selection))

(defstruct (vi-visual-yank-edit
             (:constructor %make-vi-visual-yank-edit (cursor selected))
             (:conc-name %vi-visual-yank-edit-))
  (cursor 0 :type fixnum :read-only t)
  (selected "" :type string :read-only t))

(defun vi-visual-yank-edit-for-range (state start end cursor)
  (let* ((buffer (input-state-buffer state))
         (start (max 0 (min start (length buffer))))
         (end (max start (min end (length buffer))))
         (cursor (max 0 (min cursor (length buffer)))))
    (%make-vi-visual-yank-edit cursor (subseq buffer start end))))

(defun vi-visual-yank-edit-cursor (edit)
  (%vi-visual-yank-edit-cursor edit))

(defun vi-visual-yank-edit-selected (edit)
  (%vi-visual-yank-edit-selected edit))

(defun commit-vi-visual-yank-edit (state edit)
  (let ((selected (vi-visual-yank-edit-selected edit)))
    (values (copy-input-state-with
             (%vi-command-state state
                                :clear-completion-p t
                                :cursor-pos (vi-visual-yank-edit-cursor edit))
             :kill-ring (if (zerop (length selected))
                            (input-state-kill-ring state)
                            (cons selected (input-state-kill-ring state))))
            :redraw)))

(defun commit-vi-visual-yank-selection (state selection)
  (commit-vi-visual-yank-edit
   state
   (vi-visual-yank-edit-for-range
    state
    (vi-visual-selection-start selection)
    (vi-visual-selection-end selection)
    (vi-visual-selection-cursor selection))))

(defstruct (vi-visual-anchor-swap-edit
             (:constructor %make-vi-visual-anchor-swap-edit (cursor anchor))
             (:conc-name %vi-visual-anchor-swap-edit-))
  (cursor 0 :type fixnum :read-only t)
  (anchor 0 :type fixnum :read-only t))

(defun vi-visual-anchor-swap-edit-for-state (state)
  (%make-vi-visual-anchor-swap-edit
   (input-state-cursor-pos state)
   (or (input-state-vi-visual-anchor state)
       (input-state-cursor-pos state))))

(defun vi-visual-anchor-swap-edit-cursor (edit)
  (%vi-visual-anchor-swap-edit-cursor edit))

(defun vi-visual-anchor-swap-edit-anchor (edit)
  (%vi-visual-anchor-swap-edit-anchor edit))

(defun commit-vi-visual-anchor-swap-edit (state edit)
  (values (copy-input-state-with
           state
           :cursor-pos (vi-visual-anchor-swap-edit-anchor edit)
           :vi-count nil
           :vi-visual-anchor (vi-visual-anchor-swap-edit-cursor edit))
          :redraw))

(defun %vi-swap-visual-anchor (state)
  (commit-vi-visual-anchor-swap-edit
   state
   (vi-visual-anchor-swap-edit-for-state state)))

(defun vi-enter-command-mode (state)
  "Switch STATE to vi normal mode, moving the cursor left one as vi does on ESC."
  (%vi-command-state state
                     :cursor-pos (max 0 (1- (input-state-cursor-pos state)))
                     :clear-completion-p t))

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
  (let* ((buffer (input-state-buffer state))
         (pos (input-state-cursor-pos state))
         (len (length buffer))
         (count (%vi-count state))
         (end-mode (if (eq op :c) :insert :vi-command))
         ;; The operator key repeated (dd / cc) acts on the whole line.
         (self (if (eq op :c) #\c #\d)))
    (cond
      ((char= ch self) (%vi-kill-into state 0 len 0 end-mode))
      ((char= ch #\w) (%vi-kill-into state
                                      pos
                                      (%vi-counted-kill-word-end buffer pos count)
                                      pos
                                      end-mode))
      ((char= ch #\b) (let ((start (%vi-counted-kill-word-start
                                    buffer pos count)))
                        (%vi-kill-into state start pos start end-mode)))
      ((char= ch #\$) (%vi-kill-into state pos len (if (eq op :c) pos (max 0 (1- pos))) end-mode))
      ((char= ch #\0) (%vi-kill-into state 0 pos 0 end-mode))
      ;; Unknown motion cancels the pending operator.
      (t (values (%vi-command-state state) :redraw)))))

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
