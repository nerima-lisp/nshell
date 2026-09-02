;;; Undo and redo helpers for the pure REPL input reducer.

(in-package #:nshell.presentation)

(define-value-struct %input-edit-snapshot
    ((buffer nil)
     (cursor-pos 0 :type fixnum))
  :public-accessors nil
  :constructor %make-input-edit-snapshot)

(define-value-struct %undo-stack-step
    ((snapshot nil)
     (undo-stack nil :type list)
     (redo-stack nil :type list))
  :public-accessors nil
  :constructor %make-undo-stack-step)

(define-value-struct %undo-recording-step
    ((undo-stack nil :type list)
     (redo-stack nil :type list))
  :public-accessors nil
  :constructor %make-undo-recording-step)

(define-value-struct %undo-recording-transition
    ((old-state nil)
     (new-state nil)
     (output nil)
     (key-event nil))
  :public-accessors nil
  :constructor %make-undo-recording-transition)

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

(defun undo-recording-transition (old-state new-state output key-event)
  (%make-undo-recording-transition old-state new-state output key-event))

(defun undo-recording-transition-key-type (transition)
  (nshell.domain.input:key-event-type
   (%undo-recording-transition-key-event transition)))

(defun undo-recording-transition-edit-p (transition)
  (let ((old-state (%undo-recording-transition-old-state transition))
        (new-state (%undo-recording-transition-new-state transition)))
    (or (not (string= (input-state-buffer old-state)
                      (input-state-buffer new-state)))
        (/= (input-state-cursor-pos old-state)
            (input-state-cursor-pos new-state)))))

(defun undo-recordable-transition-p (transition)
  (let ((old-state (%undo-recording-transition-old-state transition))
        (new-state (%undo-recording-transition-new-state transition)))
    (and (eq (%undo-recording-transition-output transition) :suggest-update)
         (eq (input-state-mode old-state) :insert)
         (eq (input-state-mode new-state) :insert)
         (not (member (undo-recording-transition-key-type transition)
                      '(:ctrl-underscore :alt-r)
                      :test #'eq))
         (undo-recording-transition-edit-p transition))))

(defun undo-recording-step-for-transition (transition)
  (when (undo-recordable-transition-p transition)
    (let ((old-state (%undo-recording-transition-old-state transition))
          (new-state (%undo-recording-transition-new-state transition)))
      (%make-undo-recording-step
       (cons (input-edit-snapshot old-state)
             (input-state-undo-stack new-state))
       nil))))

(defun apply-undo-recording-step (state step)
  (copy-input-state-with state
                         :undo-stack (%undo-recording-step-undo-stack
                                      step)
                         :redo-stack (%undo-recording-step-redo-stack
                                      step)))

(defun record-undo-transition (old-state new-state output key-event)
  (let* ((transition (undo-recording-transition old-state
                                                new-state
                                                output
                                                key-event))
         (step (undo-recording-step-for-transition transition)))
    (if step
        (apply-undo-recording-step new-state step)
      new-state)))
