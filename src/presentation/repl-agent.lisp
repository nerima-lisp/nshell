(in-package #:nshell.presentation)

(defun %agent-proposal-text (payload)
  (or (%assistant-proposal-text payload)
      (let* ((structured (%assistant-payload-field payload "structured_output"))
             (steps (and (listp structured)
                         (%assistant-payload-field structured "steps")))
             (first-step (and (listp steps) (first steps))))
        (cond
          ((stringp first-step) first-step)
          ((listp first-step)
           (or (%assistant-payload-field first-step "command")
               (%assistant-payload-field first-step "command_line")
               (%assistant-payload-field first-step "text")))))))

(defun %agent-request-text (session)
  (if (zerop (nshell.application:agent-session-completed-steps session))
      (nshell.application:agent-session-task session)
      (format nil
              "Continue the task: ~a~%Return exactly one next shell command."
              (nshell.application:agent-session-task session))))

(defun %agent-classification-label (step)
  (let ((classification (nshell.application:agent-step-classification step)))
    (if classification
        (string-downcase
         (symbol-name
          (nshell.feature.assistant:assistant-safety-result-classification
           classification)))
        "invalid")))

(defun %agent-step-panel-lines (session step)
  (let ((step-number (nshell.application:agent-session-steps-used session))
        (max-steps (nshell.application:agent-session-max-steps session)))
    (list
     (format nil "agent · step ~d/~d" step-number max-steps)
     (format nil "> ~a" (nshell.application:agent-step-text step))
     (format nil "~a~@[ · ~a~]"
             (%agent-classification-label step)
             (and (nshell.application:agent-step-classification step)
                  (nshell.feature.assistant:assistant-safety-result-reason
                   (nshell.application:agent-step-classification step))))
     (if (nshell.application:agent-step-blocked-p step)
         "Enter disabled · e 編集 · s 飛ばす · q 中止"
         "Enter 実行 · e 編集 · s 飛ばす · q 中止"))))

(defun %render-agent-step-panel ()
  (let ((session *agent-session*))
    (when (and session
               (nshell.application:agent-session-current-step session))
      (clear-rendered-transient-panel)
      (render-prompt-cont)
      (render-transient-panel
       (%agent-step-panel-lines
        session
        (nshell.application:agent-session-current-step session)))
      (lambda () (read-key-cont)))))

(defun %finish-agent-session (reason)
  (clear-rendered-transient-panel)
  (when *agent-session*
    (nshell.application:agent-session-stop *agent-session* reason))
  (setf *agent-session* nil
        *assistant-model-event-handler* nil
        *assistant-turn-started-at* nil
        *assistant-request-kind* nil
        *assistant-command-origin* :typed
        *assistant-command-confirmed-p* nil
        *input-state* (make-repl-input-state))
  (render-prompt-cont)
  (render-transient-panel (list (format nil "agent: ~a" reason)))
  (lambda () (read-key-cont)))

(defun %agent-start-next-request ()
  (let ((session *agent-session*))
    (if (or (null session)
            (nshell.application:agent-session-limit-reached-p session))
        (%finish-agent-session "maximum step count reached")
        (progn
          (setf *assistant-request-kind* :agent
                *input-state*
                  (copy-input-state-with
                   (make-repl-input-state
                    :buffer (%agent-request-text session))
                   :mode :ask-waiting))
          (%process-ask-submit-output-event)))))

(defun %agent-execute-current-step ()
  (let* ((session *agent-session*)
         (step (and session
                    (nshell.application:agent-session-current-step session))))
    (unless (nshell.application:agent-step-executable-p step)
      (return-from %agent-execute-current-step
        (%render-agent-step-panel)))
    (setf *assistant-command-origin* :agent
          *assistant-command-confirmed-p* t)
    (clear-rendered-transient-panel)
    (clear-rendered-prompt)
    (%execute-complete-command
     (nshell.application:agent-step-ast step)
     (nshell.application:agent-step-text step))
    (nshell.infrastructure.acl:consume-sigint-received-p)
    (nshell.application:agent-session-record-step
     session *last-command-output* *last-exit-code*)
    (if (nshell.application:agent-session-limit-reached-p session)
        (%finish-agent-session "maximum step count reached")
        (%agent-start-next-request))))

(defun %agent-skip-current-step ()
  (let ((session *agent-session*))
    (when session
      (nshell.application:agent-session-skip-step session))
    (if (or (null session)
            (nshell.application:agent-session-limit-reached-p session))
        (%finish-agent-session "maximum step count reached")
        (%agent-start-next-request))))

(defun %agent-enter-editing ()
  (let ((step (nshell.application:agent-session-current-step *agent-session*)))
    (setf (nshell.application:agent-session-state *agent-session*) :editing
          *input-state*
            (make-repl-input-state
             :buffer (nshell.application:agent-step-text step)))
    (render-prompt-cont)
    (render-transient-panel
     (list "agent: 編集中 · Enter 実行 · q 中止"))
    (lambda () (read-key-cont))))

(defun %agent-apply-edited-input ()
  (let ((step
          (nshell.application:agent-session-reclassify-step
           *agent-session*
           (input-state-buffer *input-state*))))
    (if (nshell.application:agent-step-executable-p step)
        (%agent-execute-current-step)
        (%render-agent-step-panel))))

(defun %agent-editing-event (event)
  (let ((type (nshell.domain.input:key-event-type event)))
    (cond
      ((eq type :ctrl-c)
       (%finish-agent-session "canceled"))
      ((and (eq type :char)
            (char= (nshell.domain.input:key-event-char event) #\q))
       (%finish-agent-session "canceled"))
      ((and (eq type :char)
            (char= (nshell.domain.input:key-event-char event) #\s))
       (%agent-skip-current-step))
      (t
       (multiple-value-bind (new-state output-event)
           (reduce-input-state *input-state* event)
         (setf *input-state* new-state)
         (if (eq output-event :execute)
             (%agent-apply-edited-input)
             (process-output-event output-event)))))))

(defun %process-agent-panel-event (event)
  (let* ((session *agent-session*)
         (step (and session (nshell.application:agent-session-current-step session)))
         (type (nshell.domain.input:key-event-type event))
         (char (and (eq type :char)
                    (nshell.domain.input:key-event-char event))))
    (cond
      ((or (null session) (null step))
       (read-key-cont))
      ((eq (nshell.application:agent-session-state session) :editing)
       (%agent-editing-event event))
      ((eq type :ctrl-c)
       (%finish-agent-session "canceled"))
      ((eq type :enter)
       (if (nshell.application:agent-step-blocked-p step)
           (%render-agent-step-panel)
           (%agent-execute-current-step)))
      ((and char (char= char #\e))
       (%agent-enter-editing))
      ((and char (char= char #\s))
       (%agent-skip-current-step))
      ((and char (char= char #\q))
       (%finish-agent-session "canceled"))
      (t
       (%render-agent-step-panel)))))

(defun %handle-agent-model-event (event)
  (case (nshell.feature.assistant:assistant-model-event-kind event)
    (:result
     (let ((proposal
             (%agent-proposal-text
              (nshell.feature.assistant:assistant-model-event-payload event))))
       (setf *assistant-model-event-handler* nil
             *assistant-turn-started-at* nil)
       (if (or (null proposal) (zerop (length proposal)))
           (%finish-agent-session "AI 応答に提案がありません")
           (if (nshell.application:agent-session-propose-step
                *agent-session* proposal)
               (progn
                 (setf *input-state*
                       (make-repl-input-state :buffer proposal))
                 (%render-agent-step-panel))
               (%finish-agent-session "maximum step count reached")))))
    ((:stream-error :rate-limit-event)
     (%finish-agent-session
      (%assistant-event-reason event "AI 応答を受け取れませんでした")))
    (:stream-ended
     (%finish-agent-session "AI 応答が終了しました"))
    (otherwise
     (when *assistant-turn-started-at*
       (render-assistant-progress-panel *assistant-turn-started-at*)))))

(defun start-agent-session (context task &key max-steps)
  (declare (ignore context))
  (setf *agent-session*
        (nshell.application:make-agent-session task :max-steps max-steps)
        *assistant-request-kind* :agent
        *assistant-command-origin* :typed
        *assistant-command-confirmed-p* nil
        *input-state*
          (copy-input-state-with
           (make-repl-input-state :buffer task)
           :mode :ask-waiting))
  (%process-ask-submit-output-event)
  (when *agent-session*
    (setf *preserve-transient-panel-on-next-prompt-p* t))
  t)
