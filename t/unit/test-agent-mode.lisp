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

  (it "waits-for-a-key-before-dispatching-safe-model-steps"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "inspect files"
                                                             :max-steps 1))
            (dispatches 0)
            (key-reads 0)
            (continuation nil)
            (panel nil))
        (setf nshell.presentation::*agent-session* session
              nshell.presentation::*history-persistence-enabled-p* nil)
        (with-repl-input-state (:mode :ask-waiting :buffer "inspect files"
                                :cursor-pos 13)
          (with-temporary-functions
              (('nshell.application::execute-command-node-in-context
                (lambda (node context)
                  (declare (ignore node context))
                  (incf dispatches)
                  (values "fixture-output" 0)))
               ('nshell.presentation::read-key-cont
                (lambda () (incf key-reads) nil))
               ('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore arguments))
                  (setf panel content)))
               ('nshell.presentation::render-prompt-cont
                (lambda () nil)))
            (capture-standard-output
              (setf continuation
                    (nshell.presentation::%handle-agent-model-event
                     (nshell.feature.assistant::make-assistant-model-event
                      1 :result '(("command" . "ls"))))))
            (expect 0 :to-equal dispatches)
            (expect 0 :to-equal key-reads)
            (expect nil :to-be nshell.presentation::*assistant-command-confirmed-p*)
            (expect :awaiting-approval :to-equal
                    (nshell.application:agent-session-state session))
            (expect 0 :to-equal
                    (nshell.application:agent-session-completed-steps session))
            (expect nil :to-be (search "auto" (third panel)))
            (expect (functionp continuation) :to-be-truthy)
            (when (functionp continuation) (funcall continuation))
            (expect 1 :to-equal key-reads)
            (expect 0 :to-equal dispatches)))
        (setf panel nil
              nshell.presentation::*agent-session*
                (nshell.application:make-agent-session "inspect files"
                                                       :max-steps 1))
        (with-repl-input-state (:mode :ask-waiting :buffer "inspect files"
                                :cursor-pos 13)
          (with-temporary-functions
              (('nshell.presentation::render-transient-panel
                (lambda (content &rest arguments)
                  (declare (ignore arguments))
                  (setf panel content)))
               ('nshell.presentation::render-prompt-cont
                (lambda () nil)))
            (nshell.presentation::%handle-agent-model-event
             (nshell.feature.assistant::make-assistant-model-event
              1 :result '(("command" . "unterminated '")))))
          (expect "inspect files" :to-equal
                  (nshell.presentation:input-state-buffer
                   nshell.presentation::*input-state*))
          (expect (search "invalid" (third panel)) :to-be-truthy)))))

  (it "executes-a-safe-step-only-after-enter-approval"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "list files"
                                                             :max-steps 1))
            (dispatches 0)
            (observed-origin nil)
            (observed-confirmed nil))
        (nshell.application:agent-session-propose-step session "ls")
        (let ((step (nshell.application:agent-session-current-step session)))
          (setf nshell.presentation::*agent-session* session
                nshell.presentation::*history-persistence-enabled-p* nil)
          (with-repl-input-state (:mode :insert :buffer "ls" :cursor-pos 2)
            (with-temporary-functions
                (('nshell.application::execute-command-node-in-context
                  (lambda (node context)
                    (declare (ignore node context))
                    (incf dispatches)
                    (setf observed-origin nshell.application::*execution-origin*
                          observed-confirmed nshell.application::*execution-confirmed-p*)
                    (values "fixture-output" 0)))
                 ('nshell.presentation::render-prompt-cont
                  (lambda () nil))
                 ('nshell.presentation::render-transient-panel
                  (lambda (content &rest arguments)
                    (declare (ignore content arguments))
                    nil)))
              (expect 0 :to-equal dispatches)
              (capture-standard-output
                (nshell.presentation::%process-agent-panel-event
                 (input-key-event :enter))))
            (expect 1 :to-equal dispatches)
            (expect :agent :to-be observed-origin)
            (expect t :to-be observed-confirmed)
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

  (it "accepts-q-and-s-as-text-while-editing"
    (dolist (character '(#\q #\s))
      (with-repl-test-state
        (let ((session (nshell.application:make-agent-session "list files" :max-steps 1))
              (dispatches 0))
          (nshell.application:agent-session-propose-step session "ls")
          (setf nshell.presentation::*agent-session* session)
          (with-repl-input-state (:mode :insert :buffer "ls" :cursor-pos 2)
            (with-temporary-functions
                (('nshell.application::execute-command-node-in-context
                  (lambda (context node)
                    (declare (ignore context node))
                    (incf dispatches)
                    (values "" 0)))
                 ('nshell.presentation::render-prompt-cont (lambda () nil))
                 ('nshell.presentation::render-transient-panel
                  (lambda (&rest arguments) (declare (ignore arguments)) nil))
                 ('nshell.presentation::process-output-event
                  (lambda (event) (declare (ignore event)) nil)))
              (nshell.presentation::%process-agent-panel-event (input-key-event :char #\e))
              (nshell.presentation::%process-agent-panel-event (input-key-event :char character))
              (expect :editing :to-equal (nshell.application:agent-session-state session))
              (expect session :to-be nshell.presentation::*agent-session*)
              (expect (concatenate 'string "ls" (string character))
                      :to-equal (nshell.presentation:input-state-buffer
                                 nshell.presentation::*input-state*))
              (expect :awaiting-approval :to-equal
                      (nshell.application:agent-step-status
                       (nshell.application:agent-session-current-step session)))
              (expect 0 :to-equal dispatches)
              (expect nil :to-be nshell.presentation::*assistant-command-confirmed-p*)))))))

  (it "cancels-editing-with-control-c-without-executing"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "list files" :max-steps 1))
            (dispatches 0))
        (let ((step (nshell.application:agent-session-propose-step session "ls")))
          (setf nshell.presentation::*agent-session* session)
          (with-repl-input-state (:mode :insert :buffer "ls" :cursor-pos 2)
            (with-temporary-functions
                (('nshell.application::execute-command-node-in-context
                  (lambda (context node)
                    (declare (ignore context node))
                    (incf dispatches)
                    (values "" 0)))
                 ('nshell.presentation::render-prompt-cont (lambda () nil))
                 ('nshell.presentation::render-transient-panel
                  (lambda (&rest arguments) (declare (ignore arguments)) nil)))
              (nshell.presentation::%process-agent-panel-event (input-key-event :char #\e))
              (nshell.presentation::%process-agent-panel-event (input-key-event :ctrl-c))
              (expect :stopped :to-equal (nshell.application:agent-session-state session))
              (expect "canceled" :to-equal (nshell.application:agent-session-stop-reason session))
              (expect nil :to-be nshell.presentation::*agent-session*)
              (expect "" :to-equal (nshell.presentation:input-state-buffer
                                   nshell.presentation::*input-state*))
              (expect :awaiting-approval :to-equal (nshell.application:agent-step-status step))
              (expect 0 :to-equal dispatches)
              (expect nil :to-be nshell.presentation::*assistant-command-confirmed-p*)))))))

  (it "does-not-mint-approval-in-the-step-executor"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "list files" :max-steps 1))
            (dispatches 0))
        (nshell.application:agent-session-propose-step session "ls")
        (setf nshell.presentation::*agent-session* session
              nshell.presentation::*history-persistence-enabled-p* nil)
        (with-repl-input-state (:mode :insert :buffer "ls" :cursor-pos 2)
          (with-temporary-functions
              (('nshell.application::execute-command-node-in-context
                (lambda (context node)
                  (declare (ignore context node))
                  (incf dispatches)
                  (values "fixture-output" 0)))
               ('nshell.presentation::render-prompt-cont (lambda () nil))
               ('nshell.presentation::render-transient-panel
                (lambda (&rest arguments) (declare (ignore arguments)) nil)))
            (capture-standard-output
              (nshell.presentation::%agent-execute-current-step))
            (expect 0 :to-equal dispatches)
            (expect nil :to-be nshell.presentation::*assistant-command-confirmed-p*)
            (expect :awaiting-approval :to-equal
                    (nshell.application:agent-session-state session)))))))

  (it "reclassifies-edited-input-before-enter-approval"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "inspect files" :max-steps 1))
            (dispatches 0)
            (classification nil)
            (observed-text nil)
            (observed-origin nil)
            (observed-confirmed nil))
        (nshell.application:agent-session-propose-step session "ls")
        (setf nshell.presentation::*agent-session* session
              nshell.presentation::*history-persistence-enabled-p* nil)
        (with-repl-input-state (:mode :insert :buffer "ls" :cursor-pos 2)
          (with-temporary-functions
              (('nshell.application::execute-command-node-in-context
                (lambda (context node)
                  (declare (ignore context node))
                  (incf dispatches)
                  (let ((step (nshell.application:agent-session-current-step session)))
                    (setf classification
                          (nshell.feature.assistant:assistant-safety-result-classification
                           (nshell.application:agent-step-classification step))
                          observed-text (nshell.application:agent-step-text step)
                          observed-origin nshell.application::*execution-origin*
                          observed-confirmed nshell.application::*execution-confirmed-p*))
                  (values "fixture-output" 0)))
               ('nshell.presentation::render-prompt-cont (lambda () nil))
               ('nshell.presentation::render-transient-panel
                (lambda (&rest arguments) (declare (ignore arguments)) nil)))
            (nshell.presentation::%process-agent-panel-event (input-key-event :char #\e))
            (setf nshell.presentation::*input-state*
                  (nshell.presentation::make-repl-input-state :buffer "rm -rf /"))
            (nshell.presentation::%process-agent-panel-event (input-key-event :enter))
            (expect 0 :to-equal dispatches)
            (expect nil :to-be nshell.presentation::*assistant-command-confirmed-p*)
            (expect t :to-be
                    (nshell.application:agent-step-blocked-p
                     (nshell.application:agent-session-current-step session)))
            (nshell.presentation::%process-agent-panel-event (input-key-event :char #\e))
            (setf nshell.presentation::*input-state*
                  (nshell.presentation::make-repl-input-state :buffer "rm fixture"))
            (expect 0 :to-equal dispatches)
            (capture-standard-output
              (nshell.presentation::%process-agent-panel-event (input-key-event :enter)))
            (expect 1 :to-equal dispatches)
            (expect :confirm :to-be classification)
            (expect "rm fixture" :to-equal observed-text)
            (expect :agent :to-be observed-origin)
            (expect t :to-be observed-confirmed))))))

  (it "requires-fresh-enter-approval-for-the-next-step"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "inspect files" :max-steps 2))
            (dispatches 0)
            (requests 0)
            (approval-at-request :unset)
            (dispatch-origins nil)
            (dispatch-approvals nil))
        (nshell.application:agent-session-propose-step session "ls")
        (setf nshell.presentation::*agent-session* session
              nshell.presentation::*history-persistence-enabled-p* nil)
        (with-repl-input-state (:mode :insert :buffer "ls" :cursor-pos 2)
          (with-temporary-functions
              (('nshell.application::execute-command-node-in-context
                (lambda (context node)
                  (declare (ignore context node))
                  (incf dispatches)
                  (push nshell.application::*execution-origin* dispatch-origins)
                  (push nshell.application::*execution-confirmed-p* dispatch-approvals)
                  (values "fixture-output" 0)))
               ('nshell.presentation::%process-ask-submit-output-event
                (lambda ()
                  (incf requests)
                  (setf approval-at-request
                        nshell.presentation::*assistant-command-confirmed-p*)))
               ('nshell.presentation::read-key-cont (lambda () nil))
               ('nshell.presentation::render-prompt-cont (lambda () nil))
               ('nshell.presentation::render-transient-panel
                (lambda (&rest arguments) (declare (ignore arguments)) nil)))
            (capture-standard-output
              (nshell.presentation::%process-agent-panel-event (input-key-event :enter)))
            (expect 1 :to-equal dispatches)
            (expect 1 :to-equal requests)
            (expect nil :to-be approval-at-request)
            (expect nil :to-be nshell.presentation::*assistant-command-confirmed-p*)
            (nshell.presentation::%handle-agent-model-event
             (nshell.feature.assistant::make-assistant-model-event
              2 :result '(("command" . "ls"))))
            (expect 1 :to-equal dispatches)
            (expect :awaiting-approval :to-equal
                    (nshell.application:agent-session-state session))
            (capture-standard-output
              (nshell.presentation::%process-agent-panel-event (input-key-event :enter)))
            (expect 2 :to-equal dispatches)
            (expect '(:agent :agent) :to-equal dispatch-origins)
            (expect '(t t) :to-equal dispatch-approvals)
            (nshell.presentation::%process-agent-panel-event (input-key-event :enter))
            (expect 2 :to-equal dispatches)
            (expect nil :to-be nshell.presentation::*assistant-command-confirmed-p*))))))

  (it "skips-a-step-with-s-and-does-not-execute-the-rest"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "list files"
                                                             :max-steps 1))
            (dispatches 0))
        (nshell.application:agent-session-propose-step session "rm -rf /")
        (let ((step (nshell.application:agent-session-current-step session)))
          (setf nshell.presentation::*agent-session* session)
          (with-repl-input-state (:mode :insert :buffer "ls" :cursor-pos 2)
            (with-temporary-functions
                (('nshell.application::execute-command-node-in-context
                  (lambda (context node)
                    (declare (ignore context node))
                    (incf dispatches)
                    (values "fixture-output" 0)))
                 ('nshell.presentation::render-transient-panel
                 (lambda (content &rest arguments)
                   (declare (ignore content arguments))
                   nil)))
              (nshell.presentation::%process-agent-panel-event
               (input-key-event :char #\s)))
            (expect :skipped :to-equal
                    (nshell.application:agent-step-status step))
            (expect 0 :to-equal dispatches)
            (expect nil :to-be nshell.presentation::*assistant-command-confirmed-p*)
            (expect nil :to-be nshell.presentation::*agent-session*))))))

  (it "cancels-an-agent-session-with-q"
    (with-repl-test-state
      (let ((session (nshell.application:make-agent-session "list files"
                                                             :max-steps 1))
            (dispatches 0))
        (nshell.application:agent-session-propose-step session "rm -rf /")
        (setf nshell.presentation::*agent-session* session)
        (with-repl-input-state (:mode :insert :buffer "ls" :cursor-pos 2)
          (with-temporary-functions
              (('nshell.application::execute-command-node-in-context
                (lambda (context node)
                  (declare (ignore context node))
                  (incf dispatches)
                  (values "fixture-output" 0)))
               ('nshell.presentation::render-prompt-cont
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
          (expect 0 :to-equal dispatches)
          (expect nil :to-be nshell.presentation::*assistant-command-confirmed-p*)
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
                       (nshell.infrastructure.persistence:history-record-for-entry
                        nshell.presentation::*history* entry)))
                (expect :agent :to-equal
                        (nshell.infrastructure.persistence:history-record-origin
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
      (setf nshell.presentation::*last-command-output*
              (format nil "cat /tmp/private.env~%ghp_agent-secret-token"))
      (repl-test-set-env "AGENT_SECRET" "agent-environment-secret" t)
      (with-repl-input-state (:mode :ask-waiting :buffer "continue" :cursor-pos 8)
        (host-kit:with-temporary-directory (audit-directory)
          (let ((audit-path (merge-pathnames "ai-audit.jsonl" audit-directory))
                (boundary
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
                        (search "/tmp/private.env"
                                (princ-to-string *agent-test-request-payload*)))
                (expect nil :to-be
                        (search "agent-environment-secret"
                                (princ-to-string *agent-test-request-payload*)))
                (expect nil :to-be
                        (search "ghp_agent-secret-token" audit))
                (expect nil :to-be
                        (search "agent-environment-secret" audit))))))))))
