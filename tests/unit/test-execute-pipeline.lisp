(in-package #:nshell/test)

(def-suite execute-pipeline-service-tests
  :description "Application execute-pipeline service tests"
  :in nshell-tests)

(in-suite execute-pipeline-service-tests)

(defmacro with-os-environment-variable ((name value) &body body)
  `(let* ((var ,name)
          (old (uiop:getenv var))
          (had-old old))
     (unwind-protect
          (progn
            (sb-posix:setenv var ,value 1)
            ,@body)
        (if had-old
            (sb-posix:setenv var old 1)
            (sb-posix:unsetenv var)))))

(defun %execute-pipeline-sbcl-command-node (form &optional extra-args)
  (nshell.domain.parsing:make-command-node
   (current-sbcl-executable)
   (append (list "--noinform"
                 "--non-interactive"
                 "--disable-debugger"
                 "--eval"
                 (cons form :single))
           extra-args)))

(test execute-command-line-adds-complete-commands-to-history
  "A complete command line returns an AST/result pair and records history."
  (let ((history (nshell.domain.history:make-command-history))
        (dispatcher (nshell.application:make-event-dispatcher)))
    (multiple-value-bind (ast result)
        (nshell.application:execute-command-line "echo hello" history dispatcher)
      (is (nshell.domain.parsing:parse-complete-p result))
      (is (nshell.domain.parsing:command-node-p ast))
      (is (= 1 (nshell.domain.history:history-size history)))
      (is (string= "echo hello"
                   (nshell.domain.history:entry-text
                    (first (nshell.domain.history:history-all history))))))))

(test execute-command-line-does-not-record-incomplete-input
  "Incomplete input returns no AST/result values and leaves history unchanged."
  (let ((history (nshell.domain.history:make-command-history)))
    (multiple-value-bind (ast result)
        (nshell.application:execute-command-line "echo 'unterminated" history nil)
      (is (null ast))
      (is (null result))
      (is (= 0 (nshell.domain.history:history-size history))))))

(test execute-pipeline-use-case-runs-command-and-publishes-events
  "The execute-pipeline use case returns the exit status and emits lifecycle events."
  (let ((dispatcher (nshell.application:make-event-dispatcher))
        (ast (nshell.domain.parsing:make-command-node "true" nil)))
    (with-event-capture (events dispatcher
                                 :pipeline-started
                                 :process-created
                                 :process-exited
                                 :pipeline-completed)
        (nshell.domain.events:domain-event-type event)
      (is (= 0 (nshell.application:execute-pipeline-use-case ast dispatcher)))
      (is (null (nshell.application:drain-events dispatcher)))
      (let ((delivered (nreverse events)))
        (is (member :pipeline-started delivered))
        (is (member :pipeline-completed delivered))))))

(test execute-pipeline-use-case-expands-command-position-word
  "The public pipeline API expands variables in command position before spawning."
  (with-os-environment-variable ("NSHELL_PIPELINE_CMD" "printf")
    (let* ((ast (nshell.domain.parsing:make-command-node
                 "$NSHELL_PIPELINE_CMD"
                 (list "%s" "pipeline-api")))
           (code nil)
           (output (with-output-to-string (*standard-output*)
                     (setf code
                           (nshell.application:execute-pipeline-use-case ast nil)))))
      (is (= 0 code))
      (is (string= (format nil "pipeline-api~%") output)))))

(test execute-pipeline-use-case-rejects-multi-field-command-position-expansion
  "The public pipeline API rejects ambiguous expanded command names."
  (with-os-environment-variable ("NSHELL_PIPELINE_CMD" "printf echo")
    (let ((ast (nshell.domain.parsing:make-command-node
                "$NSHELL_PIPELINE_CMD"
                (list "%s" "pipeline-api")))
          (code nil))
      (let ((error-output
              (with-output-to-string (*error-output*)
                (setf code (nshell.application:execute-pipeline-use-case ast nil)))))
        (is (= 127 code))
        (is (string= (format nil "nshell: $NSHELL_PIPELINE_CMD: command name expansion produced 2 fields~%")
                     error-output))))))

(test execute-pipeline-use-case-applies-stage-redirections
  "Pipeline execution through the application API preserves per-stage redirects."
  (let* ((root (merge-pathnames (format nil "nshell-app-pipeline-redir-~d/"
                                         (random 1000000))
                                (uiop:temporary-directory)))
         (output (merge-pathnames "output.txt" root))
         (content "application pipeline redirection")
         (ast (nshell.domain.parsing:make-pipeline-node
               (list
                (nshell.domain.parsing:make-command-node "printf" (list content))
                (nshell.domain.parsing:make-command-node
                 "cat"
                 (list ">" (namestring output)))))))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (is (= 0 (nshell.application:execute-pipeline-use-case ast nil)))
           (is (probe-file output))
           (with-open-file (stream output :direction :input)
             (let ((actual (make-string (file-length stream))))
               (read-sequence actual stream)
               (is (string= content actual)))))
        (handler-case
          (when (probe-file root)
            (uiop:delete-directory-tree root :validate t))
        (error ())))))

(test execute-pipeline-use-case-pipes-stdout-only-by-default
  "Application-level pipelines should not feed stderr into the next stage by default."
  (let* ((writer (%execute-pipeline-sbcl-command-node
                  "(progn (write-string \"OUT\") (write-string \"ERR\" *error-output*))"))
         (counter (%execute-pipeline-sbcl-command-node
                    "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
         (ast (nshell.domain.parsing:make-pipeline-node (list writer counter)))
         (code nil)
         (output (capture-standard-output
                   (setf code (nshell.application:execute-pipeline-use-case ast nil)))))
    (is (= 0 code))
    (is (string= (format nil "3~%") output))))

(test execute-pipeline-use-case-pipes-stderr-when-explicitly-merged
  "Application-level pipelines should honor explicit 2>&1 stage redirects."
  (let* ((writer (%execute-pipeline-sbcl-command-node
                  "(progn (write-string \"OUT\") (write-string \"ERR\" *error-output*))"
                  (list "2>&1")))
         (counter (%execute-pipeline-sbcl-command-node
                    "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
         (ast (nshell.domain.parsing:make-pipeline-node (list writer counter)))
         (code nil)
         (output (capture-standard-output
                   (setf code (nshell.application:execute-pipeline-use-case ast nil)))))
    (is (= 0 code))
    (is (string= (format nil "6~%") output))))

(test execute-pipeline-use-case-preserves-redirect-order-dup-before-file
  "Application pipeline execution preserves 2>&1 before stdout redirect."
  (with-temporary-output-file (target :prefix "nshell-app-pipeline-dup-before-out")
    (let* ((writer (%execute-pipeline-sbcl-command-node
                    "(progn (write-string \"OUT\") (write-string \"ERR\" *error-output*))"
                    (list "2>&1" ">" target)))
           (counter (%execute-pipeline-sbcl-command-node
                     "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
           (ast (nshell.domain.parsing:make-pipeline-node (list writer counter)))
           (code nil)
           (output (capture-standard-output
                     (setf code (nshell.application:execute-pipeline-use-case ast nil)))))
      (is (= 0 code))
      (is (string= (format nil "3~%") output))
      (is (string= "OUT" (uiop:read-file-string target))))))

(test execute-pipeline-use-case-preserves-redirect-order-file-before-dup
  "Application pipeline execution preserves stdout redirect before 2>&1."
  (with-temporary-output-file (target :prefix "nshell-app-pipeline-out-before-dup")
    (let* ((writer (%execute-pipeline-sbcl-command-node
                    "(progn (write-string \"OUT\") (write-string \"ERR\" *error-output*))"
                    (list ">" target "2>&1")))
           (counter (%execute-pipeline-sbcl-command-node
                     "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
           (ast (nshell.domain.parsing:make-pipeline-node (list writer counter)))
           (code nil)
           (output (capture-standard-output
                     (setf code (nshell.application:execute-pipeline-use-case ast nil)))))
      (is (= 0 code))
      (is (string= (format nil "0~%") output))
      (is (string= "OUTERR" (uiop:read-file-string target))))))

(test execute-command-redirect-extraction-preserves-dangling-operator
  "A trailing redirect operator should remain part of the command arguments."
  (multiple-value-bind (clean redirects)
      (nshell.application::%extract-command-redirects
       (nshell.domain.parsing:make-command-node "echo" (list "hello" ">")))
      (is (equal '("hello" ">")
                 (nshell.domain.parsing:command-node-args clean)))
      (is (null redirects))))

(test execute-command-redirect-extraction-preserves-left-to-right-order
  "Redirect extraction preserves shell-significant left-to-right order."
  (multiple-value-bind (clean redirects)
      (nshell.application::%extract-command-redirects
       (nshell.domain.parsing:make-command-node
        "cmd"
        (list "arg" "2>&1" ">" "out" "2>" "err")))
    (is (equal '("arg")
               (nshell.domain.parsing:command-node-args clean)))
    (is (equal '((:2>&1 . nil) (:> . "out") (:2> . "err"))
               redirects))))

(test execute-pipeline-use-case-returns-127-for-missing-command
  "A pipeline with an unresolvable command reports a non-zero spawn failure."
  (let ((ast (nshell.domain.parsing:make-command-node
              "definitely-not-a-real-command"
              nil)))
    (is (= 127 (nshell.application:execute-pipeline-use-case ast nil)))))
