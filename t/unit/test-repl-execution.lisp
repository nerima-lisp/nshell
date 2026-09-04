(in-package #:nshell/test)

(describe "repl-tests"
  (it "repl-state-table-factories-use-their-declared-key-semantics"
    "Name tables compare string keys by content while process tables compare job ids by identity."
    (let ((name-table (nshell.presentation::%make-repl-name-table))
          (process-table (nshell.presentation::%make-repl-process-registry)))
      (setf (gethash (copy-seq "alias") name-table) :value
            (gethash 7 process-table) :process)
      (expect :value :to-equal (gethash "alias" name-table))
      (expect :process :to-equal (gethash 7 process-table))
      (expect nil :to-be (gethash "7" process-table))))
  (it "repl-state-tables-provide-independent-name-and-process-tables"
    "The REPL state starts with four name tables and one process registry."
    (multiple-value-bind (aliases functions variables completions processes)
        (nshell.presentation::%make-repl-state-tables)
      (dolist (table (list aliases functions variables completions))
        (expect 'equal :to-equal (hash-table-test table)))
      (expect 'eql :to-equal (hash-table-test processes))))

  (it "process-environment-boundaries-preserve-inheritance-and-overrides"
    "Environment ACLs expose the process values and prefer explicitly exported entries."
    (let* ((nshell.infrastructure.acl::*exported-environment* nil)
           (entries (nshell.infrastructure.acl:current-environment-entries))
           (entry (first entries))
           (separator (and entry (position #\= entry)))
           (name (and separator (subseq entry 0 separator)))
           (value (and separator (subseq entry (1+ separator)))))
      (expect entries :to-be-truthy)
      (expect (and name value) :to-be-truthy)
      (expect (equal value (nshell.infrastructure.acl:current-environment-value name))
              :to-be-truthy)
      (expect (or (pathnamep (nshell.infrastructure.acl:current-working-directory))
                  (stringp (nshell.infrastructure.acl:current-working-directory)))
              :to-be-truthy)
      (setf nshell.infrastructure.acl::*exported-environment* '("PATH=/custom"))
      (expect '("PATH=/custom") :to-equal
              (nshell.infrastructure.acl::%get-environment))))
  (it "repl-execute-expands-history-designator-before-parsing"
    "Interactive execution expands history references before parsing and persistence."
    (let ((persisted nil))
      (with-repl-test-state
        (history-kit:history-add
         nshell.presentation::*history*
         "echo from-history")
        (with-repl-input-state (:buffer "!!" :cursor-pos 2)
          (with-temporary-function
              ('nshell.infrastructure.persistence:append-history-entry
               (lambda (text)
                 (setf persisted text)))
            (capture-process-output-event :execute))))
      (expect "echo from-history" :to-equal persisted)))
  (it "repl-editor-command-parser-preserves-quoted-and-escaped-arguments"
    "The editor command parser should retain quoted and escaped argument boundaries."
    (expect
      (list "emacs" "-nw" "file name" "--flag=value" "path with spaces" "trailing\\")
      :to-equal
      (nshell.presentation::%split-editor-command
       "emacs -nw \"file name\" \"--flag=value\" path\\ with\\ spaces trailing\\")))
  (it "repl-editor-command-argv-observes-editor-precedence-and-fallback"
    "The editor selection should honor environment precedence and recover from unusable values."
    (with-repl-test-state
      (repl-test-set-env "NSHELL_EDITOR" "")
      (repl-test-set-env "VISUAL" "")
      (repl-test-set-env "EDITOR" "nano")
      (expect (list "nano") :to-equal (nshell.presentation::%editor-command-argv))
      (repl-test-set-env "VISUAL" "vim -f")
      (expect (list "vim" "-f") :to-equal (nshell.presentation::%editor-command-argv))
      (repl-test-set-env "NSHELL_EDITOR" "emacs -nw")
      (expect (list "emacs" "-nw") :to-equal (nshell.presentation::%editor-command-argv))
      (repl-test-set-env "NSHELL_EDITOR" " ")
      (expect (list "vi") :to-equal (nshell.presentation::%editor-command-argv)))
    (with-repl-test-state
      (repl-test-set-env "NSHELL_EDITOR" "")
      (repl-test-set-env "VISUAL" "")
      (repl-test-set-env "EDITOR" "")
      (expect (list "vi") :to-equal (nshell.presentation::%editor-command-argv))))

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
                         nshell.presentation::*input-state*)))))))

  (it "repl-edit-command-passes-string-argv-to-run-external-exec"
    "The exec boundary requires string argv elements, so the temporary buffer
path must be converted from a pathname before being appended."
    (with-repl-test-state
      (with-repl-input-state (:buffer "echo before" :cursor-pos 11)
        (with-temporary-function
            ('nshell.presentation::%editor-command-argv
             (lambda () '("fake-editor")))
          (with-temporary-function
              ('nshell.infrastructure.acl:run-external-exec
               (lambda (command args)
                 (declare (ignore command))
                 (dolist (arg args)
                   (expect (stringp arg) :to-be-truthy))
                 (let ((path (car (last args))))
                   (with-open-file (stream path
                                           :direction :output
                                           :if-exists :supersede)
                     (write-line "echo edited" stream)))
                 0))
            (capture-process-output-event :edit-command))))))

  (it "repl-edit-command-reports-editor-exit-status"
    (with-repl-test-state
      (with-repl-input-state (:buffer "echo before" :cursor-pos 11)
        (with-temporary-function
            ('nshell.presentation::%editor-command-argv
             (lambda () '("fake-editor")))
          (with-temporary-function
              ('nshell.presentation::%run-external-editor
               (lambda (argv path)
                 (declare (ignore argv path))
                 7))
            (let ((output (capture-process-output-event :edit-command)))
              (expect (search "nshell: editor exited with status 7" output)
                      :to-be-truthy)))))))

  (it "repl-edit-command-reports-editor-errors"
    (with-repl-test-state
      (with-repl-input-state (:buffer "echo before" :cursor-pos 11)
        (with-temporary-function
            ('nshell.presentation::%editor-command-argv
             (lambda () '("fake-editor")))
          (with-temporary-function
              ('nshell.presentation::%run-external-editor
               (lambda (argv path)
                 (declare (ignore argv path))
                 (error "forced editor failure")))
            (let ((output (capture-process-output-event :edit-command)))
              (expect (search "nshell: editor failed: forced editor failure"
                              output)
                      :to-be-truthy)))))))

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
                          (history-kit:history-entries
                           nshell.presentation::*history*))))
              (expect "echo failed"
                      :to-equal
                      (history-kit:history-entry-text entry))
              (expect 7
                      :to-equal
                      (history-kit:history-entry-exit-code entry))))))))

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
          (expect "" :to-equal output)))))

  (it "repl-output-execution-handles-empty-input"
    "Executing an empty line clears command timing and resets the edit state."
    (with-repl-test-state
      (setf nshell.presentation::*last-command-duration-ms* 10)
      (with-stable-repl-prompt ()
        (with-fixed-terminal-size (24 80)
          (with-repl-input-state (:buffer "" :cursor-pos 0)
            (let ((output (capture-process-output-event :execute)))
              (expect (search (format nil "~%") output) :to-be-truthy)
              (expect 0 :to-equal nshell.presentation::*last-exit-code*)
              (expect nshell.presentation::*last-command-duration-ms*
                      :to-be-null)
              (is-input-state nshell.presentation::*input-state*
                              :buffer ""
                              :cursor-pos 0)))))))

  (it "repl-output-execution-reports-history-expansion-errors"
    "History expansion failures should be rendered as command diagnostics."
    (with-repl-test-state
      (with-temporary-function
          ('nshell.domain.history:history-expand-line
           (lambda (&rest arguments)
             (declare (ignore arguments))
             (values nil "history failure")))
        (with-stable-repl-prompt ()
          (with-fixed-terminal-size (24 80)
            (with-repl-input-state (:buffer "echo" :cursor-pos 4)
              (let ((output (capture-process-output-event :execute)))
                (expect (search "history failure" output) :to-be-truthy)
                (expect 2 :to-equal nshell.presentation::*last-exit-code*)
                (is-input-state nshell.presentation::*input-state*
                                :buffer ""
                                :cursor-pos 0))))))))

  (it "repl-output-execution-reports-unexpected-errors"
    "Unexpected execution errors should reset the edit state with status one."
    (with-repl-test-state
      (with-temporary-function
          ('nshell.domain.history:history-expand-line
           (lambda (&rest arguments)
             (declare (ignore arguments))
             (error "history exploded")))
        (with-stable-repl-prompt ()
          (with-fixed-terminal-size (24 80)
            (with-repl-input-state (:buffer "echo" :cursor-pos 4)
              (let ((output (capture-process-output-event :execute)))
                (expect (search "history exploded" output) :to-be-truthy)
                (expect 1 :to-equal nshell.presentation::*last-exit-code*)
                (is-input-state nshell.presentation::*input-state*
                                :buffer ""
                                :cursor-pos 0))))))))

  (it "repl-output-execution-reports-parse-errors"
    "A parse error from the public execute event should reach the error stream."
    (with-repl-test-state
      (with-stable-repl-prompt ()
        (with-fixed-terminal-size (24 80)
          (with-repl-input-state (:buffer "case vanilla" :cursor-pos 12)
            (let ((output
                    (capture-standard-output
                      (let ((*error-output* *standard-output*))
                        (let ((continuation
                                (nshell.presentation::process-output-event :execute)))
                          (when continuation
                            (funcall continuation)))))))
              (expect (search "nshell: syntax error:" output) :to-be-truthy)
              (expect 2 :to-equal nshell.presentation::*last-exit-code*)
              (is-input-state nshell.presentation::*input-state*
                              :buffer ""
                              :cursor-pos 0)))))))

  (it "repl-output-execution-keeps-incomplete-input-for-continuation"
    "An incomplete command should remain editable after the execute event."
    (with-repl-test-state
      (with-stable-repl-prompt ()
        (with-fixed-terminal-size (24 80)
          (with-repl-input-state (:buffer "echo '" :cursor-pos 6)
            (let ((output (capture-process-output-event :execute)))
              (expect (search (format nil "~%") output) :to-be-truthy)
              (expect 0 :to-equal nshell.presentation::*last-exit-code*)
              (expect (format nil "echo '~%")
                      :to-equal
                      (nshell.presentation:input-state-buffer
                       nshell.presentation::*input-state*))))))))
)
(describe "repl-shell-context-branch-tests"
  (it "repl-external-command-availability-distinguishes-paths"
    (with-repl-test-state
      (expect "/bin/sh" :to-equal
              (nshell.presentation::%repl-external-command-available-p "/bin/sh"))
      (expect (nshell.presentation::%repl-external-command-available-p
               "/definitely/not/a/nshell-command")
              :to-be-falsy)))
  (it "repl-shell-context-sync-writes-output-and-defaults-code"
    (with-repl-test-state
      (let ((output nil)
            (code nil)
            (printed nil))
        (setf printed
              (capture-standard-output
                (multiple-value-setq (output code)
                  (nshell.presentation::%execute-with-repl-shell-context
                   (lambda (context)
                     (setf (nshell.application:shell-context-pipefail-p context) t)
                     (values "context-output" 7))))))
        (expect "context-output" :to-equal output)
        (expect 7 :to-equal code)
        (expect "context-output" :to-equal printed)
        (expect t :to-be nshell.presentation::*pipefail*)
        (expect 7 :to-equal nshell.presentation::*last-exit-code*))
      (let ((output nil)
            (code nil)
            (printed nil))
        (setf printed
              (capture-standard-output
                (multiple-value-setq (output code)
                  (nshell.presentation::%execute-with-repl-shell-context
                   (lambda (context)
                     (declare (ignore context))
                     (values nil nil))))))
        (expect output :to-be-null)
        (expect 0 :to-equal code)
        (expect "" :to-equal printed))))
  (it "repl-execute-ast-rejects-unsupported-node"
    "Unsupported AST values produce a diagnostic and a nonzero status."
    (with-repl-test-state
      (multiple-value-bind (output code)
          (call-repl-execute-ast nil)
        (expect (format nil "nshell: cannot execute~%") :to-equal output)
        (expect 1 :to-equal code)))))
