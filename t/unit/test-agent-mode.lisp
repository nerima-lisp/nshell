(in-package #:nshell/test)

(defvar *agent-test-request-payload*)

(describe "agent-mode-state-machine-tests"
  (it "does-not-dispatch-an-agent-step-without-approval"
    (let ((context (nshell.application:make-shell-context))
          (ast (nshell.domain.parsing:make-command-node
                "ls" (list "unapproved")))
          (executed-p nil))
      (let ((nshell.application::*execution-origin* :agent)
            (nshell.application::*execution-confirmed-p* nil))
        (with-temporary-function
            ('nshell.application::execute-command-node-in-context
             (lambda (ignored-context ignored-ast)
               (declare (ignore ignored-context ignored-ast))
               (setf executed-p t)
               (values "executed" 0)))
          (multiple-value-bind (output code)
              (nshell.application:execute-ast-in-context context ast)
            (expect nil :to-be executed-p)
            (expect 126 :to-equal code)
            (expect (search "requires approval" output)
                    :to-be-truthy))))))

  (it "does-not-execute-a-blocked-step-when-enter-is-pressed"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "remove nothing"
                                                             :max-steps 1))
            (executed-p nil))
        (nshell.application:agent-session-propose-step session "rm -rf /")
        (setf nshell.presentation::*agent-session* session)
        (with-repl-input-state (:mode :insert :buffer "rm -rf /" :cursor-pos 8)
          (with-temporary-functions
              (('nshell.presentation::execute-ast
                (lambda (ast)
                  (declare (ignore ast))
                  (setf executed-p t)
                  0))
               ('nshell.presentation::render-prompt-cont
                (lambda () nil))
               ('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore content arguments))
                  nil)))
            (nshell.presentation::%process-agent-panel-event
             (input-key-event :enter)))
          (expect nil :to-be executed-p)
          (expect :awaiting-approval :to-equal
                  (nshell.application:agent-step-status
                   (nshell.application:agent-session-current-step session)))))))

  (it "executes-a-safe-step-only-after-enter-approval"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "list files"
                                                             :max-steps 1))
            (executed-p nil))
        (nshell.application:agent-session-propose-step session "ls")
        (let ((step (nshell.application:agent-session-current-step session)))
          (setf nshell.presentation::*agent-session* session)
          (with-repl-input-state (:mode :insert :buffer "ls" :cursor-pos 2)
            (with-temporary-functions
                (('nshell.presentation::execute-ast
                  (lambda (ast)
                    (declare (ignore ast))
                    (setf executed-p t)
                    0))
                 ('nshell.presentation::render-prompt-cont
                  (lambda () nil))
                 ('nshell.presentation::render-transient-panel
                  (lambda (content &rest arguments)
                    (declare (ignore content arguments))
                    nil)))
              (nshell.presentation::%process-agent-panel-event
               (input-key-event :enter)))
            (expect t :to-be executed-p)
            (expect :executed :to-equal
                    (nshell.application:agent-step-status step))
            (expect nil :to-be nshell.presentation::*agent-session*))))))

  (it "enters-editing-mode-with-e"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "list files"
                                                             :max-steps 1)))
        (nshell.application:agent-session-propose-step session "ls")
        (setf nshell.presentation::*agent-session* session)
        (with-repl-input-state (:mode :insert :buffer "ls" :cursor-pos 2)
          (with-temporary-functions
              (('nshell.presentation::render-prompt-cont
                (lambda () nil))
               ('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore content arguments))
                  nil)))
            (nshell.presentation::%process-agent-panel-event
             (input-key-event :char #\e)))
          (expect :editing :to-equal
                  (nshell.application:agent-session-state session))
          (expect "ls" :to-equal
                  (nshell.presentation:input-state-buffer
                   nshell.presentation::*input-state*))))))

  (it "skips-a-step-with-s-and-does-not-execute-the-rest"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "list files"
                                                             :max-steps 1))
            (executed-p nil))
        (nshell.application:agent-session-propose-step session "ls")
        (let ((step (nshell.application:agent-session-current-step session)))
          (setf nshell.presentation::*agent-session* session)
          (with-repl-input-state (:mode :insert :buffer "ls" :cursor-pos 2)
            (with-temporary-function
                ('nshell.presentation::render-transient-panel
                 (lambda (content &rest arguments)
                   (declare (ignore content arguments))
                   nil))
              (nshell.presentation::%process-agent-panel-event
               (input-key-event :char #\s)))
            (expect :skipped :to-equal
                    (nshell.application:agent-step-status step))
            (expect nil :to-be executed-p)
            (expect nil :to-be nshell.presentation::*agent-session*))))))

  (it "cancels-an-agent-session-with-q"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "list files"
                                                             :max-steps 1)))
        (nshell.application:agent-session-propose-step session "ls")
        (setf nshell.presentation::*agent-session* session)
        (with-repl-input-state (:mode :insert :buffer "ls" :cursor-pos 2)
          (with-temporary-functions
              (('nshell.presentation::render-prompt-cont
                (lambda () nil))
               ('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore content arguments))
                  nil)))
            (nshell.presentation::%process-agent-panel-event
             (input-key-event :char #\q)))
          (expect :stopped :to-equal
                  (nshell.application:agent-session-state session))
          (expect "canceled" :to-equal
                  (nshell.application:agent-session-stop-reason session))
          (expect nil :to-be nshell.presentation::*agent-session*)))))

  (it "rejects-agent-in-a-noninteractive-session-without-starting-the-sidecar"
    (with-builtins-context (context)
      (let ((started-p nil))
        (let ((nshell.application:*agent-start-handler*
                (lambda (ignored-context task &key max-steps)
                  (declare (ignore ignored-context task max-steps))
                  (setf started-p t))))
          (with-temporary-function
              ('nshell.infrastructure.terminal:interactive-terminal-p
               (lambda (&optional fd)
                 (declare (ignore fd))
                 nil))
            (multiple-value-bind (output code)
                (call-builtin context "agent" (list "run tests"))
              (expect 2 :to-equal code)
              (expect (search "interactive terminal required" output)
                      :to-be-truthy)
              (expect nil :to-be started-p)))))))

  (it "records-executed-agent-steps-with-agent-origin"
    (with-repl-test-state
      (let ((nshell.presentation::*history-persistence-enabled-p* t))
        (with-repl-input-state (:mode :insert
                                :buffer "echo from-agent"
                                :cursor-pos 16)
          (let ((nshell.presentation::*assistant-command-origin* :agent)
                (nshell.presentation::*assistant-command-confirmed-p* t))
            (with-temporary-functions
                (('nshell.presentation::execute-ast
                  (lambda (ast)
                    (declare (ignore ast))
                    0))
                 ('nshell.infrastructure.persistence:append-history-entry
                  (lambda (text)
                    (declare (ignore text))))
                 ('nshell.presentation::render-prompt-cont
                  (lambda () nil)))
              (nshell.presentation::%execute-complete-command
               (nshell.domain.parsing:make-command-node
                "echo" (list "from-agent"))
               "echo from-agent")
              (let* ((entry (first (history-kit:history-entries
                                    nshell.presentation::*history*)))
                     (record
                       (nshell.infrastructure.persistence::history-record-for-entry
                        nshell.presentation::*history* entry)))
                (expect :agent :to-equal
                        (nshell.infrastructure.persistence::history-record-origin
                         record)))))))))

  (it "stops-after-the-configured-maximum-step-count"
    (let ((session (nshell.application:make-agent-session "task" :max-steps 2)))
      (nshell.application:agent-session-propose-step session "ls")
      (nshell.application:agent-session-record-step session "one" 0)
      (nshell.application:agent-session-propose-step session "pwd")
      (nshell.application:agent-session-record-step session "two" 0)
      (expect t :to-be
              (nshell.application:agent-session-limit-reached-p session))
      (expect 2 :to-equal
              (nshell.application:agent-session-completed-steps session))))

  (it "uses-a-positive-step-limit-from-the-shell-context"
    (let ((context
            (nshell.application:make-shell-context
             :environment (nshell.domain.environment:make-environment))))
      (setf (nshell.application:shell-context-environment context)
            (nshell.domain.environment:env-set
             (nshell.application:shell-context-environment context)
             "NSHELL_AI_MAX_STEPS" "3" nil))
      (expect 3 :to-equal
              (nshell.application:agent-max-steps-from-context context))))

  (it "records-skipped-and-interrupted-step-states"
    (let ((session (nshell.application:make-agent-session "task" :max-steps 3)))
      (nshell.application:agent-session-propose-step session "ls")
      (let ((skipped-step
              (nshell.application:agent-session-current-step session)))
        (nshell.application:agent-session-skip-step session)
        (expect :skipped :to-equal
                (nshell.application:agent-step-status skipped-step)))
      (nshell.application:agent-session-propose-step session "sleep 1")
      (let ((interrupted-step
              (nshell.application:agent-session-current-step session)))
        (nshell.application:agent-session-record-step session nil 130)
        (expect :interrupted :to-equal
                (nshell.application:agent-step-status interrupted-step)))))

  (it "redacts-agent-step-output-before-request-and-audit"
    (with-repl-test-state
      (setf *agent-test-request-payload* nil)
      (setf nshell.presentation::*last-command-output* "ghp_agent-secret-token")
      (repl-test-set-env "AGENT_SECRET" "agent-environment-secret" t)
      (with-repl-input-state (:mode :ask-waiting :buffer "continue" :cursor-pos 8)
        (with-temporary-output-file (audit-path)
          (let ((boundary
                  (nshell.feature.assistant:make-assistant-model-boundary
                   :start-fn (lambda () t)
                   :request-fn (lambda (generation payload)
                                 (declare (ignore generation))
                                 (setf *agent-test-request-payload* payload)
                                 t)
                   :poll-fn (lambda (generation)
                              (declare (ignore generation))
                              (values nil nil))
                   :stop-fn (lambda () t))))
            (setf nshell.presentation::*assistant-request-kind* :agent
                  nshell.feature.assistant:*assistant-boundaries*
                    (nshell.feature.assistant:make-assistant-boundary-context
                     boundary))
            (let ((nshell.feature.assistant:*assistant-audit-file-path-override*
                    audit-path))
              (with-temporary-functions
                  (('nshell.infrastructure.acl:get-git-status
                    (lambda (directory)
                      (declare (ignore directory))
                      (values nil nil)))
                   ('nshell.presentation::render-prompt-cont
                    (lambda () nil))
                   ('nshell.presentation::render-assistant-progress-panel
                    (lambda (started-at)
                      (declare (ignore started-at))
                      nil)))
                (nshell.presentation::%process-ask-submit-output-event))
              (let ((audit (uiop:read-file-string audit-path)))
                (expect nil :to-be
                        (search "ghp_agent-secret-token"
                                (princ-to-string *agent-test-request-payload*)))
                (expect nil :to-be
                        (search "agent-environment-secret"
                                (princ-to-string *agent-test-request-payload*)))
                (expect nil :to-be
                        (search "ghp_agent-secret-token" audit))
                (expect nil :to-be
                        (search "agent-environment-secret" audit))))))))))
