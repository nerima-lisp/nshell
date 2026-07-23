(in-package #:nshell/test)

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
                 (nshell.domain.parsing:make-command-arg form :single))
           extra-args)))

(describe "execute-pipeline-service-tests"
  (it "execute-command-line-adds-complete-commands-to-history"
    "A complete command line returns an AST/result pair and records history."
    (let ((history (nshell.domain.history:make-command-history))
          (dispatcher (nshell.application:make-event-dispatcher)))
      (multiple-value-bind (ast result)
          (nshell.application:execute-command-line "echo hello" history dispatcher)
        (expect (nshell.domain.parsing:parse-complete-p result) :to-be-truthy)
        (expect (nshell.domain.parsing:command-node-p ast) :to-be-truthy)
        (expect 1 :to-equal (nshell.domain.history:history-size history))
        (expect "echo hello" :to-equal (nshell.domain.history:entry-text
                      (first (nshell.domain.history:history-all history)))))))

  (it "execute-command-line-does-not-record-incomplete-input"
    "Incomplete input returns no AST/result values and leaves history unchanged."
    (let ((history (nshell.domain.history:make-command-history)))
      (multiple-value-bind (ast result)
          (nshell.application:execute-command-line "echo 'unterminated" history nil)
        (expect ast :to-be-null)
        (expect result :to-be-null)
        (expect 0 :to-equal (nshell.domain.history:history-size history)))))

  (it "execute-pipeline-use-case-runs-command-and-publishes-events"
    "The execute-pipeline use case returns the exit status and emits lifecycle events."
    (let ((dispatcher (nshell.application:make-event-dispatcher))
          (ast (nshell.domain.parsing:make-command-node "true" nil)))
      (with-event-capture (events dispatcher
                                   :pipeline-started
                                   :process-created
                                   :process-exited
                                   :pipeline-completed)
          (nshell.domain.events:domain-event-type event)
        (expect 0 :to-equal (nshell.application:execute-pipeline-use-case ast dispatcher))
        (expect (nshell.application:drain-events dispatcher) :to-be-null)
        (let ((delivered (nreverse events)))
          (expect (member :pipeline-started delivered) :to-be-truthy)
          (expect (member :pipeline-completed delivered) :to-be-truthy)))))

  (it "execute-pipeline-use-case-expands-command-position-word"
    "The public pipeline API expands variables in command position before spawning."
    (with-os-environment-variable ("NSHELL_PIPELINE_CMD" "printf")
        (let* ((ast (nshell.domain.parsing:make-command-node
                   "$NSHELL_PIPELINE_CMD"
                   (list "%s" "pipeline-api")))
             (code nil)
             (output (with-output-to-string (*standard-output*)
                       (setf code
                             (nshell.application:execute-pipeline-use-case ast nil)))))
        (expect 0 :to-equal code)
        (expect "pipeline-api" :to-equal output))))

  (it "execute-pipeline-use-case-rejects-multi-field-command-position-expansion"
    "The public pipeline API rejects ambiguous expanded command names."
    (with-os-environment-variable ("NSHELL_PIPELINE_CMD" "printf echo")
      (let ((ast (nshell.domain.parsing:make-command-node
                  "$NSHELL_PIPELINE_CMD"
                  (list "%s" "pipeline-api")))
            (code nil))
        (let ((error-output
                (with-output-to-string (*error-output*)
                  (setf code (nshell.application:execute-pipeline-use-case ast nil)))))
          (expect 127 :to-equal code)
          (expect (format nil "nshell: $NSHELL_PIPELINE_CMD: command name expansion produced 2 fields~%") :to-equal error-output)))))

  (it "execute-pipeline-use-case-rejects-required-parameter-expansion-errors"
    "Required parameter expansion errors are reported without reaching process spawn."
    (let ((ast (nshell.domain.parsing:make-command-node
                "printf"
                (list "%s" "${NSHELL_MISSING_REQUIRED:?required value}")))
          (code nil))
      (let ((error-output
              (with-output-to-string (*error-output*)
                (setf code (nshell.application:execute-pipeline-use-case ast nil)))))
        (expect 127 :to-equal code)
        (expect (format nil "nshell: NSHELL_MISSING_REQUIRED: required value~%") :to-equal error-output))))

  (it "execute-pipeline-use-case-applies-stage-redirections"
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
             (expect 0 :to-equal (nshell.application:execute-pipeline-use-case ast nil))
             (expect (probe-file output) :to-be-truthy)
             (with-open-file (stream output :direction :input)
               (let ((actual (make-string (file-length stream))))
                 (read-sequence actual stream)
                 (expect content :to-equal actual))))
          (handler-case
            (when (probe-file root)
              (uiop:delete-directory-tree root :validate t))
          (error ())))))

  (it "execute-pipeline-use-case-pipes-stdout-only-by-default"
    "Application-level pipelines should not feed stderr into the next stage by default."
    (let* ((writer (%execute-pipeline-sbcl-command-node
                    "(progn (write-string \"OUT\") (write-string \"ERR\" *error-output*))"))
           (counter (%execute-pipeline-sbcl-command-node
                      "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
           (ast (nshell.domain.parsing:make-pipeline-node (list writer counter)))
           (code nil)
           (output (capture-standard-output
                     (setf code (nshell.application:execute-pipeline-use-case ast nil)))))
      (expect 0 :to-equal code)
      (expect (format nil "3~%") :to-equal output)))

  (it "execute-pipeline-use-case-pipes-stderr-when-explicitly-merged"
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
      (expect 0 :to-equal code)
      (expect (format nil "6~%") :to-equal output)))

  (it "execute-pipeline-use-case-preserves-redirect-order-dup-before-file"
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
        (expect 0 :to-equal code)
        (expect (format nil "3~%") :to-equal output)
        (expect "OUT" :to-equal (uiop:read-file-string target)))))

  (it "execute-pipeline-use-case-preserves-redirect-order-file-before-dup"
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
        (expect 0 :to-equal code)
        (expect (format nil "0~%") :to-equal output)
        (expect "OUTERR" :to-equal (uiop:read-file-string target)))))

  (it "execute-pipeline-use-case-returns-127-for-missing-command"
    "A pipeline with an unresolvable command reports a non-zero spawn failure."
    (let ((ast (nshell.domain.parsing:make-command-node
                "definitely-not-a-real-command"
                nil)))
      (expect 127 :to-equal (nshell.application:execute-pipeline-use-case ast nil))))

  (it "execute-pipeline-node-in-context-times-out-external-stages-in-cps-mode"
    "The CPS execution path drains external output and times out long-running stages."
    (let* ((context (make-test-shell-context))
           (ast (nshell.domain.parsing:make-pipeline-node
                 (list (nshell.domain.parsing:make-command-node
                        "sh"
                        (list "-c" "printf ready; sleep 5")))))
           (stdout nil)
           (stderr nil)
           (code nil))
      (let ((nshell.infrastructure.acl:*external-command-timeout* 0.2))
        (setf stderr
              (with-output-to-string (*error-output*)
                (multiple-value-setq (stdout code)
                  (nshell.application::execute-pipeline-node-in-context
                   context
                   ast))))
        (expect 124 :to-equal code)
        (expect "ready" :to-equal stdout)
        (expect (search "timed out after" stderr) :to-be-truthy))))

  (it "trim-command-substitution-output-strips-trailing-newlines"
    "Trailing \\n and \\r characters are removed; nil input becomes empty string."
    (flet ((trim (s) (nshell.application::%trim-command-substitution-output s)))
      (expect "" :to-equal (trim nil))
      (expect "" :to-equal (trim ""))
      (expect "hello" :to-equal (trim "hello"))
      (expect "hello" :to-equal (trim (format nil "hello~%")))
      (expect "hello" :to-equal (trim (format nil "hello~%~%")))
      (expect "hello" :to-equal (trim (format nil "hello~C~%" #\Return)))
      (expect "" :to-equal (trim (format nil "~%~%")))
      (expect (format nil "a~%b") :to-equal (trim (format nil "a~%b~%")))))

  (it "command-substitution-fields-splits-on-newlines"
    "Output is split on internal newlines after trailing newlines are stripped."
    (flet ((fields (s) (nshell.application::%command-substitution-fields s)))
      (expect (fields nil) :to-be-null)
      (expect (fields "") :to-be-null)
      (expect (fields (format nil "~%~%")) :to-be-null)
      (expect '("hello") :to-equal (fields "hello"))
      (expect '("hello") :to-equal (fields (format nil "hello~%")))
      (expect '("hello" "world") :to-equal (fields (format nil "hello~%world")))
      (expect '("hello" "world") :to-equal (fields (format nil "hello~%world~%")))
      (expect '("" "world") :to-equal (fields (format nil "~%world")))))

  (it "command-substitution-fields-returns-nil-on-parse-error"
    "A command string with a parse error returns nil without executing."
    (let ((context (make-test-builtins-context)))
      (expect (nshell.application::%execute-command-substitution-fields
                 context "| echo parse-error-command") :to-be-null)))

  (it "command-substitution-fields-returns-nil-on-incomplete-input"
    "An incomplete command substitution string returns nil without executing."
    (let ((context (make-test-builtins-context)))
      (expect (nshell.application::%execute-command-substitution-fields
                 context "echo 'unterminated") :to-be-null)))

  (it "command-substitution-fields-returns-nil-on-timeout"
    "A blocking command substitution logs a timeout to stderr and returns nil."
    (let ((context (make-test-builtins-context))
          (result :sentinel)
          (error-text nil))
      (setf error-text
            (with-output-to-string (*error-output*)
              (let ((nshell.application::*command-substitution-timeout* 0.001))
                (with-temporary-function
                    ('nshell.application::execute-ast-in-context
                     (lambda (ctx ast)
                       (declare (ignore ctx ast))
                       (sleep 5)
                       (values "" 0)))
                  (setf result
                        (nshell.application::%execute-command-substitution-fields
                         context "echo hello"))))))
      (expect result :to-be-null)
      (expect (search "timed out" error-text) :to-be-truthy)))

  (it "paren-balanced-end-finds-matching-close-paren"
    "paren-balanced-end returns index past the balancing ) or nil when unbalanced."
    (flet ((bal (text start) (nshell.application::%paren-balanced-end text start)))
      (expect 2 :to-equal (bal "()" 0))
      (expect 7 :to-equal (bal "(a (b))" 0))
      (expect (bal "(unclosed" 0) :to-be-null)
      (expect 4 :to-equal (bal "x(a)y" 1))))

  (it "append-command-substitution-char-extends-each-part"
    "append-command-substitution-char appends the character to every part string."
    (flet ((app (parts ch)
             (nshell.application::%append-command-substitution-char parts ch)))
      (expect '("a") :to-equal (app '("") #\a))
      (expect '("xa" "ya") :to-equal (app '("x" "y") #\a))
      (expect '("$") :to-equal (app '("") #\$))))

  (it "append-command-substitution-string-extends-each-part"
    "append-command-substitution-string appends a string to every part."
    (flet ((app (parts s)
             (nshell.application::%append-command-substitution-string parts s)))
      (expect '("abc") :to-equal (app '("") "abc"))
      (expect '("xabc" "yabc") :to-equal (app '("x" "y") "abc"))))

  (it "append-command-substitution-fields-cross-products-parts-and-fields"
    "append-command-substitution-fields produces the full cross-product of parts x fields."
    (flet ((app (parts fields)
             (nshell.application::%append-command-substitution-fields parts fields)))
      (expect '("one" "two") :to-equal (app '("") '("one" "two")))
      (expect '("xone" "xtwo" "yone" "ytwo") :to-equal (app '("x" "y") '("one" "two")))
      ;; nil fields → same as ("") → each part unchanged
      (expect '("x" "y") :to-equal (app '("x" "y") nil)))))
