;;; Completion cycling helpers for the input reducer.

(in-package #:nshell.presentation)

(define-value-struct %completion-cycle-selection
    ((base-buffer "" :type string)
     (base-cursor 0 :type fixnum)
     (index 0 :type fixnum)
     (candidate "")))

(defun completion-cycle-selection-for-state (state direction candidates)
  (let* ((count (length candidates))
         (first-cycle-p (= -1 (input-state-completion-index state)))
         (base-buffer (if first-cycle-p
                          (input-state-buffer state)
                          (or (input-state-completion-base-buffer state)
                              (input-state-buffer state))))
         (base-cursor (if first-cycle-p
                          (input-state-cursor-pos state)
                          (or (input-state-completion-base-cursor state)
                              (length base-buffer))))
          (index (if first-cycle-p
                     (if (minusp direction)
                         (1- count)
                         0)
                     (mod (+ (input-state-completion-index state) direction)
                          count))))
    (%make-completion-cycle-selection
     base-buffer
     base-cursor
     index
     (nth index candidates))))

(define-value-struct %completion-cycle-edit
    ((base-buffer "" :type string)
     (base-cursor 0 :type fixnum)
     (index 0 :type fixnum)
     (buffer "" :type string)
     (cursor-pos 0 :type fixnum)))

(defun completion-cycle-edit-for-selection (selection)
  (let ((base-buffer (completion-cycle-selection-base-buffer selection))
        (base-cursor (completion-cycle-selection-base-cursor selection)))
    (multiple-value-bind (buffer cursor)
        (apply-completion base-buffer
                          (completion-cycle-selection-candidate selection)
                          :cursor base-cursor)
      (%make-completion-cycle-edit
       base-buffer
       base-cursor
       (completion-cycle-selection-index selection)
       buffer
       cursor))))

(defun commit-completion-cycle-edit (state edit)
  (copy-input-state-with state
                         :suggestion :clear
                         :buffer (completion-cycle-edit-buffer edit)
                         :cursor-pos (completion-cycle-edit-cursor-pos edit)
                         :completion-index (completion-cycle-edit-index edit)
                         :completion-base-buffer
                         (completion-cycle-edit-base-buffer edit)
                         :completion-base-cursor
                         (completion-cycle-edit-base-cursor edit)))

(defun cycle-completion-state (state direction)
  (with-normalized-input-state (state state)
    (let ((candidates (input-state-last-candidates state)))
      (if (null candidates)
          (values state :complete)
          (let ((selection (completion-cycle-selection-for-state
                            state
                            direction
                            candidates)))
            (values (commit-completion-cycle-edit
                     state
                     (completion-cycle-edit-for-selection selection))
                    :complete))))))
