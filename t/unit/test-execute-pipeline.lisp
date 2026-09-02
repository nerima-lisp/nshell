(in-package #:nshell/test)

(describe "execute-pipeline-service-tests"
  (it "execute-command-line-adds-complete-commands-to-history"
    "A complete command line returns an AST/result pair and records history."
    (let ((history (history-kit:make-history)))
      (multiple-value-bind (ast result)
          (nshell.application:execute-command-line "echo hello" history)
        (expect (nshell.domain.parsing:parse-complete-p result) :to-be-truthy)
        (expect (nshell.domain.parsing:command-node-p ast) :to-be-truthy)
        (expect 1 :to-equal (history-kit:history-count history))
        (expect "echo hello" :to-equal (history-kit:history-entry-text
                      (first (history-kit:history-entries history)))))))

  (it "execute-command-line-does-not-record-incomplete-input"
    "Incomplete input returns no AST/result values and leaves history unchanged."
    (let ((history (history-kit:make-history)))
      (multiple-value-bind (ast result)
          (nshell.application:execute-command-line "echo 'unterminated" history)
        (expect ast :to-be-null)
        (expect result :to-be-null)
        (expect 0 :to-equal (history-kit:history-count history)))))

  (it "execute-pipeline-use-case-runs-command"
    "The execute-pipeline use case returns the exit status of the command it ran."
    (let ((ast (nshell.domain.parsing:make-command-node "true" nil)))
      (expect 0 :to-equal (nshell.application:execute-pipeline-use-case ast))))

  (it "execute-pipeline-use-case-expands-command-position-word"
    "The public pipeline API expands variables in command position before spawning."
    (with-os-environment-variable ("NSHELL_PIPELINE_CMD" "printf")
        (let* ((ast (nshell.domain.parsing:make-command-node
                   "$NSHELL_PIPELINE_CMD"
                   (list "%s" "pipeline-api")))
             (code nil)
             (output (with-output-to-string (*standard-output*)
                       (setf code
                             (nshell.application:execute-pipeline-use-case ast)))))
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
                  (setf code (nshell.application:execute-pipeline-use-case ast)))))
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
                (setf code (nshell.application:execute-pipeline-use-case ast)))))
          (expect 127 :to-equal code)
          (expect (format nil "nshell: NSHELL_MISSING_REQUIRED: required value~%") :to-equal error-output))))

  (it "execute-command-node-in-context-reports-internal-fd-redirect-errors"
    "Unsupported builtin fd redirects become a shell status instead of escaping the context boundary."
    (let ((context (make-test-builtins-context))
          (code nil)
          (output nil)
          (error-output nil))
      (setf error-output
            (with-output-to-string (*error-output*)
              (setf output
                    (with-output-to-string (*standard-output*)
                      (setf code
                            (nth-value
                             1
                             (nshell.application::execute-command-node-in-context
                              context
                              (nshell.domain.parsing:make-command-node
                               "echo"
                               '("builtin" "3>&1")))))))))
      (expect 1 :to-equal code)
      (expect "" :to-equal output)
      (expect (search "Unsupported file-descriptor duplication 3>&1"
                      error-output)
              :to-be-truthy)))

  (it "execute-pipeline-use-case-applies-stage-redirections"
    "Pipeline execution through the application API preserves per-stage redirects."
    (let* ((root (merge-pathnames
                  (make-pathname :directory
                                 (list :relative
                                       (format nil "nshell-app-pipeline-redir-~d"
                                               (random 1000000))))
                                  (host-kit:temporary-directory)))
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
             (expect 0 :to-equal (nshell.application:execute-pipeline-use-case ast))
             (expect (probe-file output) :to-be-truthy)
             (with-open-file (stream output)
               (let ((actual (make-string (file-length stream))))
                 (read-sequence actual stream)
                 (expect content :to-equal actual))))
          (handler-case
            (when (probe-file root)
              (host-kit:delete-directory-tree root :validate t))
          (error ())))))

  (it "execute-pipeline-use-case-preserves-arbitrary-fd-dup-order"
    "The application boundary retains fd 3 on the original stdout before a later file redirect."
    (with-temporary-output-file (target :prefix "nshell-app-pipeline-arbitrary-fd-dup")
      (let* ((ast
               (nshell.domain.parsing:make-command-node
                "sh"
                (list "-c" "printf out; printf fd3 >&3" "3>&1" ">" target)))
             (code nil)
             (output (capture-standard-output
                       (setf code
                             (nshell.application:execute-pipeline-use-case ast)))))
        (expect 0 :to-equal code)
        (expect "fd3" :to-equal output)
        (expect "out" :to-equal (host-kit:read-file-string target)))))

  (it "pipeline-stage-streams-opens-file-and-here-string-inputs"
    "Pipeline stage setup materializes file and here-string input redirects."
    (host-kit:with-temporary-directory (directory)
      (let ((input-path (merge-pathnames "pipeline-input.txt" directory)))
        (host-kit:write-file-string "file input" input-path)
        (dolist (case (list (list (cons :< (namestring input-path))
                                  "file input")
                            (list (cons :<<< "here input")
                                  "here input")))
          (let ((redirects (list (first case)))
                (expected (second case)))
            (multiple-value-bind (input output error-output input-pipe
                                  output-pipe redirect-streams)
                (nshell.infrastructure.acl::%pipeline-stage-streams
                 redirects nil nil nil)
              (unwind-protect
                   (progn
                     (expect expected :to-equal (read-line input))
                     (expect :stream :to-equal output)
                     (expect (eq *error-output* error-output) :to-be-truthy)
                     (expect input-pipe :to-be-null)
                     (expect output-pipe :to-be-null)
                     (expect 1 :to-equal (length redirect-streams)))
                (nshell.infrastructure.acl::%close-new-redirect-streams
                 redirect-streams nil))))))))

  (it "pipeline-output-streams-materializes-error-and-merged-redirects"
    "Pipeline output setup keeps stderr-only and combined redirects distinct."
    (host-kit:with-temporary-directory (directory)
      (let ((error-path (merge-pathnames "pipeline-error.txt" directory))
            (merged-path (merge-pathnames "pipeline-merged.txt" directory)))
        (multiple-value-bind (output error-output output-pipe redirect-streams)
            (nshell.infrastructure.acl::%pipeline-output-streams
             (list (cons :2> (namestring error-path))) nil nil
             :default-output :fallback)
          (unwind-protect
               (progn
                 (expect :fallback :to-equal output)
                 (expect (streamp error-output) :to-be-truthy)
                 (write-string "error only" error-output)
                 (finish-output error-output)
                 (expect output-pipe :to-be-null)
                 (expect 1 :to-equal (length redirect-streams)))
            (nshell.infrastructure.acl::%close-new-redirect-streams
             redirect-streams nil)))
        (expect "error only" :to-equal (host-kit:read-file-string error-path))
        (multiple-value-bind (output error-output output-pipe redirect-streams)
            (nshell.infrastructure.acl::%pipeline-output-streams
             (list (cons :&> (namestring merged-path))) nil nil
             :default-output :fallback)
          (unwind-protect
               (progn
                 (expect (streamp output) :to-be-truthy)
                 (expect (eq :output error-output) :to-be-truthy)
                 (write-string "merged" output)
                 (finish-output output)
                 (expect output-pipe :to-be-null)
                 (expect 1 :to-equal (length redirect-streams)))
            (nshell.infrastructure.acl::%close-new-redirect-streams
             redirect-streams nil)))
        (expect "merged" :to-equal (host-kit:read-file-string merged-path)))))

  (it "redirect-output-to-error-releases-output-and-aliases-error"
    "Output-to-error redirection closes its owned stream and preserves stderr output."
    (host-kit:with-temporary-directory (directory)
      (let ((output-path (merge-pathnames "output-to-error.txt" directory))
            (original-output (make-string-output-stream))
            (original-error (make-string-output-stream)))
        (let ((*standard-output* original-output)
              (*error-output* original-error))
          (unwind-protect
               (progn
                 (nshell.infrastructure.acl:redirect-output
                  (namestring output-path) :supersede)
                 (let ((owned-output *standard-output*))
                   (nshell.infrastructure.acl:redirect-output-to-error)
                   (expect (eq *standard-output* *error-output*) :to-be-truthy)
                   (expect (not (open-stream-p owned-output)) :to-be-truthy)
                   (write-string "merged" *standard-output*)
                   (finish-output *standard-output*))
                 (nshell.infrastructure.acl:restore-redirects)
                 (expect (eq original-output *standard-output*) :to-be-truthy)
                 (expect (eq original-error *error-output*) :to-be-truthy)
                 (expect "merged" :to-equal
                         (get-output-stream-string original-error)))
            (nshell.infrastructure.acl:restore-redirects))))))

  (it "execute-pipeline-use-case-pipes-stdout-only-by-default"
    "Application-level pipelines should not feed stderr into the next stage by default."
    (let* ((writer (%execute-pipeline-sbcl-command-node
                    "(progn (write-string \"OUT\") (finish-output) (write-string \"ERR\" *error-output*) (finish-output *error-output*))"))
           (counter (%execute-pipeline-sbcl-command-node
                      "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
           (ast (nshell.domain.parsing:make-pipeline-node (list writer counter)))
           (code nil)
           (output (capture-standard-output
                     (setf code (nshell.application:execute-pipeline-use-case ast)))))
      (expect 0 :to-equal code)
      (expect (format nil "3~%") :to-equal output)))

  (it "execute-pipeline-use-case-pipes-stderr-when-explicitly-merged"
    "Application-level pipelines should honor explicit 2>&1 stage redirects."
    (let* ((writer (%execute-pipeline-sbcl-command-node
                    "(progn (write-string \"OUT\") (finish-output) (write-string \"ERR\" *error-output*) (finish-output *error-output*))"
                    (list "2>&1")))
           (counter (%execute-pipeline-sbcl-command-node
                      "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
           (ast (nshell.domain.parsing:make-pipeline-node (list writer counter)))
           (code nil)
           (output (capture-standard-output
                     (setf code (nshell.application:execute-pipeline-use-case ast)))))
      (expect 0 :to-equal code)
      (expect (format nil "6~%") :to-equal output)))

  (it "execute-pipeline-use-case-preserves-redirect-order-dup-before-file"
    "Application pipeline execution preserves 2>&1 before stdout redirect."
    (with-temporary-output-file (target :prefix "nshell-app-pipeline-dup-before-out")
      (let* ((writer (%execute-pipeline-sbcl-command-node
                      "(progn (write-string \"OUT\") (finish-output) (write-string \"ERR\" *error-output*) (finish-output *error-output*))"
                      (list "2>&1" ">" target)))
             (counter (%execute-pipeline-sbcl-command-node
                       "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
             (ast (nshell.domain.parsing:make-pipeline-node (list writer counter)))
             (code nil)
             (output (capture-standard-output
                       (setf code (nshell.application:execute-pipeline-use-case ast)))))
        (expect 0 :to-equal code)
        (expect (format nil "3~%") :to-equal output)
        (expect "OUT" :to-equal (host-kit:read-file-string target)))))

  (it "execute-pipeline-use-case-preserves-redirect-order-file-before-dup"
    "Application pipeline execution preserves stdout redirect before 2>&1."
    (with-temporary-output-file (target :prefix "nshell-app-pipeline-out-before-dup")
      (let* ((writer (%execute-pipeline-sbcl-command-node
                      "(progn (write-string \"OUT\") (finish-output) (write-string \"ERR\" *error-output*) (finish-output *error-output*))"
                      (list ">" target "2>&1")))
             (counter (%execute-pipeline-sbcl-command-node
                       "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
             (ast (nshell.domain.parsing:make-pipeline-node (list writer counter)))
             (code nil)
             (output (capture-standard-output
                       (setf code (nshell.application:execute-pipeline-use-case ast)))))
        (expect 0 :to-equal code)
        (expect (format nil "0~%") :to-equal output)
        (expect "OUTERR" :to-equal (host-kit:read-file-string target)))))

  (it "execute-pipeline-use-case-returns-127-for-missing-command"
    "A pipeline with an unresolvable command reports a non-zero spawn failure."
    (let ((ast (nshell.domain.parsing:make-command-node
                "definitely-not-a-real-command"
                nil)))
      (expect 127 :to-equal (nshell.application:execute-pipeline-use-case ast))))

  (it "external-command-timeout-defaults-to-nil"
    "The production default disables the foreground command timeout; a
directly-launched external command is bounded only when a caller (e.g. a
non-interactive redirect, or a test) explicitly binds the special. Before
this change the default was 30, which killed any interactive foreground
command -- like `sleep 30` typed at the prompt -- after 30 seconds
regardless of interactivity; see %FOREGROUND-EXTERNAL-COMMAND-TIMEOUT in
src/infrastructure/acl/syscall-process.lisp for the interactivity gate that
now decides whether this default is even consulted."
    (expect nil :to-equal nshell.infrastructure.acl:*external-command-timeout*))

  (it "external-redirect-plan-preserves-routing-data"
    "External process routing is an immutable data boundary with no copier."
    (let ((plan (nshell.application::%make-external-process-redirect-plan
                 "stdout.log" :append
                 "stderr.log" :supersede
                 :stdout :stderr t)))
      (expect (nshell.application::%external-process-redirect-plan-p plan)
              :to-be-truthy)
      (expect (fboundp
                'nshell.application::copy-%external-process-redirect-plan)
              :to-be-falsy)
      (expect "stdout.log" :to-equal
              (nshell.application::%external-process-redirect-plan-stdout-target
               plan))
      (expect :append :to-be
              (nshell.application::%external-process-redirect-plan-stdout-mode
               plan))
      (expect "stderr.log" :to-equal
              (nshell.application::%external-process-redirect-plan-stderr-target
               plan))
      (expect :supersede :to-be
              (nshell.application::%external-process-redirect-plan-stderr-mode
               plan))
      (expect :stdout :to-be
              (nshell.application::%external-process-redirect-plan-stdout-endpoint
               plan))
      (expect :stderr :to-be
              (nshell.application::%external-process-redirect-plan-stderr-endpoint
               plan))
      (expect (nshell.application::%external-process-redirect-plan-merge-stderr-p
               plan)
              :to-be-truthy)))

  (it "external-wrapper-redirect-plan-preserves-merged-stream-topology"
    "A shell wrapper captures both child streams while retaining their merge policy."
    (let* ((source-plan
             (nshell.application::%make-external-process-redirect-plan
              "stdout.log" :append "stderr.log" :supersede
              :stdout :stderr nil))
           (wrapper-plan
             (nshell.application::%external-process-wrapper-redirect-plan
              source-plan)))
      (expect nil :to-equal
              (nshell.application::%external-process-redirect-plan-stdout-target
               wrapper-plan))
      (expect :supersede :to-be
              (nshell.application::%external-process-redirect-plan-stdout-mode
               wrapper-plan))
      (expect :stdout :to-be
              (nshell.application::%external-process-redirect-plan-stdout-endpoint
               wrapper-plan))
      (expect :stderr :to-be
              (nshell.application::%external-process-redirect-plan-stderr-endpoint
               wrapper-plan))
      (expect (nshell.application::%external-process-redirect-plan-merge-stderr-p
               wrapper-plan)
              :to-be-falsy
              )))

  (it "external-process-input-stream-selects-each-input-source"
    "External stage input selection is data-driven across file, string, and stdin sources."
    (host-kit:with-temporary-directory (directory)
      (let ((input-path (merge-pathnames "external-input.txt" directory)))
        (host-kit:write-file-string "file input" input-path)
        (dolist (case (list (list (namestring input-path) nil "file input")
                            (list nil "string input" "string input")))
          (destructuring-bind (target input expected) case
            (multiple-value-bind (stream opened)
                (nshell.application::%external-process-input-stream target input)
              (unwind-protect
                   (expect expected :to-equal (read-line stream))
                (when opened
                  (close opened))))))
        (let ((*standard-input* (make-string-input-stream "standard input")))
          (multiple-value-bind (stream opened)
              (nshell.application::%external-process-input-stream nil nil)
            (expect (eq *standard-input* stream) :to-be-truthy)
            (expect opened :to-be-null))))))

  (it "continues-stopped-external-process-and-ignores-resume-errors"
    "A stopped synchronous process is resumed, while a failed resume signal does not escape."
    (let ((signals nil))
      (with-temporary-function
          ('nshell.infrastructure.acl:kill-process
           (lambda (pid signal)
             (push (list pid signal) signals)))
        (expect :continue-wait :to-equal
                (nshell.application::%continue-stopped-external-process 321)))
      (expect '((-321 :sigcont)) :to-equal signals))
    (with-temporary-function
        ('nshell.infrastructure.acl:kill-process
         (lambda (pid signal)
           (declare (ignore pid signal))
           (error "resume failed")))
      (expect :continue-wait :to-equal
              (nshell.application::%continue-stopped-external-process 321))))

  (it "command-substitution-timeout-defaults-to-nil"
    "Command substitution is unbounded by default, like every other shell.
Before this change the default was 30, silently capping any `$(...)` at 30
seconds in every mode; a caller that wants a bound binds the special (the
0.001-second binding test elsewhere in this file covers that branch). A
reverted default would still pass the e2e substitution smoke tests -- 30 is
a valid SB-EXT:WITH-TIMEOUT argument -- so only this direct assertion pins
it."
    (expect nil :to-equal nshell.application::*command-substitution-timeout*))

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
      ;; *STANDARD-OUTPUT* is bound to a string stream because the stage's
      ;; timeout now flows through %FOREGROUND-EXTERNAL-COMMAND-TIMEOUT, which
      ;; only applies the special when stdout is NOT interactive -- and SBCL
      ;; reports the harness's standard streams as interactive even under the
      ;; Nix sandbox (same trap documented on the run-external timeout tests).
      (let ((nshell.infrastructure.acl:*external-command-timeout* 0.2)
            (*standard-output* (make-string-output-stream)))
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
(describe "execute-pipeline-branch-tests"
  (it "continues-stopped-external-process-and-ignores-signal-errors"
    "A stopped process group receives SIGCONT while delivery failures remain best effort."
    (let ((calls nil))
      (with-temporary-function
          ((quote nshell.infrastructure.acl:kill-process)
           (lambda (pid signal)
             (push (list pid signal) calls)
             (error "signal delivery failure")))
        (expect :continue-wait :to-be
                (nshell.application::%continue-stopped-external-process 4321)))
      (expect '((-4321 :sigcont)) :to-equal calls)))
  (it "process-substitution-spec-and-direction-are-classified"
    (expect (nshell.application::%process-substitution-spec-p nil) :to-be-falsy)
    (expect (nshell.application::%process-substitution-spec-p "") :to-be-falsy)
    (expect (nshell.application::%process-substitution-spec-p "<(") :to-be-falsy)
    (expect (nshell.application::%process-substitution-spec-p "<(printf") :to-be-falsy)
    (expect (nshell.application::%process-substitution-spec-p "<(printf)") :to-be-truthy)
    (expect (nshell.application::%process-substitution-spec-p ">(printf)") :to-be-truthy)
    (expect (nshell.application::%process-substitution-spec-p "x(printf)") :to-be-falsy)
    (expect :input :to-be (nshell.application::%process-substitution-direction "<(printf)"))
    (expect :output :to-be (nshell.application::%process-substitution-direction ">(printf)")))
  (it "process-substitution-error-and-inner-commands-are-pure"
    (expect (format nil "nshell: process substitution: ~a~%" "failed") :to-equal (nshell.application::%process-substitution-error "failed"))
    (with-complete-ast (command "echo hi")
      (expect (list command)
              :to-equal
              (nshell.application::%process-substitution-inner-commands command)))
    (with-complete-ast (pipeline "echo hi | cat")
      (expect 2
              :to-equal
              (length (nshell.application::%process-substitution-inner-commands pipeline))))
    (expect (nshell.application::%process-substitution-inner-commands nil) :to-be-null))
  (it "process-substitution-resource-cleanup-is-best-effort"
    (let ((released nil))
      (with-temporary-functions
          (((quote nshell.infrastructure.acl:release-process-substitution-fd)
            (lambda (resource)
              (push resource released)
              (when (eq resource :bad)
                (error "release failure")))))
        (nshell.application::%release-process-substitution-resources
         (list :first :bad :last)))
      (expect (list :last :bad :first) :to-equal released)))
  (it "process-substitution-finish-and-abort-release-all-resources"
    (let ((waited nil)
          (released nil)
          (closed nil))
      (with-temporary-functions
          (((quote nshell.infrastructure.acl:wait-process-substitution)
            (lambda (resource)
              (push resource waited)
              (when (eq resource :bad)
                (error "wait failure"))))
           ((quote nshell.infrastructure.acl:release-process-substitution-fd)
            (lambda (resource)
              (push resource released)))
           ((quote nshell.infrastructure.acl:close-process-substitution)
            (lambda (resource)
              (push resource closed))))
        (nshell.application::%finish-process-substitution-resources (list :ok :bad))
        (nshell.application::%abort-process-substitution-resources (list :left :right)))
      (expect (list :bad :ok) :to-equal waited)
      (expect (list :bad :ok) :to-equal released)
      (expect (list :right :left) :to-equal closed)))
  (it "process-substitution-resource-fds-project-in-order"
    (with-temporary-function
        ((quote nshell.infrastructure.acl:process-substitution-resource-fd)
         (lambda (resource)
           (getf resource :fd)))
      (expect (list 3 4)
              :to-equal
              (nshell.application::%process-substitution-resource-fds
               (list (list :fd 3) (list :fd 4))))))
  (it "source-pipeline-exit-status-honors-pipefail"
    (expect 2 :to-equal (nshell.application::%source-pipeline-exit-status (list 0 2) nil))
    (expect 2 :to-equal (nshell.application::%source-pipeline-exit-status (list 0 2 0) t))
    (expect 0 :to-equal (nshell.application::%source-pipeline-exit-status (list 0 0) t))
    (expect 0 :to-equal (nshell.application::%source-pipeline-exit-status nil nil)))
  (it "records-pipeline-statuses-as-normalized-environment-values"
    (let ((context (make-test-builtins-context)))
      (expect (list 0) :to-equal
              (nshell.application::%record-pipeline-statuses context nil))
      (expect (list "0") :to-equal
              (nshell.domain.environment:env-get-values
               (nshell.application:shell-context-environment context)
               "pipestatus"))
      (expect (list 2 nil 7) :to-equal
              (nshell.application::%record-pipeline-statuses context (list 2 nil 7)))
      (expect (list "2" "0" "7") :to-equal
              (nshell.domain.environment:env-get-values
               (nshell.application:shell-context-environment context)
               "pipestatus")))))
(describe "process-substitution-execution-boundaries"
  (it "materialize-reports-incomplete-and-non-command-bodies"
    (let ((context (make-test-shell-context)))
      (multiple-value-bind (path resource error)
          (nshell.application::%materialize-process-substitution-in-context
           context
           "<(echo |)")
        (expect path :to-be-null)
        (expect resource :to-be-null)
        (expect error :to-equal (format nil "nshell: process substitution: ~a~%" "the command is incomplete")))
      (multiple-value-bind (path resource error)
          (nshell.application::%materialize-process-substitution-in-context
           context
           "<(/bin/printf hi; /bin/printf bye)")
        (expect path :to-be-null)
        (expect resource :to-be-null)
        (expect error :to-equal (format nil "nshell: process substitution: ~a~%" "the command must be a command or pipeline")))))
  (it "materialize-expands-and-spawns-a-process-substitution"
    (let ((context (make-test-shell-context))
          (spawn-call nil))
      (with-temporary-functions
          (((quote nshell.application::%expand-command-nodes-in-context)
            (lambda (ignored-context commands)
              (declare (ignore ignored-context))
              (values commands nil nil)))
           ((quote nshell.infrastructure.acl:process-substitution-resource-path)
            (lambda (resource)
              (declare (ignore resource))
              "/dev/fd/9"))
           ((quote nshell.infrastructure.acl:spawn-process-substitution)
            (lambda (direction commands &key redirects)
              (setf spawn-call (list direction commands redirects))
              (values :resource))))
        (multiple-value-bind (path resource error)
            (nshell.application::%materialize-process-substitution-in-context
             context
             "<(/bin/printf hi)")
          (expect path :to-equal "/dev/fd/9")
          (expect resource :to-equal :resource)
          (expect error :to-be-null)
          (expect (list (first spawn-call) (third spawn-call)) :to-equal (list :input (list nil)))
          (expect (nshell.domain.parsing:command-node-command (first (second spawn-call))) :to-equal "/bin/printf")))))
  (it "materialize-reports-expansion-and-spawn-failures"
    (let ((context (make-test-shell-context)))
      (with-temporary-function
          ((quote nshell.application::%expand-command-nodes-in-context)
           (lambda (ignored-context commands)
             (declare (ignore ignored-context commands))
             (values nil "expansion failed" nil)))
        (multiple-value-bind (path resource error)
            (nshell.application::%materialize-process-substitution-in-context
             context
             "<(/bin/printf hi)")
          (expect path :to-be-null)
          (expect resource :to-be-null)
          (expect error :to-equal "expansion failed")))
      (with-temporary-functions
          (((quote nshell.application::%expand-command-nodes-in-context)
            (lambda (ignored-context commands)
              (declare (ignore ignored-context))
              (values commands nil nil)))
           ((quote nshell.infrastructure.acl:spawn-process-substitution)
            (lambda (direction commands &key redirects)
              (declare (ignore direction commands redirects))
              (error "spawn failed"))))
        (multiple-value-bind (path resource error)
            (nshell.application::%materialize-process-substitution-in-context
             context
             "<(/bin/printf hi)")
          (expect path :to-be-null)
          (expect resource :to-be-null)
          (expect (search "spawn failed" error) :to-be-truthy)))))
  (it "materialize-rejects-nested-and-internal-substitutions"
    (let ((context (make-test-shell-context))
          (aborted nil))
      (with-temporary-functions
          (((quote nshell.application::%expand-command-nodes-in-context)
            (lambda (ignored-context commands)
              (declare (ignore ignored-context))
              (values commands nil (list :nested))))
           ((quote nshell.application::%abort-process-substitution-resources)
            (lambda (resources)
              (setf aborted resources))))
        (multiple-value-bind (path resource error)
            (nshell.application::%materialize-process-substitution-in-context
             context
             "<(/bin/printf hi)")
          (expect path :to-be-null)
          (expect resource :to-be-null)
          (expect error :to-equal (format nil "nshell: process substitution: ~a~%" "nested process substitutions are not supported"))
          (expect aborted :to-equal (list :nested)))))
    (let ((context (make-test-shell-context)))
      (multiple-value-bind (path resource error)
          (nshell.application::%materialize-process-substitution-in-context
           context
           "<(echo hi)")
        (expect path :to-be-null)
        (expect resource :to-be-null)
        (expect error :to-equal (format nil "nshell: process substitution: ~a~%" "the command must be external")))))
  (it "expand-command-args-materializes-and-aborts-substitutions"
    (let ((context (make-test-shell-context))
          (command (nshell.domain.parsing:make-command-node
                    "cat"
                    (list "<(/bin/printf hi)"))))
      (with-temporary-function
          ((quote nshell.application::%materialize-process-substitution-in-context)
           (lambda (ignored-context value)
             (declare (ignore ignored-context))
             (expect value :to-equal "<(/bin/printf hi)")
             (values "/dev/fd/7" :resource nil)))
        (multiple-value-bind (args resources error)
            (nshell.application::%expand-command-args-in-context context command)
          (expect (mapcar #'nshell.domain.parsing:arg-value args) :to-equal (list "/dev/fd/7"))
          (expect resources :to-equal (list :resource))
          (expect error :to-be-null)))
      (let ((abort-called nil))
        (with-temporary-functions
            (((quote nshell.application::%materialize-process-substitution-in-context)
              (lambda (ignored-context value)
                (declare (ignore ignored-context value))
                (values nil nil "substitution failed")))
             ((quote nshell.application::%abort-process-substitution-resources)
              (lambda (resources)
                (declare (ignore resources))
                (setf abort-called t))))
          (multiple-value-bind (args resources error)
              (nshell.application::%expand-command-args-in-context context command)
            (expect args :to-be-null)
            (expect resources :to-be-null)
            (expect error :to-equal "substitution failed")
            (expect abort-called :to-be-truthy))))))
  (it "expand-command-nodes-aborts-earlier-resources-on-error"
    (let ((context (make-test-shell-context))
          (first-command (nshell.domain.parsing:make-command-node
                          "/bin/printf"
                          (list "first")))
          (second-command (nshell.domain.parsing:make-command-node
                           "/bin/printf"
                           (list "second")))
          (aborted nil)
          (calls 0))
      (with-temporary-functions
          (((quote nshell.application::%expand-command-node-in-context)
            (lambda (ignored-context command)
              (declare (ignore ignored-context))
              (incf calls)
              (if (= calls 1)
                  (values command nil (list :resource))
                  (values nil "node failed" nil))))
           ((quote nshell.application::%abort-process-substitution-resources)
            (lambda (resources)
              (setf aborted resources))))
        (multiple-value-bind (commands error resources)
            (nshell.application::%expand-command-nodes-in-context
             context
             (list first-command second-command))
          (expect commands :to-be-null)
          (expect resources :to-be-null)
          (expect error :to-equal "node failed")
          (expect aborted :to-equal (list :resource))))))
  (it "os-process-substitution-pipeline-releases-resources-after-spawn"
    (let ((captured nil)
          (released nil)
          (waited nil))
      (with-temporary-functions
          (((quote nshell.infrastructure.acl:process-substitution-resource-fd)
            (lambda (resource)
              (declare (ignore resource))
              19))
           ((quote nshell.infrastructure.acl:spawn-pipeline)
            (lambda (commands &key redirects pipefail-p preserve-fds after-spawn)
              (setf captured
                    (list commands redirects pipefail-p preserve-fds))
              (funcall after-spawn)
              23))
           ((quote nshell.infrastructure.acl:release-process-substitution-fd)
            (lambda (resource)
              (push resource released)))
           ((quote nshell.infrastructure.acl:wait-process-substitution)
            (lambda (resource)
              (push resource waited))))
        (multiple-value-bind (output code)
            (nshell.application::%execute-os-pipeline-with-process-substitutions
             '(:command)
             nil
             (list :resource)
             t)
          (expect output :to-equal "")
          (expect code :to-equal 23)
          (expect captured :to-equal (list '(:command) nil t (list 19)))
          (expect released :to-equal (list :resource :resource))
          (expect waited :to-equal (list :resource))))))
  (it "os-process-substitution-pipeline-aborts-on-spawn-failure"
    (let ((closed nil))
      (with-temporary-functions
          (((quote nshell.infrastructure.acl:process-substitution-resource-fd)
            (lambda (resource)
              (declare (ignore resource))
              19))
           ((quote nshell.infrastructure.acl:spawn-pipeline)
            (lambda (commands &key redirects pipefail-p preserve-fds after-spawn)
              (declare (ignore commands redirects pipefail-p preserve-fds after-spawn))
              (error "spawn failed")))
           ((quote nshell.infrastructure.acl:close-process-substitution)
            (lambda (resource)
              (push resource closed))))
        (multiple-value-bind (output code)
            (nshell.application::%execute-os-pipeline-with-process-substitutions
             '(:command)
             nil
             (list :resource)
             nil)
          (expect output :to-equal (format nil "nshell: ~a~%" "spawn failed"))
          (expect code :to-equal 127)
          (expect closed :to-equal (list :resource))))))
  (it "execute-command-rejects-internal-process-substitution"
    (let ((context (make-test-shell-context))
          (aborted nil)
          (command (nshell.domain.parsing:make-command-node "echo" nil)))
      (with-temporary-functions
          (((quote nshell.application::%expand-command-node-in-context)
            (lambda (ignored-context ignored-command)
              (declare (ignore ignored-context ignored-command))
              (values command nil (list :resource))))
           ((quote nshell.application::%abort-process-substitution-resources)
            (lambda (resources)
              (setf aborted resources))))
        (multiple-value-bind (output code)
            (nshell.application::execute-command-node-in-context context command)
          (expect output :to-equal (format nil "nshell: process substitution: ~a~%" "requires an external command"))
          (expect code :to-equal 127)
          (expect aborted :to-equal (list :resource))))))
  (it "execute-pipeline-rejects-cps-process-substitution"
    (let ((context (make-test-shell-context))
          (aborted nil)
          (pipeline (nshell.domain.parsing:make-pipeline-node
                     (list (nshell.domain.parsing:make-command-node "echo" nil)))))
      (with-temporary-functions
          (((quote nshell.application::%expand-command-nodes-in-context)
            (lambda (ignored-context ignored-commands)
              (declare (ignore ignored-context ignored-commands))
              (values (nshell.domain.parsing:pipeline-node-commands pipeline)
                      nil
                      (list :resource))))
           ((quote nshell.application::%abort-process-substitution-resources)
            (lambda (resources)
              (setf aborted resources))))
        (multiple-value-bind (output code)
            (nshell.application::execute-pipeline-node-in-context context pipeline)
          (expect output :to-equal (format nil "nshell: process substitution: ~a~%" "is not supported for internal or CPS pipelines"))
          (expect code :to-equal 127)
          (expect aborted :to-equal (list :resource))))))
  (it "execute-pipeline-routes-os-process-substitutions"
    (let ((context (make-test-shell-context :execution-strategy :os-pipes))
          (pipeline (nshell.domain.parsing:make-pipeline-node
                     (list (nshell.domain.parsing:make-command-node "/bin/cat" nil)))))
      (with-temporary-functions
          (((quote nshell.application::%expand-command-nodes-in-context)
            (lambda (ignored-context ignored-commands)
              (declare (ignore ignored-context ignored-commands))
              (values (nshell.domain.parsing:pipeline-node-commands pipeline)
                      nil
                      (list :resource))))
           ((quote nshell.application::%execute-os-pipeline-with-process-substitutions)
            (lambda (commands redirects resources pipefail-p)
              (declare (ignore commands redirects resources pipefail-p))
              (values "os output" 12))))
        (multiple-value-bind (output code)
            (nshell.application::execute-pipeline-node-in-context context pipeline)
          (expect output :to-equal "os output")
          (expect code :to-equal 12))))))
