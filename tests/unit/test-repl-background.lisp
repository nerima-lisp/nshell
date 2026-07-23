(in-package #:nshell/test)

(describe "repl-tests"
  (it "repl-background-execution-expands-command-position-word"
    "Background execution expands the command word before spawning."
    (with-repl-test-state
      (let ((nshell.application:*job-monitor*
              (nshell.domain.job-control:make-job-monitor)))
        (repl-test-set-env "CMD" "true")
        (with-complete-command-line (result ast "$CMD bg-word")
          (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
          (let ((sequence (nshell.domain.parsing::make-sequence-node
                           (list ast)
                           '(:amp))))
            (multiple-value-bind (output-text code)
                (call-repl-execute-ast sequence)
              (expect "" :to-equal output-text)
              (expect 0 :to-equal code))
            (let* ((entries (collect-monitor-entries
                             nshell.application:*job-monitor*))
                   (job (test-monitor-entry-job (first entries))))
              (expect 1 :to-equal (length entries))
              (expect "true bg-word" :to-equal (nshell.domain.execution:job-command-display-string
                            job))))))))

  (it "repl-background-execution-rejects-ambiguous-command-position-expansion"
    "Background execution rejects empty or multi-field command name expansion."
    (dolist (case '(("" 0)
                    ("echo split" 2)))
      (destructuring-bind (value expected-fields) case
        (with-repl-test-state
          (let ((nshell.application:*job-monitor*
                  (nshell.domain.job-control:make-job-monitor)))
            (repl-test-set-env "CMD" value)
            (with-complete-command-line (result ast "$CMD bg-word")
              (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
              (let ((sequence (nshell.domain.parsing::make-sequence-node
                               (list ast)
                               '(:amp))))
                (multiple-value-bind (output-text code)
                    (call-repl-execute-ast sequence)
                  (expect 127 :to-equal code)
                  (expect (format nil "nshell: $CMD: command name expansion produced ~d fields~%"
                                        expected-fields) :to-equal output-text)
                  (expect (collect-monitor-entries
                             nshell.application:*job-monitor*) :to-be-null)))))))))

  (it "repl-background-command-applies-redirections"
    "Background commands should apply redirects before spawning the process."
    (with-repl-test-state
        (let ((nshell.application:*job-monitor*
                (nshell.domain.job-control:make-job-monitor)))
          (with-temporary-output-file (output :prefix "nshell-bg-redirect-")
            (let ((ast (nshell.domain.parsing::make-sequence-node
                        (list (nshell.domain.parsing:make-command-node
                               "printf"
                               (list (nshell.domain.parsing:make-command-arg "%s" :single) "bg" ">" output)))
                        '(:amp))))
              (multiple-value-bind (output-text code)
                  (call-repl-execute-ast ast)
                (declare (ignore output-text code)))
              (expect (wait-for-file-content output "bg") :to-be-truthy)
              (let* ((entries (collect-monitor-entries
                               nshell.application:*job-monitor*))
                     (job (test-monitor-entry-job (first entries))))
                (expect 1 :to-equal (length entries))
                (expect "printf %s bg" :to-equal (nshell.domain.execution:job-command-display-string
                              job)))
              (expect (probe-file output) :to-be-truthy)
              (expect "bg" :to-equal (uiop:read-file-string output)))))))

  (it "repl-background-pipeline-registers-processes-and-applies-redirections"
    "Background pipelines should spawn every stage and keep their redirects."
    (with-repl-test-state
        (let ((nshell.application:*job-monitor*
                (nshell.domain.job-control:make-job-monitor)))
          (with-temporary-output-file (output :prefix "nshell-bg-pipeline-")
            (let* ((pipeline (nshell.domain.parsing:make-pipeline-node
                              (list (nshell.domain.parsing:make-command-node
                                     "printf"
                                     (list (nshell.domain.parsing:make-command-arg "%s" :single) "bg-pipe"))
                                    (nshell.domain.parsing:make-command-node
                                     "cat"
                                     (list ">" output)))))
                   (ast (nshell.domain.parsing::make-sequence-node
                         (list pipeline)
                         '(:amp))))
              (multiple-value-bind (output-text code)
                  (call-repl-execute-ast ast)
                (declare (ignore output-text code)))
              (expect (wait-for-file-content output "bg-pipe") :to-be-truthy)
              (let* ((entries (collect-monitor-entries
                               nshell.application:*job-monitor*))
                     (job (test-monitor-entry-job (first entries))))
                (expect 1 :to-equal (length entries))
                (expect 2 :to-equal (length (nshell.domain.execution:job-pids job)))
                (expect (nshell.domain.execution:job-background-p job) :to-be-truthy)
                (expect "printf %s bg-pipe | cat" :to-equal (nshell.domain.execution:job-command-display-string
                              job)))
              (expect (probe-file output) :to-be-truthy)
              (expect "bg-pipe" :to-equal (uiop:read-file-string output)))))))

  (it "reap-background-jobs-removes-only-completed-processes"
    "Reaping should update completed jobs and leave live ones alone."
    (with-repl-test-state
        (let* ((monitor (nshell.domain.job-control:make-job-monitor))
               (completed-job (make-test-job 0 "sleep"))
               (alive-job (make-test-job 1 "sleep"))
               (completed-proc :completed)
               (alive-proc :alive)
               (completed-job-id (nshell.domain.job-control:monitor-add-job
                                  monitor completed-job))
               (alive-job-id (nshell.domain.job-control:monitor-add-job
                              monitor alive-job)))
          (let ((nshell.application:*job-monitor* monitor))
            (repl-test-register-process-entry completed-job-id completed-proc)
            (repl-test-register-process-entry alive-job-id alive-proc)
            (let ((nshell.presentation::*background-proc-alive-p*
                    (lambda (proc)
                      (eq proc alive-proc)))
                  (nshell.presentation::*background-proc-exit-code*
                    (lambda (proc)
                      (declare (ignore proc))
                      17)))
              (nshell.presentation::reap-background-jobs))
            (expect (repl-test-process-entry completed-job-id) :to-be-null)
            (expect alive-proc :to-be (repl-test-process-entry alive-job-id))
            (expect :completed :to-be (nshell.domain.execution:job-state completed-job))
            (expect 17 :to-equal (nshell.domain.execution:job-exit-code completed-job))
            (expect :created :to-be (nshell.domain.execution:job-state alive-job))
            (let ((output (with-output-to-string (out)
                            (dolist (listing (nshell.application:jobs))
                              (nshell.application:format-job-listing listing out)))))
                (expect (search "[1] Done sleep" output) :to-be-truthy)
                (expect (search "[2] Created sleep" output) :to-be-truthy))))))

  (it "reap-background-jobs-handles-process-lists"
    "Reaping should treat process lists as a single background job entry."
    (with-repl-test-state
        (let* ((monitor (nshell.domain.job-control:make-job-monitor))
               (completed-job (make-test-job 0 "sleep"))
               (alive-job (make-test-job 1 "sleep"))
               (completed-proc-1 :completed-1)
               (completed-proc-2 :completed-2)
               (alive-proc :alive)
               (completed-job-id (nshell.domain.job-control:monitor-add-job
                                  monitor completed-job))
               (alive-job-id (nshell.domain.job-control:monitor-add-job
                              monitor alive-job)))
          (let ((nshell.application:*job-monitor* monitor))
            (repl-test-register-process-entry
             completed-job-id
             (list completed-proc-1 completed-proc-2))
            (repl-test-register-process-entry
             alive-job-id
             (list completed-proc-1 alive-proc))
            (let ((nshell.presentation::*background-proc-alive-p*
                    (lambda (proc)
                      (eq proc alive-proc)))
                  (nshell.presentation::*background-proc-exit-code*
                    (lambda (proc)
                      (case proc
                        (:completed-1 11)
                        (:completed-2 23)
                        (t 0)))))
              (nshell.presentation::reap-background-jobs))
            (expect (repl-test-process-entry completed-job-id) :to-be-null)
            (expect (list completed-proc-1 alive-proc) :to-equal (repl-test-process-entry alive-job-id))
            (expect :completed :to-be (nshell.domain.execution:job-state completed-job))
            (expect 23 :to-equal (nshell.domain.execution:job-exit-code completed-job))
            (expect :created :to-be (nshell.domain.execution:job-state alive-job))))))

  (it "reap-background-jobs-normalizes-signaled-process-status"
    "Completed background jobs should store shell-compatible signal exit statuses."
    (with-repl-test-state
        (let* ((monitor (nshell.domain.job-control:make-job-monitor))
               (job (make-test-job 0 "sh -c 'kill -TERM $$'"))
               (job-id (nshell.domain.job-control:monitor-add-job monitor job))
               (proc (sb-ext:run-program "sh" '("-c" "kill -TERM $$")
                                         :wait nil
                                         :search t)))
          (unwind-protect
               (progn
                 (sb-ext:process-wait proc)
                 (let ((nshell.application:*job-monitor* monitor))
                   (repl-test-register-process-entry job-id proc)
                   (nshell.presentation::reap-background-jobs)
                   (expect (repl-test-process-entry job-id) :to-be-null)
                   (expect :completed :to-be (nshell.domain.execution:job-state job))
                   (expect 143 :to-equal (nshell.domain.execution:job-exit-code job))))
            (when (and proc (sb-ext:process-alive-p proc))
              (sb-ext:process-kill proc 15)))))))
