;;; Session-level state transitions for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defparameter +completion-session-preserving-key-event-types+
  '(:tab :shift-tab :ctrl-l))

(defparameter +completion-session-resetting-key-event-types+
  '(:escape :ctrl-g :ctrl-c))

(defparameter +yank-session-clearing-key-event-types+
  '(:ctrl-y :alt-y))

(defparameter +argument-session-clearing-key-event-types+
  '(:alt-dot))

(defun %completion-session-preserved-p (old-state state key-event-type)
  (and (eq (input-state-mode old-state) :insert)
       (eq (input-state-mode state) :insert)
       (not (member key-event-type +completion-session-resetting-key-event-types+
                    :test #'eq))
       (or (member key-event-type +completion-session-preserving-key-event-types+
                   :test #'eq)
           (eq key-event-type :ctrl-l)
           (let ((suggestion (input-state-suggestion state)))
             (and (stringp suggestion)
                  (plusp (length suggestion)))))))

(defun %clear-session-fields (state initargs)
  (apply #'copy-input-state-with state initargs))

(defun %clear-session-fields-unless (state key-event-type exempt-events initargs)
  (if (member key-event-type exempt-events :test #'eq)
      state
      (%clear-session-fields state initargs)))

(defun %clear-yank-session-state (state key-event-type)
  (%clear-session-fields-unless state
                                key-event-type
                                +yank-session-clearing-key-event-types+
                                '(:last-yank-start nil
                                  :last-yank-end nil
                                  :last-yank-index nil)))

(defun %clear-argument-session-state (state key-event-type)
  (%clear-session-fields-unless state
                                key-event-type
                                +argument-session-clearing-key-event-types+
                                '(:last-argument-start nil
                                  :last-argument-end nil
                                  :last-argument-index nil)))

(defun %clear-transient-session-state (state key-event-type)
  (%clear-argument-session-state (%clear-yank-session-state state key-event-type)
                                 key-event-type))

(defun finalize-input-state-transition (old-state new-state key-event)
  (let ((key-event-type (nshell.domain.input:key-event-type key-event)))
    (when (eq key-event-type :ctrl-l)
      (return-from finalize-input-state-transition new-state))
    (let ((state (%clear-transient-session-state new-state key-event-type)))
      (if (%completion-session-preserved-p old-state state key-event-type)
          state
          (clear-completion-session-state state)))))

(defun reduce-input-state (state key-event)
  "Apply KEY-EVENT to INPUT-STATE and return two values.

The first value is a fresh INPUT-STATE. The second value is an OUTPUT-EVENT
keyword for the impure REPL shell to interpret. This function performs no I/O
  and mutates neither STATE nor KEY-EVENT."
  (with-normalized-input-state (state state)
    (multiple-value-bind (new-state output)
        (case (input-state-mode state)
          (:search (reduce-search-input-state state key-event))
          ((:vi-command :vi-visual :vi-d :vi-c)
           (reduce-vi-input-state state key-event))
          (t (reduce-insert-input-state state key-event)))
      (let ((final-state (finalize-input-state-transition state new-state key-event)))
        (values (record-undo-transition state final-state output key-event)
                output)))))
