(in-package #:nshell/test)

(in-suite repl-tests)

(test repl-for-loop-expands-in-values
  "Interactive for loops expand variables in the in list before assignment."
  (with-repl-test-state
    (repl-test-set-env "FIRST" "alpha")
    (let ((ast (nshell.domain.parsing::make-for-node
                "item"
                (list "$FIRST" "beta")
                (list (nshell.domain.parsing:make-command-node
                       "echo"
                       (list "$item"))))))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (is (= 0 code))
        (is (search "alpha" output))
        (is (search "beta" output))
        (is (not (search "$item" output)))))))

(test repl-execute-output-event-records-command-duration
  "Interactive execution records the elapsed runtime through the output event path."
  (with-repl-test-state
    (with-repl-input-state (:buffer "echo done" :cursor-pos 9)
      (with-temporary-function
          ('nshell.infrastructure.persistence:append-history-entry
           (lambda (text)
             (declare (ignore text))))
        (with-temporary-function
            ('nshell.presentation::execute-ast
             (lambda (ignored-ast)
               (declare (ignore ignored-ast))
               (sleep 0.05)
               0))
          (capture-process-output-event :execute))))
    (is (integerp nshell.presentation::*last-command-duration-ms*))
    (is (>= nshell.presentation::*last-command-duration-ms* 0))
    (is (= 0 nshell.presentation::*last-exit-code*))))

(test repl-command-duration-allows-sub-millisecond-execution
  "Sub-millisecond commands should be recorded as a non-negative integer duration."
  (is (= 0 (nshell.presentation::%elapsed-command-duration-ms 100 100)))
  (is (integerp (nshell.presentation::%elapsed-command-duration-ms 100 100))))

(test repl-executes-user-function-in-current-context
  "Interactive command execution should invoke user-defined functions."
  (with-repl-test-state
    (repl-test-define-function "hi" '("echo from-function"))
    (let ((ast (nshell.domain.parsing:make-command-node "hi" nil)))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (is (= 0 code))
        (is (string= (format nil "from-function~%") output))))))

(test repl-expands-command-position-word
  "Interactive foreground execution expands variables in command position before dispatch."
  (with-repl-test-state
    (repl-test-set-env "CMD" "echo")
    (with-complete-command-line (result ast "$CMD repl-word")
      (is (null (nshell.domain.parsing:parse-errors result)))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (is (= 0 code))
        (is (string= (format nil "repl-word~%") output))))))

(test repl-rejects-multi-field-command-position-expansion
  "Interactive foreground execution should not dispatch an ambiguous expanded command name."
  (with-repl-test-state
    (repl-test-set-env "CMD" "echo split")
    (with-complete-command-line (result ast "$CMD repl-word")
      (is (null (nshell.domain.parsing:parse-errors result)))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (is (= 127 code))
        (is (string= (format nil "nshell: $CMD: command name expansion produced 2 fields~%")
                     output))))))

(test repl-pipeline-feeds-builtin-output-to-read
  "Interactive pipelines should feed builtin output into later builtin stages in-process."
  (with-repl-test-state
    (let ((ast (nshell.domain.parsing:make-pipeline-node
                (list (nshell.domain.parsing:make-command-node "echo" (list "piped-value"))
                      (nshell.domain.parsing:make-command-node "read" (list "captured"))))))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (is (= 0 code))
        (is (string= "" output))
        (is (string= "piped-value"
                     (repl-test-env "captured")))))))

(test repl-pipeline-feeds-function-output-to-read
  "Interactive pipelines should pipe function output into builtin stages."
  (with-repl-test-state
    (repl-test-define-function "produce" '("echo function-value"))
    (let ((ast (nshell.domain.parsing:make-pipeline-node
                (list (nshell.domain.parsing:make-command-node "produce" nil)
                      (nshell.domain.parsing:make-command-node "read" (list "captured"))))))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (is (= 0 code))
        (is (string= "" output))
        (is (string= "function-value"
                     (repl-test-env "captured")))))))

(test repl-here-string-feeds-builtin-stdin
  "Here-strings should feed interactive builtin stdin with a trailing newline."
  (with-repl-test-state
    (with-complete-command-line (result ast "read captured <<< inline-value")
      (is (null (nshell.domain.parsing:parse-errors result)))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (is (= 0 code))
        (is (string= "" output))
        (is (string= "inline-value"
                     (repl-test-env "captured")))))))

(test repl-here-document-feeds-builtin-stdin
  "Here-documents should feed interactive builtin stdin without adding bytes."
  (with-repl-test-state
    (with-complete-command-line (result ast (format nil "read captured << EOF~%inline-doc~%EOF"))
      (is (null (nshell.domain.parsing:parse-errors result)))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (is (= 0 code))
        (is (string= "" output))
        (is (string= "inline-doc"
                     (repl-test-env "captured")))))))

(test repl-if-node-uses-contextual-pipeline-semantics
  "Interactive control-flow bodies should use the application executor semantics."
  (with-repl-test-state
    (let ((ast (nshell.domain.parsing::make-if-node
                (nshell.domain.parsing:make-command-node "test" (list "ok" "=" "ok"))
                (list (nshell.domain.parsing:make-pipeline-node
                       (list (nshell.domain.parsing:make-command-node "echo" (list "from-if"))
                             (nshell.domain.parsing:make-command-node "read" (list "captured"))))))))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (is (= 0 code))
        (is (string= "" output))
        (is (string= "from-if"
                     (repl-test-env "captured")))))))

(test repl-control-flow-expands-aliases-through-context
  "Aliases should expand inside interactive control-flow execution."
  (with-repl-test-state
    (repl-test-define-alias "say" "echo aliased")
    (let ((ast (nshell.domain.parsing::make-if-node
                (nshell.domain.parsing:make-command-node "test" (list "ok" "=" "ok"))
                (list (nshell.domain.parsing:make-command-node "say" (list "value"))))))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (is (= 0 code))
        (is (string= (format nil "aliased value~%") output))))))

(test repl-sequence-and-short-circuits-on-failure
  "Interactive `&&` sequences should stop after the first failing command."
  (with-repl-test-state
    (let ((ast (nshell.domain.parsing::make-sequence-node
                (list (nshell.domain.parsing:make-command-node "false" nil)
                      (nshell.domain.parsing:make-command-node "echo" (list "second")))
                '(:and))))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (is (= 1 code))
        (is (string= "" output))))))

(test repl-sequence-or-short-circuits-on-success
  "Interactive `||` sequences should stop after the first successful command."
  (with-repl-test-state
    (let ((ast (nshell.domain.parsing::make-sequence-node
                (list (nshell.domain.parsing:make-command-node "true" nil)
                      (nshell.domain.parsing:make-command-node "echo" (list "second")))
                '(:or))))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (is (= 0 code))
        (is (string= "" output))))))
