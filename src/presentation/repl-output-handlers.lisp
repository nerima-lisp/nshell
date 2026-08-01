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

(defun %history-last-argument-selected-p (state)
  (let* ((buffer (input-state-buffer state))
         (start (input-state-last-argument-start state))
         (end (input-state-last-argument-end state))
         (index (input-state-last-argument-index state)))
    (and (integerp start)
         (integerp end)
         (integerp index)
         (<= 0 start end (length buffer))
         (let ((argument (nshell.domain.history:history-last-argument-at
                          *history* index)))
           (and argument
                (string= argument (subseq buffer start end)))))))

(defun %insert-history-last-argument-selected (state)
  (let* ((start (input-state-last-argument-start state))
         (end (input-state-last-argument-end state))
         (index (input-state-last-argument-index state))
         (argument (nshell.domain.history:history-last-argument-at
                    *history* (1+ index))))
    (if argument
        (let ((new-state (%history-last-argument-state
                          state argument start end (1+ index))))
          (%record-history-last-argument-transition
           state new-state :suggest-update)
          :suggest-update)
        :none)))

(defun %insert-history-last-argument-initial (state)
  (let ((argument (nshell.domain.history:history-last-argument-at *history* 0)))
    (if argument
        (let ((cursor (input-state-cursor-pos state)))
          (multiple-value-bind (inserted-state inserted-output)
              (insert-string-at-cursor state argument)
            (let ((new-state (%history-last-argument-state
                              inserted-state argument
                              cursor
                              (input-state-cursor-pos inserted-state)
                              0)))
              (%record-history-last-argument-transition
               state new-state inserted-output)
              inserted-output)))
        :none)))

(defun %record-history-last-argument-transition (old-state new-state output)
  (setf *input-state*
        (record-undo-transition
         old-state new-state output
         (nshell.infrastructure.terminal:make-key-event :alt-dot)))
  output)

(defun insert-history-last-argument ()
  (let ((old-state *input-state*))
    (if (%history-last-argument-selected-p old-state)
        (%insert-history-last-argument-selected old-state)
        (%insert-history-last-argument-initial old-state))))

(defun %execute-empty-input ()
  (with-reset-rendered-prompt-state-and-prompt-cont
    (format t "~%")
    (setf *last-command-duration-ms* nil)
    (setf *input-state* (make-repl-input-state))))

(defun %execute-complete-command (ast text)
  (with-reset-rendered-prompt-state-and-prompt-cont
    (format t "~%")
    (history-kit:history-add *history* text)
    (history-kit:history-reset-navigation *history*)
    (nshell.infrastructure.persistence:append-history-entry text)
    (sync-exported-environment)
    ;; Time the command through the clock boundary (real clock == monotonic
    ;; get-internal-real-time), so a fake clock makes duration deterministic.
    (let ((start-time (boundary-monotonic)))
      (unwind-protect
           (setf *last-exit-code* (or (execute-ast ast) 0))
        (setf *last-command-duration-ms*
              (%elapsed-command-duration-ms
               start-time
               (boundary-monotonic)))))
    (setf *input-state* (make-repl-input-state))))

(defun %execute-parse-error (result)
  (with-reset-rendered-prompt-state-and-prompt-cont
    (format t "~%")
    (report-parse-diagnostics result *error-output*)
    (setf *last-exit-code* 2
          *last-command-duration-ms* nil
          *input-state* (make-repl-input-state))))

(defun %execute-incomplete-command (result)
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
  (lambda () (render-prompt-cont)))

(defun %execute-command-line (text)
  (handler-case
      (if (string= text "")
          (%execute-empty-input)
          (nshell.domain.parsing:with-parsed-command-line-case (result ast text)
              (:complete
               (%execute-complete-command ast text))
            (:error
             (%execute-parse-error result))
            (:incomplete
             (%execute-incomplete-command result))))
    (error (condition)
      (with-reset-rendered-prompt-state-and-prompt-cont
        (format t "~%nshell error: ~a~%" condition)
        (setf *last-exit-code* 1
              *last-command-duration-ms* nil
              *input-state* (make-repl-input-state))))))

(defun %process-execute-output-event ()
  (clear-rendered-completions)
  (%execute-command-line (input-state-buffer *input-state*)))

(define-output-event-handler %process-complete-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (if (%completion-session-valid-p *input-state*)
        (let ((candidates (input-state-last-candidates *input-state*))
              (selected-index (input-state-completion-index *input-state*)))
          (setf *completion-rendered-lines*
                (%render-completions-below-prompt
                 candidates
                 :selected-index selected-index)))
        (multiple-value-bind (refreshed-state candidates)
            (%refresh-completion-session-state *input-state*)
          (setf *input-state* refreshed-state)
          (when candidates
            (setf *completion-rendered-lines*
                  (%render-completions-below-prompt candidates))))))

(define-output-event-handler %process-suggest-update-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (history-kit:history-reset-navigation *history*)
    (refresh-current-input-state-suggestion))

(define-output-event-handler %process-history-search-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (let* ((query (input-state-search-query *input-state*))
           (entries (nshell.application:interactive-history-search-use-case
                     *history* query))
           (texts (history-kit:history-entry-texts entries)))
      (setf *input-state*
            (apply-history-search-results-to-input-state *input-state* texts))))

(define-output-event-handler %process-history-prev-output-event
    with-cleared-rendered-completions-and-prompt-cont
  (let ((entry (history-kit:history-previous
                 *history*
                 (input-state-buffer *input-state*))))
    (when entry
      (setf *input-state*
            (make-repl-input-state :buffer entry :cursor-pos (length entry)))
      (refresh-current-input-state-suggestion))))

(define-output-event-handler %process-history-next-output-event
    with-cleared-rendered-completions-and-prompt-cont
  (let ((entry (history-kit:history-next *history*)))
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
