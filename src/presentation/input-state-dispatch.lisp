;;; Input-dispatch rules for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defun input-dispatch-transition (state output)
  (%make-input-dispatch-transition state output))

(defun input-dispatch-output-transition (state output)
  (input-dispatch-transition (normalize-input-state state) output))

(defmacro input-dispatch-transition-from-reduction (reduction)
  `(multiple-value-bind (state output) ,reduction
     (input-dispatch-output-transition state output)))

(defun commit-input-dispatch-transition (transition)
  (values (input-dispatch-transition-state transition)
          (input-dispatch-transition-output transition)))

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

(defun %input-dispatch-name-string (keyword)
  (string-downcase (symbol-name keyword)))

(defun %input-dispatch-key-type-for-name (name)
  (find name (mapcar #'car +default-input-dispatch-bindings+)
        :key #'%input-dispatch-name-string :test #'string-equal))

(defun %input-dispatch-action-name-for-string (name)
  (find name (mapcar #'first +input-dispatch-action-table+)
        :key #'%input-dispatch-name-string :test #'string-equal))

(defun %input-dispatch-action-for-name (action-name)
  (let ((row (assoc action-name +input-dispatch-action-table+)))
    (if row
        (%make-input-dispatch-action (second row) (third row))
        (%make-input-dispatch-action :none))))

(defun input-dispatch-binding-action-name (key-type)
  "Return the action name bound to KEY-TYPE, or :NONE when unbound."
  (or (gethash key-type *input-dispatch-bindings*) :none))

(defun input-dispatch-action-for-key-event (key-event)
  (case (nshell.domain.input:key-event-type key-event)
    (:char (let ((ch (nshell.domain.input:key-event-char key-event)))
             (if ch
                 (%make-input-dispatch-action :insert-char ch)
                 (%make-input-dispatch-action :none))))
    (:paste (%make-input-dispatch-action :paste key-event))
    (:mouse (%mouse-input-dispatch-action key-event))
    (otherwise
     (%input-dispatch-action-for-name
      (input-dispatch-binding-action-name
       (nshell.domain.input:key-event-type key-event))))))

(defun input-dispatch-bindings-listing ()
  "Return an alist of (KEY-NAME . ACTION-NAME) strings, sorted by key name,
for every bindable key-event type."
  (sort (mapcar (lambda (key-type)
                  (cons (%input-dispatch-name-string key-type)
                        (%input-dispatch-name-string
                         (input-dispatch-binding-action-name key-type))))
                (mapcar #'car +default-input-dispatch-bindings+))
        #'string< :key #'car))

(defun input-dispatch-valid-key-names ()
  (sort (mapcar #'%input-dispatch-name-string
                (mapcar #'car +default-input-dispatch-bindings+))
        #'string<))

(defun input-dispatch-valid-action-names ()
  (mapcar (lambda (row) (%input-dispatch-name-string (first row)))
          +input-dispatch-action-table+))

(defun input-dispatch-get-binding (key-name)
  "Return the action name bound to KEY-NAME and T, or NIL and NIL when
KEY-NAME does not name a bindable key."
  (let ((key-type (%input-dispatch-key-type-for-name key-name)))
    (if key-type
        (values (%input-dispatch-name-string
                 (input-dispatch-binding-action-name key-type))
                t)
        (values nil nil))))

(defun input-dispatch-set-binding (key-name action-name)
  "Rebind KEY-NAME to ACTION-NAME. Returns :OK, :UNKNOWN-KEY, or
:UNKNOWN-ACTION."
  (let ((key-type (%input-dispatch-key-type-for-name key-name))
        (action (%input-dispatch-action-name-for-string action-name)))
    (cond
      ((null key-type) :unknown-key)
      ((null action) :unknown-action)
      (t (setf (gethash key-type *input-dispatch-bindings*) action)
         :ok))))

(defun input-dispatch-erase-binding (key-name)
  "Erase KEY-NAME's binding, so it dispatches :NONE. Returns :OK or
:UNKNOWN-KEY."
  (let ((key-type (%input-dispatch-key-type-for-name key-name)))
    (if key-type
        (progn (remhash key-type *input-dispatch-bindings*) :ok)
        :unknown-key)))

(defun input-dispatch-reset-bindings ()
  (clrhash *input-dispatch-bindings*)
  (dolist (entry +default-input-dispatch-bindings+)
    (setf (gethash (car entry) *input-dispatch-bindings*) (cdr entry)))
  :ok)

(defun bind-dispatch-handler (operation &rest args)
  "Implements the BIND builtin's protocol against *INPUT-DISPATCH-BINDINGS*.
OPERATION is :LIST, :GET, :SET, :ERASE, :RESET, :VALID-KEYS, or
:VALID-ACTIONS; NSHELL.APPLICATION:*BIND-TABLE-HANDLER* is set to this
function so the application layer can reach it without depending on the
presentation package."
  (ecase operation
    (:list (input-dispatch-bindings-listing))
    (:get (input-dispatch-get-binding (first args)))
    (:set (input-dispatch-set-binding (first args) (second args)))
    (:erase (input-dispatch-erase-binding (first args)))
    (:reset (input-dispatch-reset-bindings))
    (:valid-keys (input-dispatch-valid-key-names))
    (:valid-actions (input-dispatch-valid-action-names))))

(defun input-dispatch-transition-for-action (state action)
  (macrolet ((from (reduction)
               `(input-dispatch-transition-from-reduction ,reduction)))
    (case (input-dispatch-action-kind action)
      (:insert-char (from (insert-char-with-abbreviation-expansion
                           state
                           (input-dispatch-action-value action))))
      (:paste (from (insert-paste-at-cursor
                     state
                     (input-dispatch-action-value action))))
      (:enter (from (finalize-enter-input-state state)))
      (:cycle-completion (from (cycle-completion-state
                                state
                                (input-dispatch-action-value action))))
      (:backspace (from (backspace-before-cursor state)))
      (:delete (from (delete-char-at-cursor state)))
      (:clear-input (from (clear-input-state state)))
      (:delete-or-quit (from (%delete-or-quit-input-state state)))
      (:start-history-search (from (%start-history-search state)))
      (:start-ask (from (%start-ask-input-state state)))
      (:accept-suggestion (from (accept-suggestion-at-eol state)))
      (:escape (from (%escape-input-state state)))
      (:redraw-clearing-completion
       (from (%redraw-input-state (clear-completion-session-state state))))
      (:move-cursor (from (move-cursor-clearing-suggestion
                           state
                           (input-dispatch-action-value action))))
      (:move-cursor-absolute (from (move-cursor-to-clearing-suggestion
                                    state
                                    (input-dispatch-action-value action))))
      (:move-eol-or-accept-suggestion
       (from (%move-cursor-to-eol-or-accept-suggestion state)))
      (:kill-to-eol (from (%kill-to-eol state)))
      (:emit (input-dispatch-output-transition
              state
              (input-dispatch-action-value action)))
      (:transpose-chars (from (transpose-chars-around-cursor state)))
      (:kill-to-bol (from (%kill-to-bol state)))
      (:backward-kill-word (from (backward-kill-word state)))
      (:yank-last-kill (from (yank-last-kill state)))
      (:undo (from (undo-input-state state)))
      (:redo (from (redo-input-state state)))
      (:capitalize-word (from (capitalize-word-at-cursor state)))
      (:downcase-word (from (downcase-word-at-cursor state)))
      (:transpose-words (from (transpose-words-around-cursor state)))
      (:upcase-word (from (upcase-word-at-cursor state)))
      (:cycle-last-yank (from (cycle-last-yank state)))
      (:move-word-left (from (move-word-left state)))
      (:accept-suggestion-word (from (accept-suggestion-word-at-eol state)))
      (:forward-kill-word (from (forward-kill-word state)))
      (:toggle-sudo-prefix (from (toggle-sudo-prefix state)))
      (:mouse-select (from (%mouse-selection-transition
                           state
                           (input-dispatch-action-value action))))
      (:redraw (from (%redraw-input-state state)))
      (otherwise (input-dispatch-output-transition state :none)))))

(defun reduce-insert-input-state-action (state action)
  (commit-input-dispatch-transition
   (input-dispatch-transition-for-action state action)))

(defun %reduce-insert-input-state-editing (state key-event)
  (reduce-insert-input-state-action
   state
   (input-dispatch-action-for-key-event key-event)))

(defun reduce-insert-input-state (state key-event)
  (%reduce-insert-input-state-editing state key-event))
