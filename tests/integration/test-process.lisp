(in-package #:nshell/test)

(defun %process-test-sbcl-command-node (form)
  (nshell.domain.parsing:make-command-node
   (current-sbcl-executable)
   (%process-test-sbcl-argv form)))

(defun %process-test-sbcl-argv (form)
  (list "--noinform"
        "--non-interactive"
        "--disable-debugger"
        "--eval"
        form))

(describe "process-tests"
  (it "run-external-echo"
    "External echo command executes and returns exit 0"
    (let ((exit (nshell.infrastructure.acl:run-external "echo" '("hello"))))
      (expect 0 :to-equal exit)))

  (it "run-external-large-output-streams-before-wait"
    "Synchronous execution drains stdout before waiting for process exit."
    (let* ((size 131072)
           (form (format nil
                         "(write-string (make-string ~d :initial-element #\\x))"
                         size))
           (exit nil)
           (output
             (capture-standard-output
               (setf exit
                     (nshell.infrastructure.acl:run-external
                      (current-sbcl-executable)
                      (%process-test-sbcl-argv form))))))
      (expect 0 :to-equal exit)
      (expect size :to-equal (length output))
      (let ((bad-index (position-if-not (lambda (char) (char= #\x char)) output)))
        (expect bad-index :to-be-null)
        (when bad-index
          (fail "unexpected character at ~d: ~s" bad-index (char output bad-index))))))

  (it "run-external-capture-echo"
    "External command capture returns stdout and exit code."
    (multiple-value-bind (output exit)
        (nshell.infrastructure.acl:run-external-capture "echo" '("hello"))
      (expect 0 :to-equal exit)
      (expect (format nil "hello~%") :to-equal output)))

  (it "run-external-times-out-and-returns"
    "Synchronous execution should time out while reading output or waiting."
    (let* ((nshell.infrastructure.acl:*external-command-timeout* 0.2)
           (exit nil)
           (error-output
             (with-output-to-string (*error-output*)
               (setf exit
                     (nshell.infrastructure.acl:run-external
                      (current-sbcl-executable)
                      (list "--noinform"
                            "--non-interactive"
                            "--disable-debugger"
                            "--eval"
                            "(sleep 5)"))))))
      (expect 124 :to-equal exit)
      (expect (search "timed out after" error-output) :to-be-truthy)))

  (it "run-external-capture-times-out-and-returns"
    "Captured synchronous execution should return a timeout message and exit 124."
    (let ((nshell.infrastructure.acl:*external-command-timeout* 0.2))
      (multiple-value-bind (output exit)
          (nshell.infrastructure.acl:run-external-capture
           (current-sbcl-executable)
           (%process-test-sbcl-argv "(sleep 5)"))
        (expect 124 :to-equal exit)
        (expect (search "timed out after" output) :to-be-truthy))))

  (it "run-external-capture-signal-exit-status"
    "External command capture normalizes signaled processes to 128+signal."
    (multiple-value-bind (output exit)
        (nshell.infrastructure.acl:run-external-capture
         "sh"
         '("-c" "kill -TERM $$"))
      (expect 143 :to-equal exit)
      (expect "" :to-equal output)))

  (it "run-external-nonexistent"
    "Nonexistent command returns error exit code"
    (let ((exit (nshell.infrastructure.acl:run-external "nonexistent_cmd_xyz" '())))
      (expect (= 0 exit) :to-be-falsy)))

  (it "run-external-capture-nonexistent"
    "Nonexistent command capture returns an error exit code and message."
    (multiple-value-bind (output exit)
        (nshell.infrastructure.acl:run-external-capture "nonexistent_cmd_xyz" '())
      (expect (= 0 exit) :to-be-falsy)
      (expect (search "nonexistent_cmd_xyz" output) :to-be-truthy)))

  (it "spawn-async-inherits-output-when-unredirected"
    "Unredirected background processes should not leave an unread output pipe."
    (let ((proc (nshell.infrastructure.acl:spawn-async
                 "true"
                 nil)))
      (expect (null proc) :to-be-falsy)
      (when proc
        (unwind-protect
             (progn
               (sb-ext:process-wait proc)
               (expect (sb-ext:process-output proc) :to-be-null)
               (expect 0 :to-equal (sb-ext:process-exit-code proc)))
          (when (sb-ext:process-alive-p proc)
            (ignore-errors
              (sb-ext:process-kill proc 15)))))))

  (it "spawn-pipeline-pipes-stdout-only-by-default"
    "Pipeline stages pipe stdout only unless stderr is explicitly merged."
    (let* ((writer (%process-test-sbcl-command-node
                    "(progn (write-string \"OUT\") (write-string \"ERR\" *error-output*))"))
           (counter (%process-test-sbcl-command-node
                     "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
           (exit nil)
           (output (capture-standard-output
                     (setf exit
                           (nshell.infrastructure.acl:spawn-pipeline
                            (list writer counter))))))
      (expect 0 :to-equal exit)
      (expect (format nil "3~%") :to-equal output)))

  (it "spawn-pipeline-pipes-stderr-when-explicitly-merged"
    "An explicit 2>&1 redirect merges stderr into the downstream pipeline input."
    (let* ((writer (%process-test-sbcl-command-node
                    "(progn (write-string \"OUT\") (write-string \"ERR\" *error-output*))"))
           (counter (%process-test-sbcl-command-node
                     "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
           (exit nil)
           (output (capture-standard-output
                     (setf exit
                            (nshell.infrastructure.acl:spawn-pipeline
                            (list writer counter)
                            :redirects (list (list (cons :2>&1 nil)) nil))))))
      (expect 0 :to-equal exit)
      (expect (format nil "6~%") :to-equal output)))

  (it "spawn-pipeline-times-out-and-returns"
    "Synchronous pipelines should time out and terminate started processes."
    (let* ((nshell.infrastructure.acl:*external-command-timeout* 0.2)
           (sleeper (%process-test-sbcl-command-node "(sleep 5)"))
           (exit nil)
           (error-output
             (with-output-to-string (*error-output*)
               (setf exit
                     (nshell.infrastructure.acl:spawn-pipeline
                      (list sleeper))))))
      (expect 124 :to-equal exit)
      (expect (search "pipeline timed out" error-output) :to-be-truthy)))

  (it "spawn-pipeline-redirect-dup-before-stdout-redirect-keeps-stderr-on-pipe"
    "2>&1 before a stdout redirect keeps stderr connected to the original pipeline stdout."
    (with-temporary-output-file (target :prefix "nshell-pipeline-dup-before-out")
      (let* ((writer (%process-test-sbcl-command-node
                      "(progn (write-string \"OUT\") (write-string \"ERR\" *error-output*))"))
             (counter (%process-test-sbcl-command-node
                       "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
             (exit nil)
             (output (capture-standard-output
                       (setf exit
                             (nshell.infrastructure.acl:spawn-pipeline
                              (list writer counter)
                              :redirects (list (list (cons :2>&1 nil)
                                                     (cons :> target))
                                               nil))))))
        (expect 0 :to-equal exit)
        (expect (format nil "3~%") :to-equal output)
        (expect "OUT" :to-equal (uiop:read-file-string target)))))

  (it "spawn-pipeline-stdout-redirect-before-dup-merges-stderr-into-file"
    "A stdout redirect before 2>&1 merges stderr into the redirected stdout file."
    (with-temporary-output-file (target :prefix "nshell-pipeline-out-before-dup")
      (let* ((writer (%process-test-sbcl-command-node
                      "(progn (write-string \"OUT\") (write-string \"ERR\" *error-output*))"))
             (counter (%process-test-sbcl-command-node
                       "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
             (exit nil)
             (output (capture-standard-output
                       (setf exit
                             (nshell.infrastructure.acl:spawn-pipeline
                              (list writer counter)
                              :redirects (list (list (cons :> target)
                                                     (cons :2>&1 nil))
                                               nil))))))
        (expect 0 :to-equal exit)
        (expect (format nil "0~%") :to-equal output)
        (expect "OUTERR" :to-equal (uiop:read-file-string target)))))

  (it "spawn-pipeline-cleans-up-started-processes-after-spawn-failure"
    "A later stage spawn failure should not block on output from already-started stages."
    (let* ((sleeper (%process-test-sbcl-command-node "(sleep 30)"))
           (missing (nshell.domain.parsing:make-command-node
                     "definitely-not-a-real-command-nshell-pipeline"
                     nil))
           (start (get-internal-real-time))
           (exit (nshell.infrastructure.acl:spawn-pipeline
                  (list sleeper missing)))
           (elapsed (/ (- (get-internal-real-time) start)
                        internal-time-units-per-second)))
      (expect 127 :to-equal exit)
      (expect elapsed :to-be-less-than 2.0)))

  (it "spawn-pipeline-async-cleans-up-started-processes-after-spawn-failure"
    "A later async stage spawn failure should terminate already-started stages."
    (let* ((sleeper (%process-test-sbcl-command-node "(sleep 30)"))
           (missing (nshell.domain.parsing:make-command-node
                     "definitely-not-a-real-command-nshell-pipeline"
                     nil))
           (start (get-internal-real-time))
           (procs (nshell.infrastructure.acl:spawn-pipeline-async
                   (list sleeper missing)))
           (elapsed (/ (- (get-internal-real-time) start)
                       internal-time-units-per-second)))
      (expect procs :to-be-null)
      (expect elapsed :to-be-less-than 2.0))))
