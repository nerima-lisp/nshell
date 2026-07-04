;;; Completion cycling helpers for the input reducer.

(in-package #:nshell.presentation)

(defun %completion-cycle-selection (state direction candidates)
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
    (values base-buffer base-cursor index (nth index candidates))))

(defun cycle-completion-state (state direction)
  (with-normalized-input-state (state state)
    (let ((candidates (input-state-last-candidates state)))
      (if (null candidates)
          (values state :complete)
          (multiple-value-bind (base-buffer base-cursor index candidate)
              (%completion-cycle-selection state direction candidates)
            (multiple-value-bind (buffer cursor)
                (apply-completion base-buffer candidate :cursor base-cursor)
              (values (copy-input-state-with state
                                             :suggestion :clear
                                             :buffer buffer
                                             :cursor-pos cursor
                                             :completion-index index
                                             :completion-base-buffer base-buffer
                                             :completion-base-cursor base-cursor)
                      :complete)))))))
