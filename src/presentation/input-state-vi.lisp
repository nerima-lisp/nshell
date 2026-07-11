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
  (commit-vi-input-transition
   (vi-input-transition-clearing-count state output)))

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
