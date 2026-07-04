;;; Session-level state transitions for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defparameter +completion-session-preserving-key-event-types+
  '(:tab :shift-tab :ctrl-l))

(defparameter +completion-session-resetting-key-event-types+
  '(:escape :ctrl-g :ctrl-c))

(defparameter +yank-session-preserving-key-event-types+
  '(:ctrl-y :alt-y))

(defparameter +argument-session-preserving-key-event-types+
  '(:alt-dot))

(defstruct (input-session-transition-policy
             (:constructor %make-input-session-transition-policy
                 (&key preserve-all-p
                       preserve-completion-p
                       preserve-yank-session-p
                       preserve-argument-session-p))
             (:conc-name %input-session-transition-policy-))
  (preserve-all-p nil :type boolean :read-only t)
  (preserve-completion-p nil :type boolean :read-only t)
  (preserve-yank-session-p nil :type boolean :read-only t)
  (preserve-argument-session-p nil :type boolean :read-only t))

(defun input-session-transition-policy-preserve-all-p (policy)
  (%input-session-transition-policy-preserve-all-p policy))

(defun input-session-transition-policy-preserve-completion-p (policy)
  (%input-session-transition-policy-preserve-completion-p policy))

(defun input-session-transition-policy-preserve-yank-session-p (policy)
  (%input-session-transition-policy-preserve-yank-session-p policy))

(defun input-session-transition-policy-preserve-argument-session-p (policy)
  (%input-session-transition-policy-preserve-argument-session-p policy))

(defun %completion-session-preserved-p (old-state state key-event-type)
  (and (eq (input-state-mode old-state) :insert)
       (eq (input-state-mode state) :insert)
       (not (member key-event-type +completion-session-resetting-key-event-types+
                    :test #'eq))
       (or (not (null (member key-event-type
                              +completion-session-preserving-key-event-types+
                              :test #'eq)))
           (let ((suggestion (input-state-suggestion state)))
             (and (stringp suggestion)
                  (plusp (length suggestion)))))))

(defun input-session-transition-policy-for-key-event (old-state state key-event)
  (let ((key-event-type (nshell.domain.input:key-event-type key-event)))
    (%make-input-session-transition-policy
     :preserve-all-p (eq key-event-type :ctrl-l)
     :preserve-completion-p (%completion-session-preserved-p old-state
                                                              state
                                                              key-event-type)
     :preserve-yank-session-p
     (not (null (member key-event-type
                        +yank-session-preserving-key-event-types+
                        :test #'eq)))
     :preserve-argument-session-p
     (not (null (member key-event-type
                        +argument-session-preserving-key-event-types+
                        :test #'eq))))))

(defun %clear-session-fields (state initargs)
  (apply #'copy-input-state-with state initargs))

(defun %clear-session-fields-when (state clear-p initargs)
  (if clear-p
      (%clear-session-fields state initargs)
      state))

(defun %apply-yank-session-policy (state policy)
  (%clear-session-fields-when
   state
   (not (input-session-transition-policy-preserve-yank-session-p policy))
   '(:last-yank-start nil
     :last-yank-end nil
     :last-yank-index nil)))

(defun %apply-argument-session-policy (state policy)
  (%clear-session-fields-when
   state
   (not (input-session-transition-policy-preserve-argument-session-p policy))
   '(:last-argument-start nil
     :last-argument-end nil
     :last-argument-index nil)))

(defun %clear-transient-session-state (state policy)
  (%apply-argument-session-policy (%apply-yank-session-policy state policy)
                                  policy))

(defun finalize-input-state-transition (old-state new-state key-event)
  (let ((policy (input-session-transition-policy-for-key-event old-state
                                                               new-state
                                                               key-event)))
    (when (input-session-transition-policy-preserve-all-p policy)
      (return-from finalize-input-state-transition new-state))
    (let ((state (%clear-transient-session-state new-state policy)))
      (if (input-session-transition-policy-preserve-completion-p policy)
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
