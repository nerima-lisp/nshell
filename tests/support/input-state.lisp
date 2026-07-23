(in-package #:nshell/test)


(defun input-key-event (type &optional char number data)
  (nshell.domain.input:make-key-event type char number data))

(defun reduce-once (state type &optional char number data)
  (nshell.presentation:reduce-input-state
   state
   (input-key-event type char number data)))

(defun reduce-once-state (state type &optional char number data)
  (nth-value 0 (reduce-once state type char number data)))

(defmacro with-kill-then-yank ((killed-var yanked-var
                                &optional kill-output-var yank-output-var)
                               state
                               kill-type
                               &body body)
  (let ((killed-state (gensym "KILLED-STATE"))
        (kill-output (gensym "KILL-OUTPUT"))
        (yanked-state (gensym "YANKED-STATE"))
        (yank-output (gensym "YANK-OUTPUT")))
    `(multiple-value-bind (,@(list killed-state)
                           ,@(when kill-output-var (list kill-output)))
         (reduce-once ,state ,kill-type)
       (multiple-value-bind (,@(list yanked-state)
                             ,@(when yank-output-var (list yank-output)))
           (reduce-once ,killed-state :ctrl-y)
         (let ((,killed-var ,killed-state)
               (,yanked-var ,yanked-state)
               ,@(when kill-output-var
                   `((,kill-output-var ,kill-output)))
               ,@(when yank-output-var
                   `((,yank-output-var ,yank-output))))
           ,@body)))))

(defmacro with-reduced-input-state ((state-var &optional output-var) reduction-form &body body)
  (if output-var
      `(multiple-value-bind (,state-var ,output-var)
           ,reduction-form
         (declare (ignorable ,state-var ,output-var))
         ,@body)
      (let ((ignored-output (gensym "OUTPUT")))
        `(multiple-value-bind (,state-var ,ignored-output)
             ,reduction-form
           (declare (ignorable ,state-var ,ignored-output))
           ,@body))))

(defmacro with-reduced-input-states (state steps &body body)
  (labels ((expand (current-state remaining)
             (if (endp remaining)
                 `(progn ,@body)
                 (destructuring-bind ((state-var &optional output-var)
                                      event-type
                                      &rest event-args)
                     (first remaining)
                   (let ((ignored-output (gensym "OUTPUT")))
                     `(multiple-value-bind (,@(list state-var)
                                            ,@(if output-var
                                                  (list output-var)
                                                  (list ignored-output)))
                          (reduce-once ,current-state ,event-type ,@event-args)
                        (declare (ignorable ,state-var
                                            ,@(if output-var
                                                  (list output-var)
                                                  (list ignored-output))))
                         ,(expand state-var (rest remaining))))))))
    (expand state steps)))

(defmacro with-vi-command-state ((state-var state-form) &body body)
  "Bind STATE-VAR to STATE-FORM after entering vi command mode with ESC."
  `(let ((nshell.presentation::*vi-mode-enabled* t))
     (let ((,state-var (reduce-once-state ,state-form :escape)))
       ,@body)))

(defun input-state (&rest initargs)
  (apply #'nshell.presentation:make-input-state initargs))

(defun %completion-session-initargs (&key
                                     completion-index
                                     completion-base-buffer
                                     completion-base-cursor
                                     last-candidates
                                     suggestion)
  (append (when (not (null completion-index))
            (list :completion-index completion-index))
          (when completion-base-buffer
            (list :completion-base-buffer completion-base-buffer))
          (when (not (null completion-base-cursor))
            (list :completion-base-cursor completion-base-cursor))
          (when last-candidates
            (list :last-candidates last-candidates))
          (when suggestion
            (list :suggestion suggestion))))

(defun completion-session-state (&rest initargs)
  (labels ((present-p (key)
             (loop for candidate-key in initargs by #'cddr
                   thereis (eq candidate-key key))))
    (apply #'input-state
           (append initargs
                   (unless (present-p :completion-index)
                     '(:completion-index -1))
                   (unless (present-p :completion-base-buffer)
                     '(:completion-base-buffer nil))
                   (unless (present-p :completion-base-cursor)
                     '(:completion-base-cursor nil))
                   (unless (present-p :last-candidates)
                     '(:last-candidates nil))
                   (unless (present-p :suggestion)
                     '(:suggestion nil))))))

(defun history-search-state (&key
                             (buffer "")
                             cursor-pos
                             (query "")
                             original-buffer
                             original-cursor
                             (index 0)
                             completion-index
                             completion-base-buffer
                             completion-base-cursor
                             last-candidates
                             suggestion)
  (let ((base-buffer (or original-buffer buffer)))
    (apply #'input-state
           (append (list :mode :search
                         :buffer buffer
                         :cursor-pos (or cursor-pos (length buffer))
                         :search-query query
                         :search-original-buffer base-buffer
                         :search-original-cursor (or original-cursor
                                                     (length base-buffer))
                         :search-index index)
                   (%completion-session-initargs
                    :completion-index completion-index
                    :completion-base-buffer completion-base-buffer
                    :completion-base-cursor completion-base-cursor
                    :last-candidates last-candidates
                    :suggestion suggestion)))))

(defmacro with-expected-input-state-reduction ((state-var output-var)
                                               state-form
                                               reduction-form
                                               expected-output
                                               state-args
                                               &body body)
  `(let ((state ,state-form))
     (declare (ignorable state))
     (with-reduced-input-state (,state-var ,output-var)
         ,reduction-form
       (declare (ignorable ,state-var ,output-var))
       (is-input-state ,state-var ,@state-args)
       (expect ,expected-output :to-be ,output-var)
       ,@body)))

(defmacro with-expected-noop-input-state-reductions ((state-var output-var)
                                                     event
                                                     states
                                                     &body body)
  `(dolist (state ,states)
     (with-expected-input-state-reduction (,state-var ,output-var)
         state
         (reduce-once state ,event)
         :none
         (:buffer (nshell.presentation:input-state-buffer state)
          :cursor-pos (nshell.presentation:input-state-cursor-pos state))
       ,@body)))

(defmacro with-vi-visual-state ((command-state-var state-form visual-state-var)
                                &body body)
  `(with-vi-command-state (,command-state-var ,state-form)
     (with-reduced-input-state (,visual-state-var)
         (reduce-once ,command-state-var :char #\v)
       ,@body)))

(defmacro with-expected-suggestion-reduction ((state-var output-var)
                                              (buffer cursor-pos suggestion event)
                                              expected-buffer
                                              expected-cursor-pos
                                              expected-suggestion
                                              expected-output
                                              &body body)
  `(with-expected-input-state-reduction (,state-var ,output-var)
       (input-state
        :buffer ,buffer
        :cursor-pos ,cursor-pos
        :suggestion ,suggestion)
       (reduce-once state ,event)
       ,expected-output
       (:buffer ,expected-buffer
        :cursor-pos ,expected-cursor-pos
        :suggestion ,expected-suggestion)
     ,@body))

(defun read-key-events-from-string (text)
  (let ((*standard-input* (make-string-input-stream text)))
    (loop for event = (nshell.infrastructure.terminal:read-key-event)
          while event
          collect event)))

(defun single-key-event-from-string (text)
  (first (read-key-events-from-string text)))

(defun esc-sequence (suffix)
  (concatenate 'string (string #\Esc) suffix))

(defun apply-key-events-to-input-state (state events)
  (loop with current = state
        for event in events
        do (with-reduced-input-state (next-state)
               (nshell.presentation:reduce-input-state current event)
             (setf current next-state))
        finally (return current)))

(defun is-maybe-string (expected actual)
  (if expected
      (expect expected :to-equal actual)
      (expect actual :to-be-null)))

(defun is-maybe-number (expected actual)
  (if expected
      (expect expected :to-equal actual)
      (expect actual :to-be-null)))

(defun is-maybe-symbol (expected actual)
  (if expected
      (expect expected :to-be actual)
      (expect actual :to-be-null)))
