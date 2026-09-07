;;; Ask-mode transitions for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defun %start-ask-input-state (state)
  (with-normalized-cleared-completion-state (state state)
    (values (copy-input-state-with state
                                   :mode :ask
                                   :suggestion nil
                                   :ask-original-buffer (input-state-buffer state)
                                   :ask-original-cursor (input-state-cursor-pos state))
            :ask-start)))

(defun %ask-edit-reduction (reduction)
  (multiple-value-bind (state output) reduction
    (declare (ignore output))
    (values state :redraw)))

(defun %ask-insert-char (state char)
  (%ask-edit-reduction (insert-char-at-cursor state char)))

(defun %ask-insert-paste (state event)
  (%ask-edit-reduction (insert-paste-at-cursor state event)))

(defun %ask-backspace (state)
  (%ask-edit-reduction (backspace-before-cursor state)))

(defun %ask-delete (state)
  (%ask-edit-reduction (delete-char-at-cursor state)))

(defun %ask-cancel-input (state output)
  (values (copy-input-state-with
           state
           :buffer (input-state-ask-original-buffer state)
           :cursor-pos (or (input-state-ask-original-cursor state) 0)
           :mode :insert
           :suggestion nil
           :ask-original-buffer :clear
           :ask-original-cursor :clear)
          output))

(defun reduce-ask-input-state (state key-event)
  (case (nshell.domain.input:key-event-type key-event)
    (:char
     (let ((char (nshell.domain.input:key-event-char key-event)))
       (if char
           (%ask-insert-char state char)
           (values state :none))))
    (:paste (%ask-insert-paste state key-event))
    (:backspace (%ask-backspace state))
    (:delete (%ask-delete state))
    (:enter
     (values (copy-input-state-with state :mode :ask-waiting)
             :ask-submit))
    (:ctrl-g (%ask-cancel-input state :ask-cancel))
    (:ctrl-c (%ask-cancel-input state :ask-cancel))
    (otherwise (values state :none))))

(defun reduce-ask-waiting-input-state (state key-event)
  (if (eq :ctrl-c (nshell.domain.input:key-event-type key-event))
      (values state :ask-cancel-turn)
      (values state :none)))
