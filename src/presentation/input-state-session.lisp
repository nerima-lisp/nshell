;;; Session-level state transitions for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defun input-session-reduction (state output)
  (%make-input-session-reduction state output))

(defmacro define-session-clear (name kind slots)
  `(progn
     (defun ,(intern (format nil "%~A-OVERRIDES" name)) ()
       ',(loop for slot in slots append (list (intern (symbol-name slot) :keyword) nil)))
     (defun ,name ()
       (%make-transient-session-clear
        ,kind
        (,(intern (format nil "%~A-OVERRIDES" name)))))))

(defun %assert-transient-session-clear-kind (clear kind)
  (unless (and (%transient-session-clear-p clear)
               (eq kind (%transient-session-clear-kind clear)))
    (error "Expected transient session clear kind ~S, got ~S"
           kind
           clear))
  clear)

(define-session-clear yank-session-clear :yank
  (last-yank-start last-yank-end last-yank-index))

(define-session-clear argument-session-clear :argument
  (last-argument-start last-argument-end last-argument-index))

(defun apply-transient-session-clear (state clear)
  (check-type clear %transient-session-clear)
  (apply #'copy-input-state-with
         state
         (%transient-session-clear-overrides clear)))

(defun apply-yank-session-clear (state clear)
  (apply-transient-session-clear
   state
   (%assert-transient-session-clear-kind clear :yank)))

(defun apply-argument-session-clear (state clear)
  (apply-transient-session-clear
   state
   (%assert-transient-session-clear-kind clear :argument)))

(defun input-session-reduction-for-key-event (state key-event)
  (multiple-value-bind (new-state output)
      (case (input-state-mode state)
        (:search (reduce-search-input-state state key-event))
        ((:vi-command :vi-visual :vi-d :vi-c)
         (reduce-vi-input-state state key-event))
        (t (reduce-insert-input-state state key-event)))
    (input-session-reduction new-state output)))

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

(defun %clear-transient-session-when (state clear-p clear apply-clear)
  (if clear-p
      (funcall apply-clear state clear)
      state))

(defmacro define-session-policy-applier
    (name preserve-accessor clear-constructor clear-applier)
  `(defun ,name (state policy)
     (%clear-transient-session-when
      state
      (not (,preserve-accessor policy))
      (,clear-constructor)
      #',clear-applier)))

(define-session-policy-applier
    %apply-yank-session-policy
    input-session-transition-policy-preserve-yank-session-p
    yank-session-clear
    apply-yank-session-clear)

(define-session-policy-applier
    %apply-argument-session-policy
    input-session-transition-policy-preserve-argument-session-p
    argument-session-clear
    apply-argument-session-clear)

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
    (let* ((mouse-event-p
             (eq :mouse (nshell.domain.input:key-event-type key-event)))
           (working-state (if mouse-event-p
                              state
                              (%clear-mouse-selection-state state)))
           (reduction (input-session-reduction-for-key-event working-state
                                                              key-event))
           (output (input-session-reduction-output reduction))
           (final-state
             (finalize-input-state-transition
              working-state
              (input-session-reduction-state reduction)
              key-event)))
        (values (record-undo-transition state final-state output key-event)
                output))))
