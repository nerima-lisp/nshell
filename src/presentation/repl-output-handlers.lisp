;;; REPL output-event execution helpers
(in-package #:nshell.presentation)
(defun %read-command-failure-restart-choice (condition continue-restart return-restart)
  (let ((selected-p nil))
    (format t
            "~%nshell: ~a failed with status ~d.~%[1] Ignore and continue; Ctrl-C returns to the prompt.~%> "
            (nshell.application:command-failed-command condition)
            (nshell.application:command-failed-status condition))
    (finish-output)
    (loop for event =
            (nshell.infrastructure.terminal:read-key-event
             :interrupt-predicate
             (lambda ()
               (when (nshell.infrastructure.acl:consume-sigint-received-p)
                 t)))
          for event-type =
            (and event (nshell.domain.input:key-event-type event))
          do (cond
               ((null event)
                (error "End of input while waiting for command failure choice."))
               ((eq event-type :ctrl-c)
                (terpri)
                (invoke-restart
                 return-restart
                 (nshell.application:command-failed-status condition)))
               ((eq event-type :char)
                (let ((char (nshell.domain.input:key-event-char event)))
                  (if (char= char (code-char 49))
                      (unless selected-p
                        (setf selected-p t)
                        (write-char char)
                        (finish-output))
                      (setf selected-p nil))))
               ((eq event-type :backspace)
                (when selected-p
                  (write-string (format nil "~c ~c" (code-char 8) (code-char 8)))
                  (finish-output))
                (setf selected-p nil))
               ((eq event-type :enter)
                (terpri)
                (if selected-p
                    (invoke-restart continue-restart)
                    (progn
                      (format t "Enter 1 to ignore and continue, or press Ctrl-C to return to the prompt.~%> ")
                      (finish-output))))
               (t
                (setf selected-p nil))))))
(defun call-with-command-failure-restarts (thunk)
  (let ((nshell.application:*interactive-top-level-p* t))
    (let ((results
            (multiple-value-list
             (restart-case
                 (handler-bind
                     ((nshell.application:command-failed
                        (lambda (condition)
                          (let ((continue-restart
                                  (find-restart
                                   'nshell.application::continue-command-failure
                                   condition)))
                            (when continue-restart
                              (%read-command-failure-restart-choice
                               condition
                               continue-restart
                               (find-restart
                                'return-command-failure-to-prompt)))))))
                   (funcall thunk))
               (return-command-failure-to-prompt (status)
                 (values nil status))))))
      (unless (integerp (second results))
        (error 'type-error :datum (second results) :expected-type 'integer))
      (values-list results))))

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
           *last-command-output* nil
           *failure-explain-available-p* (not (zerop ,exit-code))
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
          (apply #'compute-suggestion *history*
                 text
                 :knowledge-base *kb*
                 :path completion-path
                 :filesystem filesystem
                 :alias-table *aliases*
                 :function-table *functions*
                 (repl-completion-environment-arguments)))))

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
  (let ((bindings
          (nshell.domain.environment:env-bindings (ensure-environment))))
    (nshell.feature.assistant:assemble-assistant-context
     :command (%assistant-last-command-context)
     :exit *last-exit-code*
     :duration-ms *last-command-duration-ms*
     :cwd (boundary-current-directory)
     :git-status (%assistant-git-context)
     :last-output *last-command-output*
     :environment-names
     (mapcar #'nshell.domain.environment:env-binding-name bindings)
     :denylist-paths
     nshell.feature.assistant:+assistant-default-denylist-paths+
     :denylist-commands
     nshell.feature.assistant:+assistant-default-denylist-commands+
     :denylist-values
     (%assistant-environment-denylist-values bindings))))

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
  (if (%repl-new-reader-route-enabled-p)
      (handler-case
          (let ((reader-results
                  (nshell.domain.parsing:read-submission
                   text
                   :reader-context (%repl-reader-context-for-source text))))
            (if (and
                 reader-results
                 (every
                  (function nshell.domain.parsing:reader-result-p)
                  reader-results))
                (values
                 :classified
                 (nshell.feature.assistant:classify-ast reader-results)
                 nil)
                (values :parse-error nil
                        (format nil "解釈できない提案: ~a" text))))
        (nshell.domain.parsing:sexp-reader-error ()
          (values :parse-error nil
                  (format nil "解釈できない提案: ~a" text))))
      (let ((result (nshell.domain.parsing:parse-command-line text)))
        (if (nshell.domain.parsing:parse-complete-p result)
            (values
             :classified
             (nshell.feature.assistant:classify-ast
              (nshell.domain.parsing:parse-result-ast result))
             nil)
            (values :parse-error nil
                    (format nil "解釈できない提案: ~a" text))))))

(defun %assistant-explain-text (payload)
  (labels ((payload-text (value)
             (cond
               ((stringp value) value)
               ((consp value) (object-text value))))
           (object-text (object)
             (or (let ((text (%assistant-payload-field object "explanation")))
                   (and (stringp text) text))
                 (let ((text (%assistant-payload-field object "answer")))
                   (and (stringp text) text))
                 (let ((text (%assistant-payload-field object "text")))
                   (and (stringp text) text))
                 (payload-text (%assistant-payload-field object "result"))
                 (payload-text (%assistant-payload-field object "message"))
                 (let ((content (%assistant-payload-field object "content")))
                   (when content
                     (content-text content)))))
           (content-text (content)
             (cond
               ((stringp content) content)
               ((consp content)
                (or (object-text content)
                    (some #'payload-text content))))))
    (payload-text payload)))

(defun %assistant-explain-candidate-text (value)
  (cond
    ((stringp value) value)
    ((listp value)
     (or (let ((command (%assistant-payload-field value "command")))
           (and (stringp command) command))
         (let ((text (%assistant-payload-field value "text")))
           (and (stringp text) text))
         (let ((command (%assistant-payload-field value "command_line")))
           (and (stringp command) command))))))

(defun %assistant-explain-candidates (payload)
  (let* ((structured (%assistant-payload-field payload "structured_output"))
         (source (or (%assistant-payload-field structured "next_steps")
                     (%assistant-payload-field structured "next-steps")
                     (%assistant-payload-field structured "suggestions")
                     (%assistant-payload-field payload "next_steps")
                     (%assistant-payload-field payload "next-steps")
                     (%assistant-payload-field payload "suggestions")))
         (items (cond
                  ((null source) nil)
                  ((stringp source) (list source))
                  ((and (listp source)
                        (or (%assistant-payload-field source "command")
                            (%assistant-payload-field source "text")
                            (%assistant-payload-field source "command_line")))
                   (list source))
                  (t source))))
    (loop for item in items
          for text = (%assistant-explain-candidate-text item)
          when (and text (plusp (length text)))
            collect text into candidates
          finally (return (subseq candidates 0 (min 3 (length candidates)))))))

(defun %assistant-explain-panel-lines (text candidates)
  (append (list (or text "AI 応答に説明がありません"))
          (when candidates
            (list "次の一手:"))
          (loop for candidate in candidates
                for index from 1
                collect (format nil "~d. ~a [Tabで載せる]"
                                index candidate))
          (list "出力を捕捉して再確認するには Ctrl-X を押してください。"
                "（対話型・安全でないコマンドは再実行できません。）")))

(defun %return-from-explain-with-message (message)
  (clear-rendered-completions)
  (clear-rendered-transient-panel)
  (setf *assistant-model-event-handler* nil
        *assistant-turn-started-at* nil
        *assistant-last-event-at* nil
        *assistant-request-kind* nil
        *assistant-explain-candidates* nil
        *assistant-explain-candidate-index* 0
        *input-state* (copy-input-state-with *input-state* :mode :insert))
  (render-prompt-cont)
  (render-transient-panel (list message)))

(defun %handle-explain-result (event)
  (let* ((payload (nshell.feature.assistant:assistant-model-event-payload event))
         (text (%assistant-explain-text payload))
         (candidates (%assistant-explain-candidates payload)))
    (clear-rendered-completions)
    (clear-rendered-transient-panel)
    (setf *assistant-model-event-handler* nil
          *assistant-turn-started-at* nil
          *assistant-request-kind* nil
          *assistant-explain-candidates* candidates
          *assistant-explain-candidate-index* 0
          *input-state* (copy-input-state-with *input-state* :mode :insert))
    (render-prompt-cont)
    (render-transient-panel (%assistant-explain-panel-lines text candidates))))

(defun %handle-explain-model-event (event)
  (case (nshell.feature.assistant:assistant-model-event-kind event)
    (:result (%handle-explain-result event))
    ((:stream-error :rate-limit-event)
     (%return-from-explain-with-message
      (%assistant-event-reason event "AI 応答を受け取れませんでした")))
    (:stream-ended
     (%return-from-explain-with-message "AI 応答が終了しました"))
    (otherwise
     (when *assistant-turn-started-at*
       (render-assistant-progress-panel *assistant-turn-started-at*)))))

(defun %install-explain-candidate ()
  (with-cleared-rendered-completions-and-prompt-cont
    (setf *preserve-transient-panel-on-next-prompt-p* t)
    (let ((candidate-count (length *assistant-explain-candidates*)))
      (when (plusp candidate-count)
        (let* ((index (mod *assistant-explain-candidate-index* candidate-count))
               (candidate (nth index *assistant-explain-candidates*)))
          (incf *assistant-explain-candidate-index*)
          (multiple-value-bind (status classification reason)
              (%assistant-proposal-assessment candidate)
            (when (eq status :classified)
              (case (nshell.feature.assistant:assistant-safety-result-classification
                     classification)
                (:block
                 (render-transient-panel
                  (list (format nil "候補 ~d はブロックされました: ~a"
                                (1+ index)
                                (nshell.feature.assistant:assistant-safety-result-reason
                                 classification)))))
                (otherwise
                 (%install-assistant-proposal candidate)
                 (setf *assistant-command-origin* :proposal
                       *assistant-command-confirmed-p*
                         (eq :safe
                             (nshell.feature.assistant:assistant-safety-result-classification
                              classification))))))
            (when (eq status :parse-error)
              (render-transient-panel (list reason)))))))))

(defun %process-explain-panel-event (event)
  (if (eq :tab (nshell.domain.input:key-event-type event))
      (%install-explain-candidate)
      (progn
        (setf *assistant-explain-candidates* nil
              *assistant-explain-candidate-index* 0)
        (clear-rendered-transient-panel)
        (multiple-value-bind (new-state output-event)
            (reduce-input-state *input-state* event)
          (setf *input-state* new-state)
          (process-output-event output-event)))))

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
        (and (eq :rate-limit-event
                 (nshell.feature.assistant:assistant-model-event-kind event))
             (let ((info (%assistant-payload-field payload "rate_limit_info")))
               (when (listp info)
                 (let ((status (%assistant-payload-field info "status")))
                   (and status
                        (format nil "AI rate limit: ~a" status))))))
        fallback)))

(defun %return-from-ask-with-message (message)
  (when (eq *assistant-request-kind* :agent)
    (return-from %return-from-ask-with-message
      (%finish-agent-session message)))
  (clear-rendered-completions)
  (clear-rendered-transient-panel)
  (clear-rendered-prompt)
  (format t "~%nshell: ~a~%" message)
  (setf *input-state* (make-repl-input-state)
        *assistant-model-event-handler* nil
        *assistant-turn-started-at* nil
        *assistant-last-event-at* nil
        *assistant-request-kind* nil
        *assistant-explain-candidates* nil
        *assistant-explain-candidate-index* 0
        *assistant-command-origin* :typed
        *assistant-command-confirmed-p* nil)
  (reset-rendered-prompt-state)
  (lambda () (render-prompt-cont)))

(define-output-event-handler %process-ask-start-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (setf *assistant-last-cancel-at* nil
          *assistant-request-kind* :ask
          *assistant-explain-candidates* nil
          *assistant-explain-candidate-index* 0))

(define-output-event-handler %process-ask-cancel-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (refresh-current-input-state-suggestion))

(defun %ask-model-terminal-event-p (event)
  (let ((kind (nshell.feature.assistant:assistant-model-event-kind event)))
    (or (member kind '(:result :stream-ended :stream-error) :test #'eq)
        (and (eq kind :rate-limit-event)
             (equal "rejected"
                    (%assistant-payload-field
                     (%assistant-payload-field
                      (nshell.feature.assistant:assistant-model-event-payload event)
                      "rate_limit_info")
                     "status"))))))

(defun %handle-ask-model-event (event)
  (let ((kind (nshell.feature.assistant:assistant-model-event-kind event))
        (payload (nshell.feature.assistant:assistant-model-event-payload event)))
    (case kind
      (:result
       (nshell.feature.assistant:record-assistant-result-usage payload))
      (:rate-limit-event
       (nshell.feature.assistant:record-assistant-rate-limit payload)))
    (when (and (eq kind :rate-limit-event)
               (not (%ask-model-terminal-event-p event)))
      (return-from %handle-ask-model-event nil))
    (cond
    ((eq *assistant-request-kind* :agent)
     (%handle-agent-model-event event))
    ((eq *assistant-request-kind* :explain)
     (%handle-explain-model-event event))
    (t
     (case kind
       (:result
        (let ((proposal
                (%assistant-proposal-text
                 (nshell.feature.assistant:assistant-model-event-payload event))))
          (if (or (null proposal) (zerop (length proposal)))
              (%return-from-ask-with-message "AI 応答に提案がありません")
              (multiple-value-bind (status classification reason)
                  (%assistant-proposal-assessment proposal)
                (setf *assistant-model-event-handler* nil
                      *assistant-turn-started-at* nil
                      *assistant-last-event-at* nil)
                (clear-rendered-transient-panel)
                (if (eq status :parse-error)
                    (progn
                      (setf *input-state* (make-repl-input-state)
                            *assistant-command-origin* :typed
                            *assistant-command-confirmed-p* nil)
                      (render-transient-panel (list reason))
                      (render-prompt-cont))
                    (case
                        (nshell.feature.assistant:assistant-safety-result-classification
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
          (render-assistant-progress-panel *assistant-turn-started-at*))))))))

(defun %process-ask-submit-output-event ()
  (clear-rendered-completions)
  (let* ((text (if (eq *assistant-request-kind* :explain)
                   "Explain the last failed command and suggest up to three next steps."
                   (input-state-buffer *input-state*)))
         (generation
           (setf *assistant-turn-generation*
                 (nshell.feature.assistant:next-assistant-turn-generation
                  *assistant-turn-generation*)))
         (raw-payload
           (nshell.feature.assistant:make-assistant-user-payload
            text :context (%assistant-context)))
         (payload
           (nshell.feature.assistant:redact-payload
            raw-payload
            :denylist-paths
            nshell.feature.assistant:+assistant-default-denylist-paths+
            :denylist-commands
            nshell.feature.assistant:+assistant-default-denylist-commands+
            :denylist-values
            (%assistant-environment-denylist-values
             (nshell.domain.environment:env-bindings
              (ensure-environment)))))
         (start-result (nshell.feature.assistant:assistant-model-start)))
    (setf *assistant-last-cancel-at* nil)
    (setf *assistant-explain-candidates* nil
          *assistant-explain-candidate-index* 0)
    (unless (%assistant-boundary-ok-p start-result)
      (return-from %process-ask-submit-output-event
        (%return-from-ask-with-message
         (format nil "AI 未接続: ~a"
                 (%assistant-boundary-failure-message
                  start-result "assistant model boundary is unavailable")))))
    (when *assistant-session-id*
      (nshell.feature.assistant:append-assistant-audit-entry
       payload nil
       :denylist-values
       (%assistant-environment-denylist-values
        (nshell.domain.environment:env-bindings (ensure-environment)))))
    (let ((request-result
            (nshell.feature.assistant:assistant-model-request
             generation payload)))
      (unless (%assistant-boundary-ok-p request-result)
        (return-from %process-ask-submit-output-event
          (%return-from-ask-with-message
           (format nil "AI 要求を送信できません: ~a"
                   (%assistant-boundary-failure-message
                    request-result "assistant model request failed")))))
      (setf *assistant-turn-started-at* (boundary-monotonic))
      (setf *assistant-last-event-at* *assistant-turn-started-at*)
      (setf *assistant-model-event-handler* #'%handle-ask-model-event)
      (render-prompt-cont)
      (render-assistant-progress-panel *assistant-turn-started-at*)
      (lambda () (read-key-cont)))))

(defun %assistant-cancel-repeat-p (now)
  (let ((last-cancel-at *assistant-last-cancel-at*))
    (and last-cancel-at
         (<= 0 (- now last-cancel-at) +assistant-cancel-window-ticks+))))

(defun %process-ask-cancel-turn-output-event ()
  (cond
    ((eq *assistant-request-kind* :agent)
     (let* ((now (boundary-monotonic))
            (repeat-p (%assistant-cancel-repeat-p now))
            (starting-p (eq :starting
                            (getf (nshell.feature.assistant:assistant-model-status)
                                  :state)))
            (generation
              (setf *assistant-turn-generation*
                    (nshell.feature.assistant:next-assistant-turn-generation
                     *assistant-turn-generation*)))
            (stop-result (when (or repeat-p starting-p)
                           (nshell.feature.assistant:assistant-model-stop)))
            (start-result (when repeat-p
                            (nshell.feature.assistant:assistant-model-start))))
       (declare (ignore generation))
       (setf *assistant-last-cancel-at* (unless repeat-p now))
       (prog1
           (%finish-agent-session "canceled")
         (when (and repeat-p
                    (not (%assistant-boundary-ok-p start-result)))
           (format t "nshell: AI sidecar restart failed: ~a~%"
                   (%assistant-boundary-failure-message
                    start-result "assistant model boundary is unavailable")))
         (when (and repeat-p
                    (not (%assistant-boundary-ok-p stop-result)))
           (format t "nshell: AI sidecar stop failed: ~a~%"
                   (%assistant-boundary-failure-message
                    stop-result "assistant model boundary is unavailable"))))))
    (t
     (let* ((now (boundary-monotonic))
            (repeat-p (%assistant-cancel-repeat-p now))
            (starting-p (eq :starting
                            (getf (nshell.feature.assistant:assistant-model-status)
                                  :state)))
            (generation
              (setf *assistant-turn-generation*
                    (nshell.feature.assistant:next-assistant-turn-generation
                     *assistant-turn-generation*)))
            (stop-result (when (or repeat-p starting-p)
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
             *assistant-last-event-at* nil
             *assistant-request-kind* nil
             *assistant-explain-candidates* nil
             *assistant-explain-candidate-index* 0
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
       (lambda () (render-prompt-cont))))))
(defun %execute-empty-input ()
  (with-reset-rendered-prompt-state-and-prompt-cont
    (format t "~%")
    (setf *last-command-duration-ms* nil)
    (setf *last-command-output* nil
          *failure-explain-available-p* nil)
    (setf *assistant-command-origin* :typed
          *assistant-command-confirmed-p* nil)
    (progn
      (setf *osc133-state* :none)
      (setf *input-state* (make-repl-input-state)))))

(defun %assistant-proposal-confirmation-required-p ()
  (and (eq *assistant-command-origin* :proposal)
       (not *assistant-command-confirmed-p*)))

(defun %confirm-assistant-proposal ()
  (setf *assistant-command-confirmed-p* t)
  (clear-rendered-transient-panel)
  (render-transient-panel
   (list "AI proposal requires confirmation; press Enter again to execute."))
  (lambda () (render-prompt-cont)))

(defun %execute-complete-command (ast text &optional evaluator)
  (with-reset-rendered-prompt-state-and-prompt-cont
   (progn
     (format t "~%")
     (setf *osc133-state* :command)
     (%emit-terminal-integration-sequence :osc133 "C")
     (%emit-terminal-integration-sequence
      :title
      (format nil "nshell: ~a | ~a" (boundary-current-directory) text)))
   (%refresh-history-from-file)
   (sync-exported-environment)
   ;; Time the command through the clock boundary (real clock == monotonic
   ;; get-internal-real-time), so a fake clock makes duration deterministic.
   (let ((start-time (boundary-monotonic))
         (timestamp (get-universal-time))
         (cwd (boundary-current-directory))
         (host (boundary-hostname))
         (exit-code nil))
     (unwind-protect
         (let ((nshell.infrastructure.acl:*command-not-found-hook*
                (lambda (command)
                  (setf *command-not-found-command* command)))
               (nshell.application:*execution-origin*
                *assistant-command-origin*)
               (nshell.application:*execution-confirmed-p*
                *assistant-command-confirmed-p*))
           (setf *command-not-found-command* nil)
           (setf *last-command-output* nil)
           (setf exit-code (or (if evaluator (funcall evaluator) (execute-ast ast)) 0)))
       (let ((recorded-exit-code (if (integerp exit-code) exit-code 1)))
         (let ((duration-ms (%elapsed-command-duration-ms
                             start-time
                             (boundary-monotonic))))
           (setf *last-exit-code* recorded-exit-code
                 *last-command-duration-ms* duration-ms
                 *failure-explain-available-p* (not (zerop recorded-exit-code)))
           (if (and (= recorded-exit-code 127)
                    *command-not-found-command*
                    (not *agent-session*))
               (progn
                 (let ((corrections (%repl-command-corrections
                                     *command-not-found-command*)))
                   (when corrections
                     (format t "nshell: did you mean: ~{~a~^, ~}?~%" corrections)))
                 (setf *command-not-found-fallback-text* text
                       *preserve-transient-panel-on-next-prompt-p* t
                       *transient-panel-content* '("⌃] で AI に聞く")))
             (progn
               (when (and *agent-session*
                          (= recorded-exit-code 127)
                          *command-not-found-command*)
                 (setf *last-command-output*
                       (or *last-command-output*
                           (format nil "nshell: ~a: command not found~%"
                                   *command-not-found-command*))
                       *command-not-found-fallback-text* nil)
                 (write-string *last-command-output*))
               (when (and *history-persistence-enabled-p*
                          (not (and (plusp (length text))
                                    (char= (char text 0) #\Space))))
                 (multiple-value-bind (history record)
                     (nshell.infrastructure.persistence:history-record-add
                      *history* text
                      :timestamp timestamp
                      :cwd cwd
                      :exit-code recorded-exit-code
                      :duration-ms duration-ms
                      :origin *assistant-command-origin*
                      :host host)
                   (declare (ignore history))
                   (history-kit:history-reset-navigation *history*)
                   (let ((nshell.infrastructure.persistence:*history-record-to-append*
                          record))
                     (nshell.infrastructure.persistence:append-history-entry text)))
                 (setf (gethash text *history-seen-command-texts*) t))))
           (setf *last-command-text* text
                 *assistant-pending-transcript*
                 (list :session-id *assistant-session-id*
                       :timestamp timestamp
                       :cwd cwd
                       :text text
                       :exit recorded-exit-code
                       :duration-ms duration-ms
                       :origin *assistant-command-origin*
                       :output-head *last-command-output*
                       :denylist-paths
                       nshell.feature.assistant:+assistant-default-denylist-paths+
                       :denylist-commands
                       nshell.feature.assistant:+assistant-default-denylist-commands+
                       :denylist-values
                       (%assistant-environment-denylist-values
                        (nshell.domain.environment:env-bindings
                         (ensure-environment)))))
           (progn
             (setf *command-not-found-command* nil)
             (%emit-terminal-integration-sequence
              :osc133
              (format nil "D;~d" recorded-exit-code))
             (setf *osc133-state* :none)))))
     (unless *agent-session*
       (setf *assistant-command-origin* :typed
             *assistant-command-confirmed-p* nil)
       (setf *input-state* (make-repl-input-state))))))

(defun %execute-parse-error (result)
  (with-reset-rendered-prompt-state-and-prompt-cont
    (progn
      (format t "~%")
      (setf *osc133-state* :none))
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

(defparameter +rerun-interactive-command-names+
  '("vi" "vim" "nvim" "nano" "emacs"
    "less" "more" "most" "man"
    "ssh" "mosh" "telnet"
    "top" "htop" "btop" "watch"
    "tmux" "screen" "fzf")
  "Commands that require a live terminal and cannot use the capture runner.")

(defparameter +rerun-interactive-repl-command-names+
  '("python" "python3" "node" "irb" "sbcl" "ghci")
  "Commands that are interactive only when started without arguments.")

(defparameter +rerun-command-expansion-depth-limit+ 8)

(defparameter +rerun-dynamic-command-names+
  '("eval" "source" ".")
  "Commands whose contents are only known at execution time.")

(defun %rerun-command-substitution-texts (value)
  (mapcan (lambda (marker)
            (let ((texts
                    (nshell.domain.parsing:parenthesized-substitution-texts
                     value marker)))
              (if (member :incomplete texts)
                  (list :incomplete)
                  texts)))
          '("$(" "<(" ">(" "(")))

(defun %rerun-parse-command-details (text &key depth seen)
  (let ((result (nshell.domain.parsing:parse-command-line text)))
    (if (nshell.domain.parsing:parse-complete-p result)
        (%rerun-command-details
         (nshell.domain.parsing:parse-result-ast result)
         :depth depth :seen seen)
        (list (list :dynamic
                    "定義または置換の内容を解析できないため出力を捕捉できません")))))

(defun %rerun-definition-details (name texts &key depth seen)
  (if (or (null texts) (member name seen :test #'string-equal))
      nil
      (%rerun-parse-command-details
       (format nil "~{~a~^~%~}" texts)
       :depth (1+ depth) :seen (cons name seen))))

(defun %rerun-command-substitution-details (values &key depth seen)
  (mapcan
   (lambda (value)
     (mapcan (lambda (text)
               (if (eq text :incomplete)
                   (list (list :dynamic
                               "置換の内容を完全に解析できないため出力を捕捉できません"))
                   (%rerun-parse-command-details text
                                                  :depth (1+ depth)
                                                  :seen seen)))
             (%rerun-command-substitution-texts value)))
   values))

(defun %rerun-command-definition-details (name &key depth seen)
  (cond
    ((member name seen :test #'string-equal) nil)
    ((>= depth +rerun-command-expansion-depth-limit+)
     (list (list :dynamic
                 "定義の展開が深すぎるため出力を捕捉できません")))
    (t
     (append
      (%rerun-definition-details
       name (let ((alias (gethash name *aliases*)))
              (and alias (list alias)))
       :depth depth :seen seen)
      (%rerun-definition-details
       name (gethash name *functions*) :depth depth :seen seen)
      (%rerun-definition-details
       name (let ((abbreviation (gethash name *abbreviations*)))
              (when abbreviation
                (list (if (stringp abbreviation)
                          abbreviation
                          (nshell.domain.abbreviation:abbreviation-expansion
                           abbreviation)))))
       :depth depth :seen seen)))))

(defun %rerun-command-details (ast &key (depth 0) (seen nil))
  (cond
    ((nshell.domain.parsing:command-node-p ast)
     (let* ((raw-command (nshell.domain.parsing:command-node-command ast))
            (raw-args (nshell.domain.parsing:command-node-arg-values ast))
            (command-and-args
              (multiple-value-list
               (nshell.feature.assistant:assistant-command-after-wrappers
                raw-command raw-args))))
       (append
        (list (list :command (first command-and-args)
                    :args (second command-and-args)))
        (%rerun-command-substitution-details
         (cons raw-command raw-args) :depth depth :seen seen)
        (%rerun-command-definition-details
         (first command-and-args) :depth depth :seen seen))))
    ((nshell.domain.parsing:pipeline-node-p ast)
     (mapcan (lambda (node) (%rerun-command-details node :depth depth :seen seen))
             (nshell.domain.parsing:pipeline-node-commands ast)))
    ((nshell.domain.parsing:sequence-node-p ast)
     (mapcan (lambda (node) (%rerun-command-details node :depth depth :seen seen))
             (nshell.domain.parsing:sequence-node-commands ast)))
    ((nshell.domain.parsing:if-node-p ast)
     (mapcan (lambda (node) (%rerun-command-details node :depth depth :seen seen))
             (append (list (nshell.domain.parsing:if-node-condition ast))
                     (nshell.domain.parsing:if-node-then-branch ast)
                     (nshell.domain.parsing:if-node-else-branch ast))))
    ((nshell.domain.parsing:for-node-p ast)
     (mapcan (lambda (node) (%rerun-command-details node :depth depth :seen seen))
             (append (nshell.domain.parsing:for-node-in-values ast)
                     (nshell.domain.parsing:for-node-body ast))))
    ((nshell.domain.parsing:while-node-p ast)
     (mapcan (lambda (node) (%rerun-command-details node :depth depth :seen seen))
             (append (list (nshell.domain.parsing:while-node-condition ast))
                     (nshell.domain.parsing:while-node-body ast))))
    ((nshell.domain.parsing:case-node-p ast)
     (mapcan (lambda (clause)
               (mapcan (lambda (node) (%rerun-command-details node :depth depth :seen seen))
                       (nshell.domain.parsing:case-clause-body clause)))
             (nshell.domain.parsing:case-node-clauses ast)))
    ((nshell.domain.parsing:begin-end-node-p ast)
     (mapcan (lambda (node) (%rerun-command-details node :depth depth :seen seen))
             (nshell.domain.parsing:begin-end-node-body ast)))
    (t nil)))

(defun %rerun-command-assessment (text)
  (let ((result (nshell.domain.parsing:parse-command-line text)))
    (if (nshell.domain.parsing:parse-complete-p result)
        (let* ((ast (nshell.domain.parsing:parse-result-ast result))
               (classification (nshell.feature.assistant:classify-ast ast))
               (details (%rerun-command-details ast))
               (dynamic-reason
                 (some (lambda (detail)
                         (when (eq (first detail) :dynamic)
                           (second detail)))
                       details))
               (interactive-command
                 (some (lambda (detail)
                         (when (eq (first detail) :command)
                           (let ((command (getf detail :command))
                                 (args (getf detail :args)))
                             (when (or (member command +rerun-interactive-command-names+
                                                :test #'string-equal)
                                       (and (null args)
                                            (member command
                                                    +rerun-interactive-repl-command-names+
                                                    :test #'string-equal)))
                               command))))
                       details))
               (dynamic-command
                 (some (lambda (detail)
                         (when (eq (first detail) :command)
                           (let ((command (getf detail :command)))
                             (when (or (member command +rerun-dynamic-command-names+
                                                :test #'string-equal)
                                       (search "$" command)
                                       (search "`" command))
                               command))))
                       details)))
          (list :classification
                (if (or dynamic-reason dynamic-command)
                    :block
                    (nshell.feature.assistant:assistant-safety-result-classification
                     classification))
                :reason
                (cond
                  (dynamic-reason
                   dynamic-reason)
                  (dynamic-command
                   (format nil "~a は実行時まで内容が決まらないため出力を捕捉できません"
                           dynamic-command))
                  (interactive-command
                    (format nil "~a にはライブ端末が必要です" interactive-command))
                  (t
                   (nshell.feature.assistant:assistant-safety-result-reason
                    classification)))
                :interactive-command interactive-command))
        (list :classification :block
              :reason "直前のコマンドを安全に解析できません"
              :interactive-command nil))))

(defun %rerun-panel-lines (assessment)
  (list (format nil "出力を捕捉して再実行: ~a" *last-command-text*)
        (format nil "安全性: ~(~a~)（~a）"
                (getf assessment :classification)
                (getf assessment :reason))
        (format nil "確認するにはもう一度 ~{~a~^ / ~} を押してください。その他のキーで取り消します。"
                (loop for (key . action) in (input-dispatch-bindings-listing)
                      when (string= action "rerun-last-command")
                        collect key))))

(defun %rerun-confirmation-panel-lines (assessment)
  (let ((width (- (terminal-width) 4))
        (lines nil))
    (unless (plusp width)
      (return-from %rerun-confirmation-panel-lines nil))
    (dolist (line (%rerun-panel-lines assessment))
      (when (some (lambda (char)
                    (let ((code (char-code char)))
                      (or (< code 32) (<= 127 code 159))))
                  line)
        (return-from %rerun-confirmation-panel-lines nil))
      (let ((graphemes nil)
            (line-width 0))
        (dolist (grapheme (cl-tty-kit:string-graphemes line))
          (let ((grapheme-width (%grapheme-visible-width grapheme)))
            (when (> grapheme-width width)
              (return-from %rerun-confirmation-panel-lines nil))
            (when (> (+ line-width grapheme-width) width)
              (push (format nil "~{~a~}" (nreverse graphemes)) lines)
              (setf graphemes nil line-width 0))
            (push grapheme graphemes)
            (incf line-width grapheme-width)))
        (push (format nil "~{~a~}" (nreverse graphemes)) lines)))
    (when (<= (+ 2 (length lines))
              (max 0 (- (%transient-panel-terminal-rows)
                        *prompt-rendered-lines* 1)))
      (nreverse lines))))

(defun %reject-incomplete-rerun-confirmation ()
  (setf *rerun-confirmation-pending-p* nil
        *rerun-command-assessment* nil)
  (render-transient-panel
   '("確認内容を全て表示できないため、出力捕捉による再実行を拒否しました。"
     "端末を広げ、表示できない制御文字を含まないコマンドを使用してください。")))

(defun %process-rerun-last-command-output-event ()
  (cond
    ((null *last-command-text*)
     (setf *rerun-command-assessment* nil)
     (with-cleared-rendered-completions-and-prompt-cont
       (render-transient-panel '("捕捉する直前のコマンドがありません。"))))
    ((not *rerun-confirmation-pending-p*)
     (with-cleared-rendered-completions-and-prompt-cont
       (let ((assessment (%rerun-command-assessment *last-command-text*)))
         (setf *rerun-command-assessment* assessment)
         (if (or (getf assessment :interactive-command)
                 (eq :block (getf assessment :classification)))
             (render-transient-panel
              (list (format nil "出力捕捉による再実行を拒否: ~a"
                            (getf assessment :reason))
                    (format nil "コマンド: ~a" *last-command-text*)))
             (let ((lines (%rerun-confirmation-panel-lines assessment)))
               (if lines
                   (progn
                     (setf *rerun-confirmation-pending-p* t)
                     (render-transient-panel lines)
                     (setf *preserve-transient-panel-on-next-prompt-p* t))
                   (%reject-incomplete-rerun-confirmation)))))))
    (t
     (let ((assessment *rerun-command-assessment*))
       (setf *rerun-confirmation-pending-p* nil
             *rerun-command-assessment* nil)
       (if (or (null assessment)
               (getf assessment :interactive-command)
               (eq :block (getf assessment :classification)))
           (with-cleared-rendered-completions-and-prompt-cont
             (render-transient-panel
              '("安全でない、または対話型のコマンドのため、出力捕捉による再実行を拒否しました。")))
           (if (let ((lines (%rerun-confirmation-panel-lines assessment)))
                 (not (and lines
                           (equal lines *transient-panel-content*)
                           (= (+ 2 (length lines))
                              *transient-panel-rendered-lines*))))
               (with-cleared-rendered-completions-and-prompt-cont
                 (%reject-incomplete-rerun-confirmation))
               (progn
                 (clear-rendered-transient-panel)
                 (setf *input-state*
                       (make-repl-input-state
                        :buffer *last-command-text*
                        :cursor-pos (length *last-command-text*)))
                 (let ((*capture-command-output-p* t))
                   (%process-execute-output-event)))))))))

(defun %execute-command-line-legacy (text)
  (if (%assistant-proposal-confirmation-required-p)
      (%confirm-assistant-proposal)
      (handler-case
          (if (string= text "")
              (%execute-empty-input)
              (multiple-value-bind (expanded-text expansion-error)
                  (nshell.domain.history:history-expand-line *history* text)
                (if expansion-error
                    (with-reset-rendered-prompt-state-and-prompt-cont
                     (progn
                      (format t "~%nshell: ~a~%" expansion-error)
                      (setf *osc133-state* :none))
                     (%set-command-failure-state 2))
                    (nshell.domain.parsing:with-parsed-command-line-case
                     (result ast expanded-text)
                     (:complete
                      (%execute-complete-command
                       (if (nshell.application:function-definition-line-p
                            expanded-text)
                           (make-source-text-request expanded-text)
                           ast)
                       expanded-text))
                     (:error
                      (%execute-parse-error result))
                     (:incomplete
                      (%execute-incomplete-command result))
                     (:empty
                      (%execute-empty-input))))))
        (nshell.infrastructure.terminal:terminal-mode-operation-failed (condition)
          (format *error-output* "~%nshell: ~a~%" condition)
          (%set-command-failure-state 1)
          (setf *running* nil)
          +repl-exit+)
        (storage-condition ()
          (with-reset-rendered-prompt-state-and-prompt-cont
            (format t "~%nshell: storage exhausted~%")
            (%set-command-failure-state 1)))
        (error (condition)
               (with-reset-rendered-prompt-state-and-prompt-cont
                (format t "~%nshell error: ~a~%" condition)
                (%set-command-failure-state 1))))))
(defun %execute-command-line (text)
  (cond
    ((%assistant-proposal-confirmation-required-p)
     (%confirm-assistant-proposal))
    ((%repl-new-reader-route-enabled-p)
     (if (every (lambda (character)
                  (find character (list #\Space #\Tab #\Newline #\Return)))
                text)
         (%execute-empty-input)
         (%execute-complete-command
          nil
          text
          (lambda ()
            (%evaluate-repl-reader-submission
             text
             (%repl-reader-context-for-source text))))))
    (t
     (%execute-command-line-legacy text))))

  (defun %process-execute-output-event ()
    (clear-rendered-completions)
    (clear-rendered-search-results)
    (%execute-command-line (input-state-buffer *input-state*)))

  (define-output-event-handler %process-complete-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (unless (%completion-session-valid-p *input-state*)
      (let* ((base-state *input-state*)
             (base-buffer (input-state-buffer base-state))
             (base-cursor (input-state-cursor-pos base-state)))
        (multiple-value-bind (refreshed-state candidates)
            (%refresh-completion-session-state base-state)
          (setf *input-state*
                (cond
                  ((null candidates) refreshed-state)
                  ((> (completion-render-line-count
                       candidates
                       :terminal-width (terminal-width))
                      (%completion-pager-row-budget))
                   (copy-input-state-with
                    base-state
                    :last-candidates candidates
                    :completion-base-buffer base-buffer
                    :completion-base-cursor base-cursor
                    :completion-pager (list :query "" :index 0)
                    :suggestion :clear))
                  (t
                   (copy-input-state-with
                    refreshed-state
                    :completion-base-buffer base-buffer
                    :completion-base-cursor base-cursor))))))))

(define-output-event-handler %process-suggest-update-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (history-kit:history-reset-navigation *history*)
    (refresh-current-input-state-suggestion))

(define-output-event-handler %process-history-search-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (%refresh-history-from-file)
    (let* ((query (input-state-search-query *input-state*))
           (entries (nshell.application:interactive-history-search-use-case
                     *history* query))
           (texts (history-kit:history-entry-texts entries)))
      (setf *input-state*
            (apply-history-search-results-to-input-state *input-state* texts))))

(define-output-event-handler %process-history-prev-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (%refresh-history-from-file)
    (let ((entry (history-kit:history-previous
                  *history*
                  (input-state-buffer *input-state*))))
      (when entry
        (setf *input-state*
              (make-repl-input-state :buffer entry :cursor-pos (length entry)))
        (refresh-current-input-state-suggestion))))

(define-output-event-handler %process-history-next-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (%refresh-history-from-file)
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
