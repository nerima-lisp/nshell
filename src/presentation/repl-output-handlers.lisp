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

(defun %assistant-boundary-ok-p (result)
  (eq :ok (nshell.feature.assistant:assistant-boundary-status result)))

(defun %assistant-boundary-failure-message (result fallback)
  (or (nshell.feature.assistant:assistant-boundary-message result)
      fallback))

(defun %assistant-last-command-context ()
  (let ((entry (first (history-kit:history-entries *history*))))
    (and entry (history-kit:history-entry-text entry))))

(defun %assistant-git-context ()
  (multiple-value-bind (branch dirty-p)
      (nshell.infrastructure.acl:get-git-status (boundary-current-directory))
    (when branch
      (if dirty-p
          (format nil "~a dirty" branch)
          branch))))

(defun %assistant-context ()
  (nshell.feature.assistant:assemble-assistant-context
   :command (%assistant-last-command-context)
   :exit *last-exit-code*
   :duration-ms *last-command-duration-ms*
   :cwd (boundary-current-directory)
   :git-status (%assistant-git-context)
   :last-output nil
   :environment-names
   (mapcar #'nshell.domain.environment:env-binding-name
           (nshell.domain.environment:env-bindings (ensure-environment)))))

(defun %assistant-payload-field (payload key)
  (when (listp payload)
    (loop for entry in payload
          when (and (consp entry)
                    (stringp (car entry))
                    (string= key (car entry)))
            do (return (cdr entry)))))

