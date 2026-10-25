(in-package #:nshell/test)

(defun %make-command-failure-fixture (names status stage-statuses stage-signals)
  (let ((commands
         (mapcar
          (lambda (name)
            (nshell.domain.parsing:make-command-node name nil))
          names)))
    (values
     (if (cdr commands)
         (nshell.domain.parsing:make-pipeline-node commands)
         (first commands))
     (nshell.application:make-pipeline-execution-result status stage-statuses stage-signals))))
(defun %call-with-command-failure-test-input (events thunk)
  (let* ((reader-symbol 'nshell.infrastructure.terminal:read-key-event)
         (original-reader (symbol-function reader-symbol))
         (read-count 0)
         (results nil))
    (unwind-protect
        (progn
          (setf (symbol-function reader-symbol)
                (lambda (&key interrupt-predicate)
                  (declare (ignore interrupt-predicate))
                  (incf read-count)
                  (pop events)))
          (setf results
                (let ((*standard-output* (make-string-output-stream)))
                  (multiple-value-list (funcall thunk)))))
      (setf (symbol-function reader-symbol) original-reader))
    (values results read-count)))

(describe "command-failure-policy"
          (it
           "ignores upstream SIGPIPE and reports the first other failure in source order"
           (multiple-value-bind (command pipeline-result)
               (%make-command-failure-fixture
                '("upstream" "first-failure" "later-failure")
                4
                '(141 5 4)
                (list sb-unix:sigpipe nil nil))
             (let ((failure
                    (let ((nshell.application:*interactive-top-level-p* nil)
                          (nshell.application:*errexit-p* nil)
                          (nshell.application:*command-test-position-p* nil))
                      (handler-case (progn
                                      (nshell.application:call-with-command-failure-policy
                                       command
                                       (lambda ()
                                         (values :value 4 pipeline-result)))
                                      nil)
                        (nshell.application:command-failed (condition)
                          condition)))))
               (expect (nshell.application:command-failed-command failure)
                       :to-equal
                       "first-failure")
               (expect (nshell.application:command-failed-status failure)
                       :to-equal
                       5)
               (expect
                (nshell.application:command-failed-stage-statuses failure)
                :to-equal
                '(141 5 4))
               (expect (nshell.application:command-failed-signal failure)
                       :to-equal
                       nil))))
          (it
           "preserves the final status and rejects inconsistent stage metadata"
           (multiple-value-bind (command pipeline-result)
               (%make-command-failure-fixture '("failure") 17 '(17) '(nil))
             (let ((results
                    (let ((nshell.application:*interactive-top-level-p* nil)
                          (nshell.application:*errexit-p* nil)
                          (nshell.application:*command-test-position-p* nil))
                      (handler-bind ((nshell.application:command-failed
                                      (lambda (condition)
                                        (declare (ignore condition))
                                        (invoke-restart
                                         'nshell.application::continue-command-failure))))
                        (multiple-value-list
                         (nshell.application:call-with-command-failure-policy
                          command
                          (lambda ()
                            (values :original-value 17 pipeline-result))))))))
               (progn
                 (expect results :to-equal '(nil 17))
                 (expect
                  (handler-case
                      (progn
                        (nshell.application:call-with-command-failure-policy
                         command
                         (lambda ()
                           (values :value
                                   0
                                   (nshell.application:make-pipeline-execution-result
                                    0 '(9) '(nil)))))
                        nil)
                    (error () t))
                  :to-be-truthy)))))
          (it
           "suppresses an interactive top-level failure and a test-position failure"
           (multiple-value-bind (command pipeline-result)
               (%make-command-failure-fixture '("failure") 9 '(9) '(nil))
             (let ((interactive-values
                    (let ((nshell.application:*interactive-top-level-p* t)
                          (nshell.application:*errexit-p* nil)
                          (nshell.application:*command-test-position-p* nil))
                      (multiple-value-list
                       (nshell.application:call-with-command-failure-policy
                        command
                        (lambda ()
                          (values :interactive-value 9 pipeline-result))))))
                   (test-position-values
                    (let ((nshell.application:*interactive-top-level-p* nil)
                          (nshell.application:*errexit-p* t)
                          (nshell.application:*command-test-position-p* t))
                      (multiple-value-list
                       (nshell.application:call-with-command-failure-policy
                        command
                        (lambda ()
                          (values :test-value 9 pipeline-result)))))))
               (expect interactive-values :to-equal '(:interactive-value 9))
               (expect test-position-values :to-equal '(:test-value 9)))))
          (it
           "signals a failure when errexit is active at the interactive top level"
           (multiple-value-bind (command pipeline-result)
               (%make-command-failure-fixture '("failure") 9 '(9) '(nil))
             (let ((failure
                    (let ((nshell.application:*interactive-top-level-p* t)
                          (nshell.application:*errexit-p* t)
                          (nshell.application:*command-test-position-p* nil))
                      (handler-case (progn
                                      (nshell.application:call-with-command-failure-policy
                                       command
                                       (lambda ()
                                         (values :value 9 pipeline-result)))
                                      nil)
                        (nshell.application:command-failed (condition)
                          condition)))))
               (expect failure :to-be-truthy)
               (expect (nshell.application:command-failed-status failure)
                       :to-equal
                       9)))))

(describe "command-failure-restarts"
          (it "keeps reading until choice 1 is submitted, then continues the nested function"
              (multiple-value-bind (command pipeline-result)
                  (%make-command-failure-fixture '("nested-failure") 7 '(7) '(nil))
                (let ((continued-p nil))
                  (multiple-value-bind (results read-count)
                      (%call-with-command-failure-test-input
                       (list (nshell.domain.input:make-key-event :char #\2)
                             (nshell.domain.input:make-key-event :char #\1)
                             (nshell.domain.input:make-key-event :enter))
                       (lambda ()
                         (nshell.presentation:call-with-command-failure-restarts
                          (lambda ()
                            (let ((nshell.application:*interactive-top-level-p* nil)
                                  (nshell.application:*errexit-p* nil)
                                  (nshell.application:*command-test-position-p* nil))
                              (multiple-value-prog1
                                  (nshell.application:call-with-command-failure-policy
                                   command
                                   (lambda () (values :original-value 7 pipeline-result)))
                                (setf continued-p t)))))))
                    (expect read-count :to-equal 3)
                    (expect continued-p :to-be-truthy)
                    (expect results :to-equal '(nil 7))))))
          (it "returns to the prompt on Ctrl-C without running the rest of the function"
              (multiple-value-bind (command pipeline-result)
                  (%make-command-failure-fixture '("nested-failure") 11 '(11) '(nil))
                (let ((continued-p nil))
                  (multiple-value-bind (results read-count)
                      (%call-with-command-failure-test-input
                       (list (nshell.domain.input:make-key-event :ctrl-c))
                       (lambda ()
                         (nshell.presentation:call-with-command-failure-restarts
                          (lambda ()
                            (let ((nshell.application:*interactive-top-level-p* nil)
                                  (nshell.application:*errexit-p* nil)
                                  (nshell.application:*command-test-position-p* nil))
                              (multiple-value-prog1
                                  (nshell.application:call-with-command-failure-policy
                                   command
                                   (lambda () (values :original-value 11 pipeline-result)))
                                (setf continued-p t)))))))
                    (expect read-count :to-equal 1)
                    (expect continued-p :to-be-falsy)
                    (expect results :to-equal '(nil 11))))))
          (it "preserves the continue restart through the evaluator status handler"
              (multiple-value-bind (command pipeline-result)
                  (%make-command-failure-fixture '("upstream" "final") 0 '(7 0) '(nil nil))
                (let* ((executor-symbol
                        (find-symbol "EXECUTE-READER-AST-IN-CONTEXT" "NSHELL.APPLICATION"))
                       (original-executor (symbol-function executor-symbol)))
                  (unwind-protect
                      (progn
                        (setf (symbol-function executor-symbol)
                              (lambda (context ast command-executor)
                                (declare (ignore context ast command-executor))
                                (values :original-value 0 pipeline-result)))
                        (multiple-value-bind (results read-count)
                            (%call-with-command-failure-test-input
                             (list (nshell.domain.input:make-key-event :char (code-char 49))
                                   (nshell.domain.input:make-key-event :enter))
                             (lambda ()
                               (let ((nshell.application::*current-evaluation-status* 0))
                                 (nshell.presentation:call-with-command-failure-restarts
                                  (lambda ()
                                    (let ((nshell.application:*errexit-p* t))
                                      (multiple-value-bind (value)
                                          (nshell.application::%eval-command-ast-in-position (make-test-shell-context) command nil nil :stream)
                                        (values value
                                                nshell.application::*current-evaluation-status*))))))))
                          (expect read-count :to-equal 2)
                          (expect results :to-equal (list nil 0))))
                    (setf (symbol-function executor-symbol) original-executor))))))

(describe "missing-command-suggestion-tests"
  (it "uses external knowledge and PATH candidates without spawning commands"
    (with-repl-test-state
      (nshell.presentation::seed-repl-completion-knowledge-base
       nshell.presentation::*kb*)
      (repl-test-set-env "PATH" "/__nshell_c04_empty_path__")
      (expect (nshell.domain.completion:kb-command-present-p
               nshell.presentation::*kb* "git")
              :to-be-truthy)
      (expect (member "git" (nshell.presentation::%repl-path-command-names)
                      :test #'string=)
              :to-be-null)
      (host-kit:with-temporary-directory (directory)
        (let ((grep-path (merge-pathnames "grep" directory))
              (spawn-count 0))
          (host-kit:write-file-string "#!/bin/sh" grep-path)
          (sb-posix:chmod (namestring grep-path) #o700)
          (with-rebound-function
              (nshell.infrastructure.acl::%spawn-posix-process
               (lambda (&rest arguments)
                 (declare (ignore arguments))
                 (incf spawn-count)
                 (error "missing-command suggestions must not spawn processes")))
            (expect (member "git"
                            (nshell.presentation::%repl-command-corrections "gti")
                            :test #'string=)
                    :to-be-truthy)
            (setf nshell.presentation::*kb*
                  (nshell.domain.completion:make-empty-knowledge-base))
            (repl-test-set-env "PATH" (namestring directory))
            (expect (member "grep" (nshell.presentation::%repl-path-command-names)
                            :test #'string=)
                    :to-be-truthy)
            (expect (nshell.domain.completion:kb-command-present-p
                     nshell.presentation::*kb* "grep")
                    :to-be-null)
            (expect (member "grep"
                            (nshell.presentation::%repl-command-corrections "grpe")
                            :test #'string=)
                    :to-be-truthy))
          (expect 0 :to-equal spawn-count)))))
  (it "batch diagnostics suggest known commands and preserve status 127 without spawning"
      (with-repl-test-state
       (nshell.presentation::seed-repl-completion-knowledge-base
        nshell.presentation::*kb*)
       (repl-test-set-env "PATH" "/__nshell_c04_empty_path__")
       (let ((spawn-count 0)
             (code nil)
             (printed nil))
         (setf printed
               (with-output-to-string (*standard-output*)
                 (let ((*error-output* *standard-output*))
                   (with-rebound-function
                    (nshell.infrastructure.acl::%spawn-posix-process
                     (lambda (&rest arguments)
                       (declare (ignore arguments))
                       (incf spawn-count)
                       (error "batch missing-command suggestions must not spawn processes")))
                    (setf code
                          (nshell.presentation::%run-batch-source-lines
                           (list "gti")))))))
         (expect 127 :to-equal code)
         (expect 127 :to-equal nshell.presentation::*last-exit-code*)
         (expect (search "nshell: gti: command not found" printed) :to-be-truthy)
         (expect (search "nshell: did you mean: git" printed) :to-be-truthy)
         (expect 0 :to-equal spawn-count)))))

