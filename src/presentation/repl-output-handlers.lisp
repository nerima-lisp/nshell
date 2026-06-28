;;; REPL output-event execution helpers
(in-package #:nshell.presentation)

(defmacro with-reset-rendered-prompt-state-and-prompt-cont (&body body)
  `(progn
     ,@body
     (reset-rendered-prompt-state)
     (lambda () (render-prompt-cont))))

(defmacro with-cleared-rendered-completions-and-prompt-cont (&body body)
  `(with-reset-rendered-prompt-state-and-prompt-cont
     (clear-rendered-completions)
     ,@body))

(defmacro define-output-event-handler (name wrapper &body body)
  `(defun ,name ()
     (,wrapper
      ,@body)))

(defun %elapsed-command-duration-ms (start-time end-time)
  (max 0
       (round (* 1000
                 (/ (- end-time start-time)
                    internal-time-units-per-second)))))

(defun refresh-current-input-state-suggestion (&optional (text (input-state-buffer *input-state*)))
  (let ((completion-path
          (nshell.domain.environment:env-get (ensure-environment) "PATH")))
    (setf (input-state-suggestion *input-state*)
          (compute-suggestion *history*
                              text
                              :knowledge-base *kb*
                              :path completion-path))))

(defun %history-last-argument-state (state argument start end index)
  (copy-input-state-clearing-completion
   state
   :buffer (concatenate 'string
                        (subseq (input-state-buffer state) 0 start)
                        argument
                        (subseq (input-state-buffer state) end))
   :cursor-pos (+ start (length argument))
   :last-argument-start start
   :last-argument-end (+ start (length argument))
   :last-argument-index index))

(defun %record-history-last-argument-transition (old-state new-state output)
  (setf *input-state*
        (record-undo-transition
         old-state new-state output
         (nshell.infrastructure.terminal:make-key-event :alt-dot)))
  output)

(defun insert-history-last-argument ()
  (let* ((old-state *input-state*)
         (buffer (input-state-buffer old-state))
         (start (input-state-last-argument-start old-state))
         (end (input-state-last-argument-end old-state))
         (index (input-state-last-argument-index old-state)))
    (cond
      ((and (integerp start)
            (integerp end)
            (integerp index)
            (<= 0 start end (length buffer))
            (let ((argument (nshell.domain.history:history-last-argument-at
                             *history* index)))
              (and argument
                   (string= argument (subseq buffer start end)))))
       (let ((argument (nshell.domain.history:history-last-argument-at
                        *history* (1+ index))))
         (if argument
             (let ((new-state (%history-last-argument-state
                               old-state argument start end (1+ index))))
               (%record-history-last-argument-transition
                old-state new-state :suggest-update)
               :suggest-update)
             :none)))
      (t
       (let ((argument (nshell.domain.history:history-last-argument-at
                        *history* 0)))
         (if argument
             (let ((cursor (input-state-cursor-pos old-state)))
               (multiple-value-bind (inserted-state inserted-output)
                   (insert-string-at-cursor old-state argument)
                 (let ((new-state (%history-last-argument-state
                                   inserted-state argument
                                   cursor
                                   (input-state-cursor-pos inserted-state)
                                   0)))
                   (%record-history-last-argument-transition
                    old-state new-state inserted-output)
                   inserted-output)))
             :none))))))

(defun %process-execute-output-event ()
  (clear-rendered-completions)
  (let ((text (input-state-buffer *input-state*)))
    (handler-case
      (if (string= text "")
            (with-reset-rendered-prompt-state-and-prompt-cont
              (format t "~%")
              (setf *last-command-duration-ms* nil)
              (setf *input-state* (make-repl-input-state)))
            (nshell.domain.parsing:with-parsed-command-line-case (result ast text)
              (:complete
               (with-reset-rendered-prompt-state-and-prompt-cont
                 (format t "~%")
                 (nshell.domain.history:history-add *history* text)
                 (nshell.domain.history:history-reset-navigation *history*)
                 (nshell.infrastructure.persistence:append-history-entry text)
                 (sync-exported-environment)
                 (let ((start-time (get-internal-real-time)))
                   (unwind-protect
                        (setf *last-exit-code* (or (execute-ast ast) 0))
                     (setf *last-command-duration-ms*
                           (%elapsed-command-duration-ms
                            start-time
                            (get-internal-real-time)))))
                 (setf *input-state* (make-repl-input-state))))
              (:error
               (with-reset-rendered-prompt-state-and-prompt-cont
                 (format t "~%")
                 (report-parse-diagnostics result *error-output*)
                 (setf *last-exit-code* 2
                       *last-command-duration-ms* nil
                       *input-state* (make-repl-input-state))))
              (:incomplete
               (format t "~%")
               (reset-rendered-prompt-state)
               (multiple-value-bind (continued-state output)
                   (insert-newline-at-cursor *input-state*
                                             :indent (if (or (nshell.domain.parsing:parse-diagnostic-kind-p
                                                              result :trailing-continuation)
                                                             (nshell.domain.parsing:parse-diagnostic-kind-p
                                                              result :unclosed-block))
                                                         2
                                                         0))
                 (declare (ignore output))
                 (setf *input-state* continued-state))
               (lambda () (render-prompt-cont)))))
      (error (condition)
        (with-reset-rendered-prompt-state-and-prompt-cont
          (format t "~%nshell error: ~a~%" condition)
          (setf *last-exit-code* 1
                *last-command-duration-ms* nil
                *input-state* (make-repl-input-state)))))))

(define-output-event-handler %process-complete-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (let ((candidates (input-state-last-candidates *input-state*))
          (selected-index (input-state-completion-index *input-state*)))
      (if (and candidates
               (>= selected-index 0)
               (< selected-index (length candidates))
               (let ((base-buffer (input-state-completion-base-buffer *input-state*))
                     (base-cursor (input-state-completion-base-cursor *input-state*)))
                 (and base-buffer
                      base-cursor
                      (multiple-value-bind (expected-buffer expected-cursor)
                          (apply-completion base-buffer
                                            (nth selected-index candidates)
                                            :cursor base-cursor)
                        (and (string= expected-buffer (input-state-buffer *input-state*))
                             (= expected-cursor (input-state-cursor-pos *input-state*)))))))
          (setf *completion-rendered-lines*
                (%render-completions-below-prompt
                 candidates
                 :selected-index selected-index))
          (let* ((text (input-state-buffer *input-state*))
                 (completion-path
                   (nshell.domain.environment:env-get (ensure-environment) "PATH"))
                 (candidates (when (> (length text) 0)
                               (nshell.domain.completion:complete
                                *kb* text :path completion-path))))
            (if candidates
                (progn
                  (multiple-value-bind (extended-state extended-p)
                      (maybe-extend-completion-common-prefix *input-state* candidates)
                    (declare (ignore extended-p))
                    (setf *input-state* extended-state))
                  (setf (input-state-last-candidates *input-state*) candidates)
                  (setf *completion-rendered-lines*
                        (%render-completions-below-prompt candidates)))
                (setf *input-state*
                      (clear-completion-session-state *input-state*)))))))

(define-output-event-handler %process-suggest-update-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (nshell.domain.history:history-reset-navigation *history*)
    (refresh-current-input-state-suggestion))

(define-output-event-handler %process-history-search-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (let* ((query (input-state-search-query *input-state*))
           (entries (nshell.application:interactive-history-search-use-case
                     *history* query))
           (texts (nshell.domain.history:history-entry-texts entries)))
      (setf *input-state*
            (apply-history-search-results-to-input-state *input-state* texts))))

(define-output-event-handler %process-history-prev-output-event
    with-cleared-rendered-completions-and-prompt-cont
  (let ((entry (nshell.domain.history:history-previous
                 *history*
                 (input-state-buffer *input-state*))))
    (when entry
      (setf *input-state*
            (make-repl-input-state :buffer entry :cursor-pos (length entry)))
      (refresh-current-input-state-suggestion))))

(define-output-event-handler %process-history-next-output-event
    with-cleared-rendered-completions-and-prompt-cont
  (let ((entry (nshell.domain.history:history-next *history*)))
    (when entry
      (setf *input-state*
            (make-repl-input-state :buffer entry :cursor-pos (length entry)))
      (refresh-current-input-state-suggestion))))

(define-output-event-handler %process-clear-screen-output-event
    with-reset-rendered-prompt-state-and-prompt-cont
    (nshell.infrastructure.terminal:ansi-clear-screen)
    (nshell.infrastructure.terminal:ansi-move-cursor 1 1)
    (reset-rendered-completion-state))

(define-output-event-handler %process-insert-last-argument-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (when (eq (insert-history-last-argument) :suggest-update)
      (refresh-current-input-state-suggestion)))

(define-output-event-handler %process-redraw-output-event
    with-cleared-rendered-completions-and-prompt-cont)

(define-output-event-handler %process-quit-output-event
    progn
    (setf *running* nil)
    nil)

(define-output-event-handler %process-default-output-event
    with-cleared-rendered-completions-and-prompt-cont)