(defun %assistant-content-proposal-text (content)
  (cond
    ((stringp content) content)
    ((listp content)
     (or (%assistant-proposal-text content)
         (some #'%assistant-content-proposal-text content)))))

(defun %assistant-proposal-text (payload)
  (cond
    ((null payload) nil)
    ((stringp payload) payload)
    ((listp payload)
     (or (let ((command (%assistant-payload-field payload "command")))
           (and (stringp command) command))
         (%assistant-proposal-text
          (%assistant-payload-field payload "structured_output"))
         (let ((text (%assistant-payload-field payload "text")))
           (and (stringp text) text))
         (%assistant-proposal-text
          (%assistant-payload-field payload "message"))
         (%assistant-content-proposal-text
          (%assistant-payload-field payload "content"))))))

(defun %assistant-proposal-assessment (text)
  (let ((result (nshell.domain.parsing:parse-command-line text)))
    (if (nshell.domain.parsing:parse-complete-p result)
        (values
         :classified
         (nshell.feature.assistant:classify-ast
          (nshell.domain.parsing:parse-result-ast result))
         nil)
        (values :parse-error nil
                (format nil "解釈できない提案: ~a" text)))))

(defun %install-assistant-proposal (text)
  (let ((state *input-state*))
    (setf *input-state*
          (copy-input-state-clearing-completion
           state
           :buffer text
           :cursor-pos (length text)
           :mode :insert
           :ask-original-buffer :clear
           :ask-original-cursor :clear
           :undo-stack (cons (input-edit-snapshot state)
                             (input-state-undo-stack state))
           :redo-stack nil))))

(defun %assistant-proposal-panel (classification reason)
  (render-transient-panel
   (list (format nil "AI proposal [~(~a~)]: ~a"
                 classification reason))))

(defun %assistant-event-reason (event fallback)
  (let ((payload (nshell.feature.assistant:assistant-model-event-payload event)))
    (or (and (listp payload)
             (or (%assistant-payload-field payload "message")
                 (%assistant-payload-field payload "reason")
                 (%assistant-payload-field payload "error")))
        fallback)))

(defun %return-from-ask-with-message (message)
  (clear-rendered-completions)
  (clear-rendered-transient-panel)
  (clear-rendered-prompt)
  (format t "~%nshell: ~a~%" message)
  (setf *input-state* (make-repl-input-state)
        *assistant-model-event-handler* nil
        *assistant-turn-started-at* nil
        *assistant-command-origin* :typed
        *assistant-command-confirmed-p* nil)
  (reset-rendered-prompt-state)
  (lambda () (render-prompt-cont)))

(define-output-event-handler %process-ask-start-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (setf *assistant-last-cancel-at* nil))

(define-output-event-handler %process-ask-cancel-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (refresh-current-input-state-suggestion))

(defun %ask-model-terminal-event-p (event)
  (member (nshell.feature.assistant:assistant-model-event-kind event)
          '(:result :stream-ended :stream-error :rate-limit-event)
          :test #'eq))

(defun %handle-ask-model-event (event)
  (case (nshell.feature.assistant:assistant-model-event-kind event)
    (:result
     (let ((proposal
             (%assistant-proposal-text
              (nshell.feature.assistant:assistant-model-event-payload event))))
       (if (or (null proposal) (zerop (length proposal)))
           (%return-from-ask-with-message "AI 応答に提案がありません")
           (multiple-value-bind (status classification reason)
               (%assistant-proposal-assessment proposal)
             (setf *assistant-model-event-handler* nil
                   *assistant-turn-started-at* nil)
             (clear-rendered-transient-panel)
             (if (eq status :parse-error)
                 (progn
                   (setf *input-state* (make-repl-input-state)
                         *assistant-command-origin* :typed
                         *assistant-command-confirmed-p* nil)
                   (render-transient-panel (list reason))
                   (render-prompt-cont))
                 (case (nshell.feature.assistant:assistant-safety-result-classification
                        classification)
                   (:block
                    (setf *input-state* (make-repl-input-state)
                          *assistant-command-origin* :typed
                          *assistant-command-confirmed-p* nil)
                    (%assistant-proposal-panel
                     :block
                     (nshell.feature.assistant:assistant-safety-result-reason
                      classification))
                    (render-prompt-cont))
                   (otherwise
                    (%install-assistant-proposal proposal)
                    (setf *assistant-command-origin* :proposal
                          *assistant-command-confirmed-p*
                            (eq :safe
                                (nshell.feature.assistant:assistant-safety-result-classification
                                 classification)))
                    (%assistant-proposal-panel
                     (nshell.feature.assistant:assistant-safety-result-classification
                      classification)
                     (nshell.feature.assistant:assistant-safety-result-reason
                      classification))
                    (render-prompt-cont))))))))
    ((:stream-error :rate-limit-event)
     (%return-from-ask-with-message
      (%assistant-event-reason event "AI 応答を受け取れませんでした")))
    (:stream-ended
     (%return-from-ask-with-message "AI 応答が終了しました"))
    (otherwise
     (when *assistant-turn-started-at*
       (render-assistant-progress-panel *assistant-turn-started-at*)))))

(defun %process-ask-submit-output-event ()
  (clear-rendered-completions)
  (let* ((text (input-state-buffer *input-state*))
         (generation
           (setf *assistant-turn-generation*
                 (nshell.feature.assistant:next-assistant-turn-generation
                  *assistant-turn-generation*)))
         (raw-payload
           (nshell.feature.assistant:make-assistant-user-payload
            text :context (%assistant-context)))
         (payload (nshell.feature.assistant:redact-payload raw-payload))
         (start-result (nshell.feature.assistant:assistant-model-start)))
    (setf *assistant-last-cancel-at* nil)
    (setf *assistant-turn-started-at* (boundary-monotonic))
    (unless (%assistant-boundary-ok-p start-result)
      (return-from %process-ask-submit-output-event
        (%return-from-ask-with-message
         (format nil "AI 未接続: ~a"
                 (%assistant-boundary-failure-message
                  start-result "assistant model boundary is unavailable")))))
    (nshell.feature.assistant:append-assistant-audit-entry payload nil)
    (let ((request-result
            (nshell.feature.assistant:assistant-model-request
             generation payload)))
      (unless (%assistant-boundary-ok-p request-result)
        (return-from %process-ask-submit-output-event
          (%return-from-ask-with-message
           (format nil "AI 要求を送信できません: ~a"
                   (%assistant-boundary-failure-message
                    request-result "assistant model request failed")))))
      (setf *assistant-model-event-handler* #'%handle-ask-model-event)
      (render-prompt-cont)
      (render-assistant-progress-panel *assistant-turn-started-at*)
      (lambda () (read-key-cont)))))

(defun %assistant-cancel-repeat-p (now)
  (let ((last-cancel-at *assistant-last-cancel-at*))
    (and last-cancel-at
         (<= 0 (- now last-cancel-at) +assistant-cancel-window-ticks+))))

(defun %process-ask-cancel-turn-output-event ()
  (let* ((now (boundary-monotonic))
         (repeat-p (%assistant-cancel-repeat-p now))
         (generation
           (setf *assistant-turn-generation*
                 (nshell.feature.assistant:next-assistant-turn-generation
                  *assistant-turn-generation*)))
         (stop-result (when repeat-p
                        (nshell.feature.assistant:assistant-model-stop)))
         (start-result (when repeat-p
                         (nshell.feature.assistant:assistant-model-start))))
    (declare (ignore generation))
    (clear-rendered-completions)
    (clear-rendered-transient-panel)
    (clear-rendered-prompt)
    (setf *input-state* (make-repl-input-state)
          *assistant-model-event-handler* nil
          *assistant-turn-started-at* nil
          *assistant-last-cancel-at* (unless repeat-p now))
    (format t "~%nshell: AI turn canceled~%")
    (when (and repeat-p
               (not (%assistant-boundary-ok-p start-result)))
      (format t "nshell: AI sidecar restart failed: ~a~%"
              (%assistant-boundary-failure-message
               start-result "assistant model boundary is unavailable")))
    (when (and repeat-p
               (not (%assistant-boundary-ok-p stop-result)))
      (format t "nshell: AI sidecar stop failed: ~a~%"
              (%assistant-boundary-failure-message
               stop-result "assistant model boundary is unavailable")))
    (reset-rendered-prompt-state)
    (lambda () (render-prompt-cont))))
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
          (timestamp (get-universal-time))
          (cwd (boundary-current-directory))
          (exit-code nil))
      (unwind-protect
           (setf exit-code (or (execute-ast ast) 0))
        (let ((recorded-exit-code (if (integerp exit-code) exit-code 1)))
          (let ((duration-ms (%elapsed-command-duration-ms
                              start-time
                              (boundary-monotonic))))
            (setf *last-exit-code* recorded-exit-code
                  *last-command-duration-ms* duration-ms)
            (when *history-persistence-enabled-p*
              (multiple-value-bind (history record)
                  (nshell.infrastructure.persistence::history-record-add
                   *history* text
                   :timestamp timestamp
                   :cwd cwd
                   :exit-code recorded-exit-code
                   :duration-ms duration-ms
                   :origin :typed)
                (declare (ignore history))
                (history-kit:history-reset-navigation *history*)
                (let ((nshell.infrastructure.persistence::*history-record-to-append*
                        record))
                  (nshell.infrastructure.persistence:append-history-entry text))))))
    (setf *input-state* (make-repl-input-state))))))

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
