;;; Undo and redo helpers for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defstruct (%input-edit-snapshot
            (:constructor %make-input-edit-snapshot (buffer cursor-pos))
            (:conc-name %input-edit-snapshot-))
  buffer
  cursor-pos)

(defstruct (%undo-stack-step
            (:constructor %make-undo-stack-step
                (snapshot undo-stack redo-stack))
            (:conc-name %undo-stack-step-))
  snapshot
  undo-stack
  redo-stack)

(defstruct (%undo-recording-step
            (:constructor %make-undo-recording-step
                (undo-stack redo-stack))
            (:conc-name %undo-recording-step-))
  undo-stack
  redo-stack)

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

(defun undo-stack-step-for-direction (state direction)
  (ecase direction
    (:undo
     (let ((source-stack (input-state-undo-stack state)))
       (when source-stack
         (%make-undo-stack-step
          (first source-stack)
          (rest source-stack)
          (cons (input-edit-snapshot state)
                (input-state-redo-stack state))))))
    (:redo
     (let ((source-stack (input-state-redo-stack state)))
       (when source-stack
         (%make-undo-stack-step
          (first source-stack)
          (cons (input-edit-snapshot state)
                (input-state-undo-stack state))
          (rest source-stack)))))))

(defun apply-undo-stack-step (state step)
  (restore-input-edit-snapshot state
                               (%undo-stack-step-snapshot step)
                               :undo-stack (%undo-stack-step-undo-stack
                                            step)
                               :redo-stack (%undo-stack-step-redo-stack
                                            step)))

(defun undo-input-state (state)
  (let ((step (undo-stack-step-for-direction state :undo)))
    (if step
        (values (apply-undo-stack-step state step)
                :suggest-update)
        (values state :none))))

(defun redo-input-state (state)
  (let ((step (undo-stack-step-for-direction state :redo)))
    (if step
        (values (apply-undo-stack-step state step)
                :suggest-update)
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

(defun undo-recording-step-for-transition (old-state new-state output key-event)
  (when (undo-recordable-transition-p old-state new-state output key-event)
    (%make-undo-recording-step
     (cons (input-edit-snapshot old-state)
           (input-state-undo-stack new-state))
     nil)))

(defun apply-undo-recording-step (state step)
  (copy-input-state-with state
                         :undo-stack (%undo-recording-step-undo-stack
                                      step)
                         :redo-stack (%undo-recording-step-redo-stack
                                      step)))

(defun record-undo-transition (old-state new-state output key-event)
  (let ((step (undo-recording-step-for-transition old-state
                                                  new-state
                                                  output
                                                  key-event)))
    (if step
        (apply-undo-recording-step new-state step)
      new-state)))
