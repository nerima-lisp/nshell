;;; Undo and redo helpers for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defstruct (%input-edit-snapshot
            (:constructor %make-input-edit-snapshot (buffer cursor-pos))
            (:conc-name %input-edit-snapshot-))
  buffer
  cursor-pos)

(defun input-edit-snapshot (state)
  (%make-input-edit-snapshot (input-state-buffer state)
                             (input-state-cursor-pos state)))

(defun restore-input-edit-snapshot (state snapshot &key undo-stack redo-stack)
  (copy-input-state-clearing-completion state
                                        :buffer (%input-edit-snapshot-buffer
                                                 snapshot)
                                        :cursor-pos (%input-edit-snapshot-cursor-pos
                                                     snapshot)
                                        :last-yank-start nil
                                        :last-yank-end nil
                                        :last-yank-index nil
                                        :last-argument-start nil
                                        :last-argument-end nil
                                        :last-argument-index nil
                                        :undo-stack undo-stack
                                        :redo-stack redo-stack))

(defun undo-input-state (state)
  (let ((source-stack (input-state-undo-stack state)))
    (if source-stack
        (let ((next (first source-stack)))
          (values (restore-input-edit-snapshot state
                                               next
                                               :undo-stack (rest source-stack)
                                               :redo-stack (cons (input-edit-snapshot state)
                                                                 (input-state-redo-stack state)))
                  :suggest-update))
        (values state :none))))

(defun redo-input-state (state)
  (let ((source-stack (input-state-redo-stack state)))
    (if source-stack
        (let ((next (first source-stack)))
          (values (restore-input-edit-snapshot state
                                               next
                                               :undo-stack (cons (input-edit-snapshot state)
                                                                 (input-state-undo-stack state))
                                               :redo-stack (rest source-stack))
                  :suggest-update))
        (values state :none))))

(defun undo-recordable-transition-p (old-state new-state output key-event)
  (and (eq output :suggest-update)
       (eq (input-state-mode old-state) :insert)
       (eq (input-state-mode new-state) :insert)
       (not (member (nshell.domain.input:key-event-type key-event)
                    '(:ctrl-underscore :alt-r)
                    :test #'eq))
       (not (and (string= (input-state-buffer old-state)
                          (input-state-buffer new-state))
                 (= (input-state-cursor-pos old-state)
                    (input-state-cursor-pos new-state))))))

(defun record-undo-transition (old-state new-state output key-event)
  (if (undo-recordable-transition-p old-state new-state output key-event)
      (copy-input-state-with new-state
                             :undo-stack (cons (input-edit-snapshot old-state)
                                               (input-state-undo-stack
                                                new-state))
                             :redo-stack nil)
      new-state))
