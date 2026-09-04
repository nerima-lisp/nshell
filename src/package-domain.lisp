;;; nshell domain package definitions -- see package.lisp for the split's rationale.
;;; DDD architecture: domain/ must not import from application/, infrastructure/, or presentation/

(eval-when (:compile-toplevel :load-toplevel :execute)
(defpackage #:nshell.domain.execution
  (:documentation
   "Domain: commands, pipelines, pipeline plans, and jobs as values, together
with the job state machine that says which transitions between running,
stopped, and completed are legal. Creates no processes -- it describes what is
to be run and what state a run is in, and nshell.application drives it.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export
   ;; A single command
   #:make-command #:command-name #:command-args #:command-to-list
   ;; A pipeline of commands
   #:make-pipeline #:pipeline-p #:pipeline-commands
   #:pipeline-length #:pipeline-empty-p #:pipeline-single-command-p
   ;; The plan derived from a pipeline: which stage reads or writes a pipe
   #:make-pipeline-plan #:pipeline-plan-p #:pipeline-plan-stage-count
   #:pipeline-plan-commands #:pipeline-plan-stage-piped-input-p
   #:pipeline-plan-stage-piped-output-p
   ;; A job and what it is made of
   #:make-job #:job-id #:job-state #:job-pids #:job-known-pids #:job-last-pid
   #:job-pipefail-p
   #:job-pgid #:job-exit-code #:job-command-line #:job-command-display-string
   #:job-background-p
   ;; The job state machine
   #:job-state-valid-p #:job-state-transition
   #:job-running-p #:job-stopped-p #:job-completed-p
   ;; Recording what a run did
   #:job-register-background-processes #:job-record-runtime-metadata
   #:job-set-background-visible #:job-record-terminal-exit-code
   ;; Process groups
   #:valid-process-group-id-p #:job-control-pgid
   ;; Monitor lookup (the monitor itself lives in nshell.domain.job-control)
   #:make-job-monitor #:monitor-find-job))

(defpackage #:nshell.domain.parsing
  (:documentation
   "Domain: the shell grammar. Tokenizes a line, builds the AST, splits
redirections out of commands, and recognises the if/for/while/case/begin
control-flow forms, reporting incomplete input so the reader can ask for a
continuation line. A pure string-to-AST function with no filesystem access.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:tokenize #:shell-assignment-word-p #:parse-command-line
           #:shell-input-blank-p
           #:shell-word-separator-p #:shell-operator-separator-p
           #:shell-token-separator-p #:shell-command-separator-token-p
           #:+redirect-specs+ #:+redirect-fd-dup-specs+
           #:make-redirect-fd-dup-target
           #:redirect-fd-dup-target-p #:redirect-fd-dup-target-source
           #:redirect-fd-dup-target-target #:redirect-fd-dup-target-operator
           #:redirect-input-kind-p #:redirect-output-kind-p #:redirect-stderr-kind-p
           #:redirect-append-kind-p #:map-redirect-entries #:redirect-input-spec
           #:redirect-input-file-target #:redirect-output-spec
           #:redirect-stderr-spec #:redirect-output-p
           #:redirect-output-destinations
           #:redirect-output-destinations-p
           #:redirect-output-destinations-stdout-target
           #:redirect-output-destinations-stdout-mode
           #:redirect-output-destinations-stdout-endpoint
           #:redirect-output-destinations-stderr-target
           #:redirect-output-destinations-stderr-mode
           #:redirect-output-destinations-stderr-endpoint
           #:redirects-require-shell-wrapper-p
           #:shell-redirect-script
           #:tokenization-result-p
           #:tokenization-result-tokens
           #:tokenization-result-cursor-token
           #:tokenization-result-incomplete-p
           #:token-type #:token-value #:token-start #:token-end #:token-quote-style
           #:token-fragments #:make-token
           #:ast-node-type #:make-command-node #:make-pipeline-node
                #:command-node-p #:pipeline-node-p #:sequence-node-p
                #:command-node-command #:command-node-command-quote-style
                #:command-node-command-fragments #:command-node-args
                #:sequence-node-commands #:pipeline-node-commands
                #:sequence-node-separators
                #:command-node-arg-values #:split-command-node-redirects
                #:command-redirect-split-result-p
                #:command-redirect-split-result-clean-command
                #:command-redirect-split-result-redirects
                #:split-command-nodes-redirects
                #:command-list-redirect-split-result-p
                #:command-list-redirect-split-result-clean-commands
                #:command-list-redirect-split-result-redirects
                #:ast-node->command-line
                #:command-arg #:command-arg-p #:make-command-arg
                #:command-arg-value #:command-arg-quote-style #:command-arg-fragments
                #:command-fragment #:command-fragment-p #:make-command-fragment
                #:command-fragment-value #:command-fragment-quote-style
                #:command-fragment-escaped-positions
                #:arg-value #:arg-quote-style #:arg-here-doc-literal-p
                #:sequence-node-command-separator
                #:sequence-node-command-separator-p
                #:sequence-node-command-separator-command
                #:sequence-node-command-separator-separator
                #:sequence-node-command-separators
             #:if-node-p #:if-node-condition #:if-node-then-branch #:if-node-else-branch
             #:for-node-p #:for-node-var-name #:for-node-in-values #:for-node-body
             #:while-node-p #:while-node-condition #:while-node-body
             #:case-clause #:case-clause-p #:make-case-clause
             #:case-clause-pattern #:case-clause-body
             #:case-node-p #:case-node-value #:case-node-clauses
             #:begin-end-node-p #:begin-end-node-body
           #:with-parsed-command-line #:with-parsed-command-line-case #:with-complete-command-line
           #:parse-complete-p #:parse-result-state #:parse-errors
           #:parse-error-messages #:format-parse-error-messages
           #:parse-result-ast #:parse-result-incomplete
           #:parse-diagnostic-kind #:parse-diagnostic-kind-p #:parse-diagnostic-message
           #:parse-diagnostic-start #:parse-diagnostic-end
           #:parse-diagnostic-token))

(defpackage #:nshell.domain.environment
  (:documentation
   "Domain: the shell variable environment as a value -- scalar and list
bindings, their export flags, and the operations that produce a new environment
from an old one. Process values are supplied explicitly by infrastructure.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:environment-p #:make-environment
           #:make-default-environment #:inject-os-environment
           #:env-get #:env-get-values #:env-set #:env-set-values
           #:env-defined-p #:env-exported-p #:env-unset #:env-export
           #:env-assign-default! #:env-binding-name #:env-binding-value
           #:env-binding-values #:env-binding-exported-p
           #:env-bindings #:env-entry-p
           #:env-entry-name #:env-entry-value #:env-list))

(defpackage #:nshell.domain.filesystem
  (:documentation
   "Domain: filesystem capabilities as explicit values. The domain consumes
directory enumeration, executable checks, and directory mapping through this
data object; infrastructure constructs it from host operations.")
  (:use #:cl)
  (:export #:filesystem #:filesystem-p #:make-filesystem
           #:filesystem-directory-files #:filesystem-subdirectories
           #:filesystem-executable-p #:filesystem-directory-map))

(defpackage #:nshell.domain.expansion
  (:documentation
   "Domain: word expansion -- tilde, parameter, arithmetic, brace, and glob --
applied according to each word's quoting style. Globbing consumes an explicit
filesystem capability, so expansion remains testable without a disk.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct #:string-prefix-p)
  (:import-from #:nshell.domain.environment #:env-get)
  ;; cl-parser-kit powers the $((...)) arithmetic tokenizer + Pratt parser.
  (:import-from #:cl-parser-kit
                #:make-tokenizer #:tokenize
                #:make-whitespace-rule #:make-predicate-rule
                #:make-identifier-rule #:make-operator-rule
                #:token-value
                #:make-pratt-table #:register-atom #:register-prefix
                #:register-infix-left #:register-infix-right
                #:register-grouping #:register-ternary
                #:parse-pratt-all #:parse-failure->string)
  (:export #:glob-match-p
           #:expand-variables #:expand-tilde #:expand-glob #:expand-all
           #:expand-by-quote-style
           #:expand-command-name-fields-by-quote-style
           #:expand-command-name-by-quote-style
           #:expand-double-quoted #:expand-arithmetic #:evaluate-arithmetic
           #:expand-braces #:argv-reference-fields #:*positional-args*
           #:parameter-expansion-error #:parameter-expansion-error-name
           #:parameter-expansion-error-message))

(defpackage #:nshell.domain.history
  (:documentation
   "Domain: interactive history expansion and the `!$`/Alt-. last-argument
feature. The shell-specific expansion syntax and tokenizer-coupled argument
extraction live here; generic history storage, search, and recall navigation
are the nerima-lisp `history-kit` library's responsibility, used directly
(qualified as `history-kit:...`) rather than wrapped here.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:command-line-last-argument
           #:history-last-argument-at
           #:history-expand-line))

(defpackage #:nshell.domain.job-control
  (:documentation
   "Domain: the job monitor -- which jobs exist, what number each was given, and
how suspending, foregrounding, and backgrounding move them between states. The
process-group calls those moves imply are made in infrastructure; here they are
transitions on a value.")
  (:use #:cl)
  (:export #:job-monitor-p #:make-job-monitor
            #:monitor-empty-p #:monitor-next-job-id
            #:monitor-add-job #:monitor-add-background-job
            #:monitor-update
            #:monitor-map-jobs #:monitor-find-job
            #:monitor-current-job-id #:monitor-previous-job-id
            #:monitor-resolve-job-spec
            #:monitor-remove-job
            #:suspend-job #:foreground-job #:background-job
            #:complete-job))

)
