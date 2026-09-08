(in-package #:nshell/test)

(describe "assistant-state-export-contracts"
  (it "writes redacted transcript and snapshot once at the prompt boundary"
    (host-kit:with-temporary-directory (directory)
      (let* ((state-directory (merge-pathnames "state/" directory))
             (transcript-session "integration-session")
             (transcript-path
               (merge-pathnames
                (format nil "transcript-~a.jsonl" transcript-session)
                state-directory))
             (snapshot-path (merge-pathnames "snapshot.json" state-directory)))
        (let ((nshell.feature.assistant:*assistant-state-directory-path-override*
                state-directory)
              (nshell.application:*job-monitor*
                (nshell.domain.job-control:make-job-monitor)))
          (with-repl-test-state
            (setf nshell.presentation::*interactive-terminal-installed-p* t
                  nshell.presentation::*assistant-session-id* transcript-session
                  nshell.presentation::*input-state*
                    (nshell.presentation::make-repl-input-state)
                  nshell.presentation::*last-command-text*
                    "printf ghp_12345678901234567890"
                  nshell.presentation::*last-exit-code* 7
                  nshell.presentation::*last-command-duration-ms* 42
                  nshell.presentation::*assistant-pending-transcript*
                    (list :session-id transcript-session
                          :timestamp 123
                          :cwd "/tmp/project"
                          :text "printf ghp_12345678901234567890"
                          :exit 7
                          :duration-ms 42
                          :origin :proposal
                          :output-head
                          (format nil
                                  "visible~%secret-value~%ghp_12345678901234567890~%-----BEGIN PRIVATE KEY-----~%private~%-----END PRIVATE KEY-----~%cat /tmp/private.env")
                          :denylist-paths '("*/private.env")
                          :denylist-commands '("cat")
                          :denylist-values '("secret-value")))
            (repl-test-set-env "API_TOKEN" "secret-value")
            (with-temporary-function
                ('nshell.infrastructure.acl:get-git-status
                 (lambda (directory)
                   (declare (ignore directory))
                   (values "main" t)))
              (with-stable-repl-prompt ()
                (with-fixed-terminal-size (24 80)
                  (capture-standard-output
                    (nshell.presentation::render-prompt-cont)
                    (nshell.presentation::render-prompt-cont))))
            (let ((transcript (host-kit:read-file-string transcript-path))
                  (snapshot (host-kit:read-file-string snapshot-path)))
              (expect 1 :to-be (count #\Newline transcript))
              (expect (json-kit:parse transcript) :to-be-truthy)
              (expect (json-kit:parse snapshot) :to-be-truthy)
              (expect (search "\"cwd\":\"/tmp/project\"" transcript)
                      :to-be-truthy)
              (expect (search "\"exit\":7" snapshot) :to-be-truthy)
              (expect (search "\"origin\":\"proposal\"" transcript)
                      :to-be-truthy)
              (expect (search "\"API_TOKEN\"" snapshot) :to-be-truthy)
              (expect (search "visible" transcript) :to-be-truthy)
              (expect nil :to-be (search "secret-value" transcript))
              (expect nil :to-be
                      (search "ghp_12345678901234567890" transcript))
              (expect nil :to-be (search "PRIVATE KEY" transcript))
              (expect nil :to-be (search "/tmp/private.env" transcript))
              (expect nil :to-be (search "secret-value" snapshot)))))))))

  (it "does not create state files for batch or script execution"
    (host-kit:with-temporary-directory (directory)
      (let ((state-directory (merge-pathnames "state/" directory))
            (script-path (merge-pathnames "script.nsh" directory)))
        (host-kit:write-file-string (format nil "true~%") script-path)
        (let ((nshell.feature.assistant:*assistant-state-directory-path-override*
                state-directory))
          (expect 0 :to-be
                  (nshell.presentation:run-repl-batch :line "true"))
          (expect 0 :to-be
                  (nshell.presentation:run-repl-script script-path))
          (expect nil :to-be (probe-file state-directory))
          (expect nil :to-be
                  (probe-file
                   (merge-pathnames "snapshot.json" state-directory))))))))
