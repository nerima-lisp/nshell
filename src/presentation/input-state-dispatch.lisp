;;; Input-dispatch rules for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defstruct (input-dispatch-action
             (:constructor %make-input-dispatch-action
                 (kind &optional value))
             (:conc-name %input-dispatch-action-))
  (kind :none :type symbol :read-only t)
  (value nil :read-only t))

(defun input-dispatch-action-kind (action)
  (%input-dispatch-action-kind action))

(defun input-dispatch-action-value (action)
  (%input-dispatch-action-value action))

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

(defun input-dispatch-action-for-key-event (key-event)
  (case (nshell.domain.input:key-event-type key-event)
    (:char (let ((ch (nshell.domain.input:key-event-char key-event)))
             (if ch
                 (%make-input-dispatch-action :insert-char ch)
                 (%make-input-dispatch-action :none))))
    (:paste (%make-input-dispatch-action :paste key-event))
    (:enter (%make-input-dispatch-action :enter))
    (:tab (%make-input-dispatch-action :cycle-completion 1))
    (:shift-tab (%make-input-dispatch-action :cycle-completion -1))
    (:backspace (%make-input-dispatch-action :backspace))
    (:delete (%make-input-dispatch-action :delete))
    (:ctrl-c (%make-input-dispatch-action :clear-input))
    (:ctrl-d (%make-input-dispatch-action :delete-or-quit))
    ((:ctrl-r :ctrl-s) (%make-input-dispatch-action :start-history-search))
    ((:ctrl-f :right) (%make-input-dispatch-action :accept-suggestion))
    (:escape (%make-input-dispatch-action :escape))
    (:ctrl-g (%make-input-dispatch-action :redraw-clearing-completion))
    ((:ctrl-b :left) (%make-input-dispatch-action :move-cursor -1))
    ((:ctrl-a :home) (%make-input-dispatch-action :move-cursor-absolute 0))
    ((:ctrl-e :end) (%make-input-dispatch-action
                     :move-eol-or-accept-suggestion))
    (:ctrl-k (%make-input-dispatch-action :kill-to-eol))
    (:ctrl-l (%make-input-dispatch-action :emit :clear-screen))
    ((:ctrl-n :down :page-down) (%make-input-dispatch-action
                                 :emit
                                 :history-next))
    ((:ctrl-p :up :page-up) (%make-input-dispatch-action
                             :emit
                             :history-prev))
    (:ctrl-t (%make-input-dispatch-action :transpose-chars))
    (:ctrl-u (%make-input-dispatch-action :kill-to-bol))
    (:ctrl-w (%make-input-dispatch-action :backward-kill-word))
    (:ctrl-y (%make-input-dispatch-action :yank-last-kill))
    (:ctrl-underscore (%make-input-dispatch-action :undo))
    (:alt-r (%make-input-dispatch-action :redo))
    (:alt-dot (%make-input-dispatch-action :emit :insert-last-argument))
    (:alt-c (%make-input-dispatch-action :capitalize-word))
    (:alt-l (%make-input-dispatch-action :downcase-word))
    (:alt-t (%make-input-dispatch-action :transpose-words))
    (:alt-u (%make-input-dispatch-action :upcase-word))
    (:alt-y (%make-input-dispatch-action :cycle-last-yank))
    ((:alt-left :ctrl-left :alt-b) (%make-input-dispatch-action
                                    :move-word-left))
    ((:alt-right :ctrl-right :alt-f) (%make-input-dispatch-action
                                      :accept-suggestion-word))
    (:alt-backspace (%make-input-dispatch-action :backward-kill-word))
    (:alt-d (%make-input-dispatch-action :forward-kill-word))
    (:alt-s (%make-input-dispatch-action :toggle-sudo-prefix))
    ((:shift-up :shift-down :shift-left :shift-right
      :alt-up :alt-down :ctrl-up :ctrl-down
      :shift-alt-up :shift-alt-down :shift-alt-left :shift-alt-right
      :shift-ctrl-up :shift-ctrl-down :shift-ctrl-left :shift-ctrl-right
      :alt-ctrl-up :alt-ctrl-down :alt-ctrl-left :alt-ctrl-right
      :shift-alt-ctrl-up :shift-alt-ctrl-down :shift-alt-ctrl-left
      :shift-alt-ctrl-right
      :mouse)
     (%make-input-dispatch-action :redraw))
    (otherwise (%make-input-dispatch-action :none))))

(defun reduce-insert-input-state-action (state action)
  (case (input-dispatch-action-kind action)
    (:insert-char (insert-char-with-abbreviation-expansion
                   state
                   (input-dispatch-action-value action)))
    (:paste (insert-paste-at-cursor state
                                    (input-dispatch-action-value action)))
    (:enter (finalize-enter-input-state state))
    (:cycle-completion (cycle-completion-state
                        state
                        (input-dispatch-action-value action)))
    (:backspace (backspace-before-cursor state))
    (:delete (delete-char-at-cursor state))
    (:clear-input (clear-input-state state))
    (:delete-or-quit (%delete-or-quit-input-state state))
    (:start-history-search (%start-history-search state))
    (:accept-suggestion (accept-suggestion-at-eol state))
    (:escape (%escape-input-state state))
    (:redraw-clearing-completion
     (%redraw-input-state (clear-completion-session-state state)))
    (:move-cursor (move-cursor-clearing-suggestion
                   state
                   (input-dispatch-action-value action)))
    (:move-cursor-absolute (move-cursor-to-clearing-suggestion
                            state
                            (input-dispatch-action-value action)))
    (:move-eol-or-accept-suggestion
     (%move-cursor-to-eol-or-accept-suggestion state))
    (:kill-to-eol (%kill-to-eol state))
    (:emit (values state (input-dispatch-action-value action)))
    (:transpose-chars (transpose-chars-around-cursor state))
    (:kill-to-bol (%kill-to-bol state))
    (:backward-kill-word (backward-kill-word state))
    (:yank-last-kill (yank-last-kill state))
    (:undo (undo-input-state state))
    (:redo (redo-input-state state))
    (:capitalize-word (capitalize-word-at-cursor state))
    (:downcase-word (downcase-word-at-cursor state))
    (:transpose-words (transpose-words-around-cursor state))
    (:upcase-word (upcase-word-at-cursor state))
    (:cycle-last-yank (cycle-last-yank state))
    (:move-word-left (move-word-left state))
    (:accept-suggestion-word (accept-suggestion-word-at-eol state))
    (:forward-kill-word (forward-kill-word state))
    (:toggle-sudo-prefix (toggle-sudo-prefix state))
    (:redraw (%redraw-input-state state))
    (otherwise (values state :none))))

(defun %reduce-insert-input-state-editing (state key-event)
  (reduce-insert-input-state-action
   state
   (input-dispatch-action-for-key-event key-event)))

(defun reduce-insert-input-state (state key-event)
  (%reduce-insert-input-state-editing state key-event))
