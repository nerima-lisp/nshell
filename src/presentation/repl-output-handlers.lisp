;;; REPL output-event execution helpers
(in-package #:nshell.presentation)

(defmacro with-reset-rendered-prompt-state-and-prompt-cont (&body body)
  "For handlers whose BODY leaves the terminal in a state CLEAR-RENDERED-PROMPT
cannot navigate from the old geometry -- BODY already committed the prior
render to scrollback with its own output (a trailing newline, a screen clear),
or handed the terminal to a program outside nshell's tracking. The next
RENDER-PROMPT-CONT must start from a blank slate rather than walk rows
computed against a layout that no longer describes what is on screen."
  `(progn
     ,@body
     (reset-rendered-prompt-state)
     (lambda () (render-prompt-cont))))

(defmacro with-cleared-rendered-completions-and-reset-prompt-cont (&body body)
  `(with-reset-rendered-prompt-state-and-prompt-cont
     (clear-rendered-completions)
     ,@body))

(defmacro with-cleared-rendered-completions-and-prompt-cont (&body body)
  "For in-place redraws (typing, cursor movement, history/completion
browsing) where the previously rendered prompt is still on screen exactly as
*PROMPT-RENDERED-LINES* and *PROMPT-RENDERED-CURSOR-ROW* describe it. The
returned RENDER-PROMPT-CONT calls CLEAR-RENDERED-PROMPT, which needs that live
geometry to walk up and erase every row of a wrapped prompt+input; resetting
it here first -- as the reset-based wrapper does -- makes CLEAR-RENDERED-PROMPT
believe nothing is rendered, so it erases only the current line and leaves the
wrapped line's other rows on screen as stale duplicates."
  `(progn
     (clear-rendered-completions)
     ,@body
     (lambda () (render-prompt-cont))))

(defmacro define-output-event-handler (name wrapper &body body)
  `(defun ,name ()
     (,wrapper
      ,@body)))

(defmacro %set-command-failure-state (exit-code)
  `(progn
     (setf *last-exit-code* ,exit-code
           *last-command-duration-ms* nil
           *input-state* (make-repl-input-state))
     (dolist (name '("?" "status"))
       (setf *environment*
             (nshell.domain.environment:env-set
              (ensure-environment) name (princ-to-string *last-exit-code*) nil)))))

(defun %elapsed-command-duration-ms (start-time end-time)
  (max 0
       (round (* 1000
                 (/ (- end-time start-time)
                    internal-time-units-per-second)))))

(defun refresh-current-input-state-suggestion (&optional (text (input-state-buffer *input-state*)))
  (let ((completion-path
          (nshell.domain.environment:env-get (ensure-environment) "PATH"))
        (filesystem (nshell.infrastructure.acl:make-host-filesystem)))
    (setf (input-state-suggestion *input-state*)
          (compute-suggestion *history*
                              text
                              :knowledge-base *kb*
                              :path completion-path
                              :filesystem filesystem
                              :alias-table *aliases*
                              :function-table *functions*))))

(defun %execute-empty-input ()
  (with-reset-rendered-prompt-state-and-prompt-cont
    (format t "~%")
    (setf *last-command-duration-ms* nil)
    (setf *input-state* (make-repl-input-state))))

(defun %execute-complete-command (ast text)
  (with-reset-rendered-prompt-state-and-prompt-cont
    (format t "~%")
    (sync-exported-environment)
    ;; Time the command through the clock boundary (real clock == monotonic
    ;; get-internal-real-time), so a fake clock makes duration deterministic.
    (let ((start-time (boundary-monotonic))
          (exit-code nil))
      (unwind-protect
           (setf exit-code (or (execute-ast ast) 0))
        (let ((recorded-exit-code (if (integerp exit-code) exit-code 1)))
          (setf *last-exit-code* recorded-exit-code
                *last-command-duration-ms*
                (%elapsed-command-duration-ms
                 start-time
                 (boundary-monotonic)))
          (when *history-persistence-enabled-p*
            (history-kit:history-add *history* text
                                     :exit-code recorded-exit-code)
            (history-kit:history-reset-navigation *history*)
            (nshell.infrastructure.persistence:append-history-entry text))))
    (setf *input-state* (make-repl-input-state)))))

(defun %execute-parse-error (result)
  (with-reset-rendered-prompt-state-and-prompt-cont
    (format t "~%")
    (report-parse-diagnostics result *error-output*)
    (%set-command-failure-state 2)))

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
          (multiple-value-bind (expanded-text expansion-error)
              (nshell.domain.history:history-expand-line *history* text)
            (if expansion-error
                (with-reset-rendered-prompt-state-and-prompt-cont
                 (format t "~%nshell: ~a~%" expansion-error)
                 (%set-command-failure-state 2))
                (nshell.domain.parsing:with-parsed-command-line-case
                 (result ast expanded-text)
                 (:complete
                  (%execute-complete-command ast expanded-text))
                 (:error
                  (%execute-parse-error result))
                 (:incomplete
                  (%execute-incomplete-command result))))))
    (nshell.infrastructure.terminal:terminal-mode-operation-failed (condition)
      (format *error-output* "~%nshell: ~a~%" condition)
      (%set-command-failure-state 1)
      (setf *running* nil)
      nil)
    (error (condition)
           (with-reset-rendered-prompt-state-and-prompt-cont
            (format t "~%nshell error: ~a~%" condition)
            (%set-command-failure-state 1)))))

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
