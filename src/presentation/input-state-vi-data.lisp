;;; Data helpers for vi-mode input-state transitions.

(in-package #:nshell.presentation)

(defstruct (vi-input-transition
             (:constructor %make-vi-input-transition
                 (state output))
             (:conc-name vi-input-transition-))
  (state nil :read-only t)
  (output :none :type symbol :read-only t))

(defun %vi-clear-count (state)
  (copy-input-state-with state :vi-count nil))

(defun vi-input-transition (state output)
  (%make-vi-input-transition state output))

(defun vi-input-transition-clearing-count (state output)
  (vi-input-transition (%vi-clear-count state) output))

(defun commit-vi-input-transition (transition)
  (values (vi-input-transition-state transition)
          (vi-input-transition-output transition)))

(defstruct (vi-visual-selection
             (:constructor %make-vi-visual-selection (start end cursor))
             (:conc-name vi-visual-selection-))
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t)
  (cursor 0 :type fixnum :read-only t))

(defstruct (vi-operator-edit
             (:constructor %make-vi-operator-edit (start end cursor end-mode))
             (:conc-name vi-operator-edit-))
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t)
  (cursor 0 :type fixnum :read-only t)
  (end-mode :vi-command :type (member :vi-command :insert) :read-only t))

(defun %vi-visual-range (state)
  (let* ((buffer (input-state-buffer state))
         (anchor (or (input-state-vi-visual-anchor state)
                     (input-state-cursor-pos state)))
         (cursor (input-state-cursor-pos state))
         (start (min anchor cursor))
         (end (min (length buffer) (1+ (max anchor cursor)))))
    (values start end)))

(defun vi-visual-selection-for-state (state)
  (multiple-value-bind (start end)
      (%vi-visual-range state)
    (%make-vi-visual-selection start end start)))

(defstruct (vi-visual-yank-edit
             (:constructor %make-vi-visual-yank-edit (cursor selected))
             (:conc-name vi-visual-yank-edit-))
  (cursor 0 :type fixnum :read-only t)
  (selected "" :type string :read-only t))

(defun vi-visual-yank-edit-for-range (state start end cursor)
  (let* ((buffer (input-state-buffer state))
         (start (max 0 (min start (length buffer))))
         (end (max start (min end (length buffer))))
         (cursor (max 0 (min cursor (length buffer)))))
    (%make-vi-visual-yank-edit cursor (subseq buffer start end))))

(defstruct (vi-visual-anchor-swap-edit
             (:constructor %make-vi-visual-anchor-swap-edit (cursor anchor))
             (:conc-name vi-visual-anchor-swap-edit-))
  (cursor 0 :type fixnum :read-only t)
  (anchor 0 :type fixnum :read-only t))

(defun vi-visual-anchor-swap-edit-for-state (state)
  (%make-vi-visual-anchor-swap-edit
   (input-state-cursor-pos state)
   (or (input-state-vi-visual-anchor state)
       (input-state-cursor-pos state))))
