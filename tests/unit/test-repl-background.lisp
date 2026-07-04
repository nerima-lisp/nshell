(in-package #:nshell/test)

(in-suite repl-tests)

(test repl-background-preparation-expands-command-position-word
  "Background preparation expands the command word before spawning."
  (with-repl-test-state
    (setf nshell.presentation::*environment*
          (nshell.domain.environment:env-set
           nshell.presentation::*environment*
           "CMD" "echo" nil))
    (with-complete-command-line (result ast "$CMD bg-word")
      (is (null (nshell.domain.parsing:parse-errors result)))
      (multiple-value-bind (cmd redirects error)
          (nshell.presentation::%prepare-command-node ast)
        (is (null error))
        (is (null redirects))
        (is (string= "echo"
                     (nshell.domain.parsing:command-node-command cmd)))
        (is (equal '("bg-word")
                   (nshell.domain.parsing:command-node-arg-values cmd)))))))

(test repl-background-preparation-rejects-ambiguous-command-position-expansion
  "Background preparation rejects empty or multi-field command name expansion."
  (dolist (case '(("" 0)
                  ("echo split" 2)))
    (destructuring-bind (value expected-fields) case
      (with-repl-test-state
        (setf nshell.presentation::*environment*
              (nshell.domain.environment:env-set
               nshell.presentation::*environment*
               "CMD" value nil))
        (with-complete-command-line (result ast "$CMD bg-word")
          (is (null (nshell.domain.parsing:parse-errors result)))
          (multiple-value-bind (cmd redirects error)
              (nshell.presentation::%prepare-command-node ast)
            (is (null cmd))
            (is (null redirects))
            (is (string= (format nil "nshell: $CMD: command name expansion produced ~d fields~%"
                                 expected-fields)
                         error))))))))

(test repl-background-command-applies-redirections
  "Background commands should apply redirects before spawning the process."
  (with-repl-test-state
      (let ((nshell.application:*job-monitor*
              (nshell.domain.job-control:make-job-monitor)))
        (with-temporary-output-file (output :prefix "nshell-bg-redirect-")
          (let ((ast (nshell.domain.parsing::make-sequence-node
                      (list (nshell.domain.parsing:make-command-node
                             "printf"
                             (list (cons "%s" :single) "bg" ">" output)))
                      '(:amp))))
            (multiple-value-bind (output-text code)
                (call-repl-execute-ast ast)
              (declare (ignore output-text code)))
            (is (wait-for-file-content output "bg"))
            (let* ((entries (nshell.domain.job-control:monitor-entries
                             nshell.application:*job-monitor*))
                   (job (cdar entries)))
              (is (= 1 (length entries)))
              (is (string= "printf %s bg"
                           (nshell.domain.execution:job-command-display-string
                            job))))
            (is (probe-file output))
            (is (string= "bg" (uiop:read-file-string output))))))))

(test repl-background-pipeline-registers-processes-and-applies-redirections
  "Background pipelines should spawn every stage and keep their redirects."
  (with-repl-test-state
      (let ((nshell.application:*job-monitor*
              (nshell.domain.job-control:make-job-monitor)))
        (with-temporary-output-file (output :prefix "nshell-bg-pipeline-")
          (let* ((pipeline (nshell.domain.parsing:make-pipeline-node
                            (list (nshell.domain.parsing:make-command-node
                                   "printf"
                                   (list (cons "%s" :single) "bg-pipe"))
                                  (nshell.domain.parsing:make-command-node
                                   "cat"
                                   (list ">" output)))))
                 (ast (nshell.domain.parsing::make-sequence-node
                       (list pipeline)
                       '(:amp))))
            (multiple-value-bind (output-text code)
                (call-repl-execute-ast ast)
              (declare (ignore output-text code)))
            (is (wait-for-file-content output "bg-pipe"))
            (let* ((entries (nshell.domain.job-control:monitor-entries
                             nshell.application:*job-monitor*))
                   (job (cdar entries)))
              (is (= 1 (length entries)))
              (is (= 2 (length (nshell.domain.execution:job-pids job))))
              (is (nshell.domain.execution:job-background-p job))
              (is (string= "printf %s bg-pipe | cat"
                           (nshell.domain.execution:job-command-display-string
                            job))))
            (is (probe-file output))
            (is (string= "bg-pipe" (uiop:read-file-string output))))))))

(test reap-background-jobs-removes-only-completed-processes
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
        (let ((nshell.application:*job-monitor* monitor)
              (nshell.presentation::*proc-registry*
                (make-hash-table :test #'eql)))
          (setf (gethash completed-job-id nshell.presentation::*proc-registry*)
                  completed-proc
                  (gethash alive-job-id nshell.presentation::*proc-registry*)
                  alive-proc)
            (let ((nshell.presentation::*background-proc-alive-p*
                    (lambda (proc)
                      (eq proc alive-proc)))
                  (nshell.presentation::*background-proc-exit-code*
                    (lambda (proc)
                      (declare (ignore proc))
                      17)))
              (nshell.presentation::reap-background-jobs))
            (is (null (gethash completed-job-id
                               nshell.presentation::*proc-registry*)))
            (is (eq alive-proc
                  (gethash alive-job-id nshell.presentation::*proc-registry*)))
          (is (eq :completed (nshell.domain.execution:job-state completed-job)))
          (is (= 17 (nshell.domain.execution:job-exit-code completed-job)))
          (is (eq :created (nshell.domain.execution:job-state alive-job)))
          (let ((output (with-output-to-string (out)
                          (dolist (listing (nshell.application:jobs))
                            (nshell.application:format-job-listing listing out)))))
              (is (search "[1] Done sleep" output))
              (is (search "[2] Created sleep" output)))))))

(test reap-background-jobs-handles-process-lists
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
        (let ((nshell.application:*job-monitor* monitor)
              (nshell.presentation::*proc-registry*
                (make-hash-table :test #'eql)))
          (setf (gethash completed-job-id nshell.presentation::*proc-registry*)
                  (list completed-proc-1 completed-proc-2)
                (gethash alive-job-id nshell.presentation::*proc-registry*)
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
          (is (null (gethash completed-job-id
                             nshell.presentation::*proc-registry*)))
          (is (equal (list completed-proc-1 alive-proc)
                     (gethash alive-job-id nshell.presentation::*proc-registry*)))
          (is (eq :completed (nshell.domain.execution:job-state completed-job)))
          (is (= 23 (nshell.domain.execution:job-exit-code completed-job)))
          (is (eq :created (nshell.domain.execution:job-state alive-job)))))))

(test reap-background-jobs-normalizes-signaled-process-status
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
               (let ((nshell.application:*job-monitor* monitor)
                     (nshell.presentation::*proc-registry*
                       (make-hash-table :test #'eql)))
                 (setf (gethash job-id nshell.presentation::*proc-registry*) proc)
                 (nshell.presentation::reap-background-jobs)
                 (is (null (gethash job-id nshell.presentation::*proc-registry*)))
                 (is (eq :completed (nshell.domain.execution:job-state job)))
                 (is (= 143 (nshell.domain.execution:job-exit-code job)))))
          (when (and proc (sb-ext:process-alive-p proc))
            (sb-ext:process-kill proc 15))))))
