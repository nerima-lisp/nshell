;;; Mouse selection rules for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defun %mouse-left-button-p (data)
  (let ((button-code (or (getf data :button-code)
                         (getf data :button)
                         -1)))
    (and (integerp button-code)
         (zerop (logand button-code 3)))))

(defun %mouse-selection-index (data)
  (let ((index (getf data :buffer-index)))
    (and (integerp index) (>= index 0) index)))

(defun %mouse-shift-p (data)
  (some (lambda (modifier)
          (string-equal "SHIFT" (princ-to-string modifier)))
        (getf data :modifiers)))

(defun %clear-mouse-selection-state (state)
  (copy-input-state-with state :mouse-selection-anchor nil :mouse-selection-end nil))

(defun %mouse-selection-range (state)
  (let ((anchor (input-state-mouse-selection-anchor state))
        (end (input-state-mouse-selection-end state)))
    (when (and (integerp anchor) (integerp end))
      (values (min anchor end) (max anchor end)))))

(defun %mouse-selection-transition (state data)
  (let ((event (getf data :event)) (index (%mouse-selection-index data)))
    (case event
      (:press
       (let ((anchor (if (and (%mouse-shift-p data)
                              (integerp (input-state-mouse-selection-anchor state)))
                         (input-state-mouse-selection-anchor state)
                         index)))
         (values (copy-input-state-with state
                                        :mouse-selection-anchor anchor
                                        :mouse-selection-end index)
                 :redraw)))
      (:drag
       (let ((anchor (or (input-state-mouse-selection-anchor state) index)))
         (values (copy-input-state-with state
                                        :mouse-selection-anchor anchor
                                        :mouse-selection-end index)
                 :redraw)))
      (:release
       (multiple-value-bind (start end) (%mouse-selection-range state)
         (if (and start end (< start end))
             (values (copy-input-state-with
                      state
                      :kill-ring (cons (subseq (input-state-buffer state) start end)
                                       (input-state-kill-ring state))
                      :mouse-selection-anchor nil
                      :mouse-selection-end nil)
                     :copy)
             (values (%clear-mouse-selection-state state) :redraw))))
      (otherwise (values state :redraw)))))

(defun %mouse-input-dispatch-action (key-event)
  (let ((data (nshell.domain.input:key-event-data key-event)))
    (if (eq :sgr (getf data :protocol))
        (case (getf data :event)
          (:wheel-up (%make-input-dispatch-action :emit :history-prev))
          (:wheel-down (%make-input-dispatch-action :emit :history-next))
          ((:press :drag :release)
           (if (and (%mouse-left-button-p data) (%mouse-selection-index data))
               (%make-input-dispatch-action :mouse-select data)
               (%make-input-dispatch-action :redraw)))
          (otherwise (%make-input-dispatch-action :redraw)))
        (%make-input-dispatch-action :redraw))))
