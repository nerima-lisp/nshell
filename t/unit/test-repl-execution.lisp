(in-package #:nshell/test)

(describe "repl-tests"
  (it "repl-execute-expands-history-designator-before-parsing"
    "Interactive execution expands history references before parsing and persistence."
    (let ((persisted nil))
      (with-repl-test-state
        (nshell.domain.history:history-add
         nshell.presentation::*history*
         "echo from-history")
        (with-repl-input-state (:buffer "!!" :cursor-pos 2)
          (with-temporary-function
              ('nshell.infrastructure.persistence:append-history-entry
               (lambda (text)
                 (setf persisted text)))
            (capture-process-output-event :execute))))
      (expect "echo from-history" :to-equal persisted)))

  (it "repl-edit-command-replaces-input-from-external-editor"
    "The external editor event writes the current buffer and installs the edited text."
    (with-repl-test-state
      (with-repl-input-state (:buffer "echo before" :cursor-pos 11)
        (with-temporary-function
            ('nshell.presentation::%editor-command-argv
             (lambda () '("fake-editor")))
          (with-temporary-function
              ('nshell.infrastructure.acl:run-external-exec
               (lambda (command args)
                 (declare (ignore command))
                 (let ((path (car (last args))))
                   (with-open-file (stream path
                                           :direction :output
                                           :if-exists :supersede)
                     (write-line "echo edited" stream)))
                 0))
            (capture-process-output-event :edit-command)
            (expect "echo edited"
                    :to-equal
                    (nshell.presentation::input-state-buffer
                     nshell.presentation::*input-state*))))))

  (it "repl-for-loop-expands-in-values"
    "Interactive for loops expand variables in the in list before assignment."
    (with-repl-test-state
      (repl-test-set-env "FIRST" "alpha")
      (with-complete-command-line (result ast "for item in $FIRST beta; do echo $item; done")
        (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
        (multiple-value-bind (output code)
            (call-repl-execute-ast ast)
          (expect 0 :to-equal code)
          (expect (search "alpha" output) :to-be-truthy)
          (expect (search "beta" output) :to-be-truthy)
          (expect (search "$item" output) :to-be-falsy)))))

  (it "repl-execute-output-event-records-command-duration"
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
      (expect (integerp nshell.presentation::*last-command-duration-ms*) :to-be-truthy)
      (expect nshell.presentation::*last-command-duration-ms* :to-be-greater-than-or-equal 0)
      (expect 0 :to-equal nshell.presentation::*last-exit-code*)))

  (it "repl-execute-output-event-records-command-exit-code-in-history"
    "Interactive history entries retain the command exit status after execution."
    (with-repl-test-state
      (with-repl-input-state (:buffer "echo failed" :cursor-pos 11)
        (with-temporary-function
            ('nshell.infrastructure.persistence:append-history-entry
             (lambda (text)
               (declare (ignore text))))
          (with-temporary-function
              ('nshell.presentation::execute-ast
               (lambda (ignored-ast)
                 (declare (ignore ignored-ast))
                 7))
            (capture-process-output-event :execute)
            (let ((entry (first
                          (nshell.domain.history:history-all
                           nshell.presentation::*history*))))
              (expect "echo failed"
                      :to-equal
                      (nshell.domain.history:entry-text entry))
              (expect 7
                      :to-equal
                      (nshell.domain.history:entry-exit-code entry))))))))

  (it "repl-command-duration-allows-sub-millisecond-execution"
    "Sub-millisecond commands should be recorded as a non-negative integer duration."
    (expect 0 :to-equal (nshell.presentation::%elapsed-command-duration-ms 100 100))
    (expect (integerp (nshell.presentation::%elapsed-command-duration-ms 100 100)) :to-be-truthy))

  (it "repl-executes-user-function-in-current-context"
    "Interactive command execution should invoke user-defined functions."
    (with-repl-test-state
      (repl-test-define-function "hi" '("echo from-function"))
      (let ((ast (nshell.domain.parsing:make-command-node "hi" nil)))
        (multiple-value-bind (output code)
            (call-repl-execute-ast ast)
          (expect 0 :to-equal code)
          (expect (format nil "from-function~%") :to-equal output)))))

  (it "repl-expands-command-position-word"
    "Interactive foreground execution expands variables in command position before dispatch."
    (with-repl-test-state
      (repl-test-set-env "CMD" "echo")
      (with-complete-command-line (result ast "$CMD repl-word")
        (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
        (multiple-value-bind (output code)
            (call-repl-execute-ast ast)
          (expect 0 :to-equal code)
          (expect (format nil "repl-word~%") :to-equal output)))))

  (it "repl-rejects-multi-field-command-position-expansion"
    "Interactive foreground execution should not dispatch an ambiguous expanded command name."
    (with-repl-test-state
      (repl-test-set-env "CMD" "echo split")
      (with-complete-command-line (result ast "$CMD repl-word")
        (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
        (multiple-value-bind (output code)
            (call-repl-execute-ast ast)
          (expect 127 :to-equal code)
          (expect (format nil "nshell: $CMD: command name expansion produced 2 fields~%") :to-equal output)))))

  (it "repl-pipeline-feeds-builtin-output-to-read"
    "Interactive pipelines should feed builtin output into later builtin stages in-process."
    (with-repl-test-state
      (let ((ast (nshell.domain.parsing:make-pipeline-node
                  (list (nshell.domain.parsing:make-command-node "echo" (list "piped-value"))
                        (nshell.domain.parsing:make-command-node "read" (list "captured"))))))
        (multiple-value-bind (output code)
            (call-repl-execute-ast ast)
          (expect 0 :to-equal code)
          (expect "" :to-equal output)
          (expect "piped-value" :to-equal (repl-test-env "captured"))))))

  (it "repl-pipeline-feeds-function-output-to-read"
    "Interactive pipelines should pipe function output into builtin stages."
    (with-repl-test-state
      (repl-test-define-function "produce" '("echo function-value"))
      (let ((ast (nshell.domain.parsing:make-pipeline-node
                  (list (nshell.domain.parsing:make-command-node "produce" nil)
                        (nshell.domain.parsing:make-command-node "read" (list "captured"))))))
        (multiple-value-bind (output code)
            (call-repl-execute-ast ast)
          (expect 0 :to-equal code)
          (expect "" :to-equal output)
          (expect "function-value" :to-equal (repl-test-env "captured"))))))

  (it "repl-here-string-feeds-builtin-stdin"
    "Here-strings should feed interactive builtin stdin with a trailing newline."
    (with-repl-test-state
      (with-complete-command-line (result ast "read captured <<< inline-value")
        (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
        (multiple-value-bind (output code)
            (call-repl-execute-ast ast)
          (expect 0 :to-equal code)
          (expect "" :to-equal output)
          (expect "inline-value" :to-equal (repl-test-env "captured"))))))

  (it "repl-here-document-feeds-builtin-stdin"
    "Here-documents should feed interactive builtin stdin without adding bytes."
    (with-repl-test-state
      (with-complete-command-line (result ast (format nil "read captured << EOF~%inline-doc~%EOF"))
        (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
        (multiple-value-bind (output code)
            (call-repl-execute-ast ast)
          (expect 0 :to-equal code)
          (expect "" :to-equal output)
          (expect "inline-doc" :to-equal (repl-test-env "captured"))))))

  (it "repl-if-node-uses-contextual-pipeline-semantics"
    "Interactive control-flow bodies should use the application executor semantics."
    (with-repl-test-state
      (with-complete-command-line (result ast "if test ok = ok; then echo from-if | read captured; fi")
        (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
        (multiple-value-bind (output code)
            (call-repl-execute-ast ast)
          (expect 0 :to-equal code)
          (expect "" :to-equal output)
          (expect "from-if" :to-equal (repl-test-env "captured"))))))

  (it "repl-control-flow-expands-aliases-through-context"
    "Aliases should expand inside interactive control-flow execution."
    (with-repl-test-state
      (repl-test-define-alias "say" "echo aliased")
      (with-complete-command-line (result ast "if test ok = ok; then say value; fi")
        (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
        (multiple-value-bind (output code)
            (call-repl-execute-ast ast)
          (expect 0 :to-equal code)
          (expect (format nil "aliased value~%") :to-equal output)))))

  (it "repl-sequence-and-short-circuits-on-failure"
    "Interactive `&&` sequences should stop after the first failing command."
    (with-repl-test-state
      (with-complete-command-line (result ast "false && echo second")
        (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
        (multiple-value-bind (output code)
            (call-repl-execute-ast ast)
          (expect 1 :to-equal code)
          (expect "" :to-equal output)))))

  (it "repl-sequence-or-short-circuits-on-success"
    "Interactive `||` sequences should stop after the first successful command."
    (with-repl-test-state
      (with-complete-command-line (result ast "true || echo second")
        (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
        (multiple-value-bind (output code)
            (call-repl-execute-ast ast)
          (expect 0 :to-equal code)
          (expect "" :to-equal output))))))
)
