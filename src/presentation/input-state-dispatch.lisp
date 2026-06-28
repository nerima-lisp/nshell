;;; Input-dispatch rules for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defun %start-history-search (state)
  (with-normalized-cleared-completion-state (state state)
    (values (copy-input-state-clearing-completion
             state
             :mode :search
             :search-query ""
             :search-original-buffer (input-state-buffer state)
             :search-original-cursor (input-state-cursor-pos state)
             :search-index 0)
            :search-start)))

(defun %delete-or-quit-input-state (state)
  (if (string= "" (input-state-buffer state))
      (values state :quit)
      (delete-char-at-cursor state)))

(defun %escape-input-state (state)
  (if *vi-mode-enabled*
      (values (vi-enter-command-mode state) :redraw)
      (values (clear-completion-session-state state) :redraw)))

(defun %move-cursor-to-eol-or-accept-suggestion (state)
  (with-normalized-input-state (state state)
    (if (input-state-at-eol-p state)
        (accept-suggestion-at-eol state)
        (values (copy-input-state-with state
                                       :cursor-pos (length (input-state-buffer state)))
                :redraw))))

(defun %redraw-input-state (state)
  (values state :redraw))

(defun %kill-to-eol (state)
  (with-normalized-cleared-completion-state (state state)
    (%kill-range state
                 (input-state-cursor-pos state)
                 (length (input-state-buffer state))
                 (input-state-cursor-pos state))))

(defun %kill-to-bol (state)
  (with-normalized-cleared-completion-state (state state)
    (%kill-range state
                 0
                 (input-state-cursor-pos state)
                 0)))

(defun reduce-insert-input-state (state key-event)
  (case (nshell.domain.input:key-event-type key-event)
    (:char (let ((ch (nshell.domain.input:key-event-char key-event)))
             (if ch
                 (insert-char-with-abbreviation-expansion state ch)
                 (values state :none))))
    (:paste (insert-paste-at-cursor state key-event))
    (:enter (finalize-enter-input-state state))
    (:tab (cycle-completion-state state 1))
    (:shift-tab (cycle-completion-state state -1))
    (:backspace (backspace-before-cursor state))
    (:delete (delete-char-at-cursor state))
    (:ctrl-c (clear-input-state state))
    (:ctrl-d (%delete-or-quit-input-state state))
    ((:ctrl-r :ctrl-s) (%start-history-search state))
    ((:ctrl-f :right) (accept-suggestion-at-eol state))
    (:escape (%escape-input-state state))
    (:ctrl-g (%redraw-input-state (clear-completion-session-state state)))
    ((:ctrl-b :left) (move-cursor-clearing-suggestion state -1))
    ((:ctrl-a :home) (move-cursor-to-clearing-suggestion state 0))
    ((:ctrl-e :end) (%move-cursor-to-eol-or-accept-suggestion state))
    (:ctrl-k (%kill-to-eol state))
    (:ctrl-l (values state :clear-screen))
    ((:ctrl-n :down :page-down) (values state :history-next))
    ((:ctrl-p :up :page-up) (values state :history-prev))
    (:ctrl-t (transpose-chars-around-cursor state))
    (:ctrl-u (%kill-to-bol state))
    (:ctrl-w (backward-kill-word state))
    (:ctrl-y (yank-last-kill state))
    (:ctrl-underscore (undo-input-state state))
    (:alt-r (redo-input-state state))
    (:alt-dot (values state :insert-last-argument))
    (:alt-c (capitalize-word-at-cursor state))
    (:alt-l (downcase-word-at-cursor state))
    (:alt-t (transpose-words-around-cursor state))
    (:alt-u (upcase-word-at-cursor state))
    (:alt-y (cycle-last-yank state))
    ((:alt-left :ctrl-left :alt-b) (move-word-left state))
    ((:alt-right :ctrl-right :alt-f) (accept-suggestion-word-at-eol state))
    (:alt-backspace (backward-kill-word state))
    (:alt-d (forward-kill-word state))
    (:alt-s (toggle-sudo-prefix state))
    ((:shift-up :shift-down :shift-left :shift-right
      :alt-up :alt-down :ctrl-up :ctrl-down
      :shift-alt-up :shift-alt-down :shift-alt-left :shift-alt-right
      :shift-ctrl-up :shift-ctrl-down :shift-ctrl-left :shift-ctrl-right
      :alt-ctrl-up :alt-ctrl-down :alt-ctrl-left :alt-ctrl-right
      :shift-alt-ctrl-up :shift-alt-ctrl-down :shift-alt-ctrl-left
      :shift-alt-ctrl-right
      :mouse)
     (%redraw-input-state state))
    (otherwise (values state :none))))
