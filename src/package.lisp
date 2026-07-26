;;; nshell package definitions
;;; DDD architecture: domain/ must not import from application/, infrastructure/, or presentation/

(eval-when (:compile-toplevel :load-toplevel :execute)
;; -- Main package ------------------------------------------
(defpackage #:nshell
  (:documentation
   "Entry point: parses argv and hands control to the presentation layer's REPL.
Holds no shell logic of its own; it only chooses between interactive, -c, and
script startup.")
  (:use #:cl)
  (:export #:main))

;; -- Foundational, dependency-free utility package -----------
;; No layer restrictions apply: every layer may use this package's macros.
(defpackage #:nshell.util
  (:documentation
   "Layer-free primitives shared by every layer: the DEFINE-VALUE-STRUCT macro
that gives the domain its immutable value types, plus small string predicates.
Depends on nothing but CL, which is why no layer rule applies to it.")
  (:use #:cl)
  (:export #:define-value-struct #:string-prefix-p))

;; -- Domain packages (pure, no side effects) ----------------
(defpackage #:nshell.domain.events
  (:documentation
   "Domain: the vocabulary of things that happen in a shell session -- a command
was entered, a process exited, a job stopped -- as immutable event values.
Publishing and subscribing belong to the application layer's dispatcher; this
package only says what an event is.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:domain-event-type #:domain-event-timestamp
           #:make-generic-domain-event
           #:make-command-entered-event #:make-command-parsed-event
           #:make-parse-failed-event #:make-pipeline-started-event
           #:make-process-created-event #:make-process-exited-event
           #:make-pipeline-completed-event #:make-job-created-event
           #:make-job-stopped-event #:make-job-continued-event
           #:make-job-completed-event #:make-signal-caught-event
           #:make-command-appended-to-history-event #:make-history-searched-event
           #:make-completion-triggered-event))

(defpackage #:nshell.domain.signals
  (:documentation
   "Domain: POSIX signals as domain values, with SIGINT, SIGTERM, SIGCONT, and
SIGCHLD named rather than numbered. Lets job control reason about signals
without any layer above it having to reach for sb-posix; the number mapping is
applied in nshell.infrastructure.acl.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:make-signal #:signal-name #:signal-number #:signal-p #:signal=
           #:+sigint+ #:+sigterm+ #:+sigcont+ #:+sigchld+))

(defpackage #:nshell.domain.input
  (:documentation
   "Domain: the key-event value type -- one keystroke, already classified into a
character, a named key, or a mouse or paste event. It is the seam between the
terminal byte decoder in infrastructure and the line editor in presentation, so
neither side has to know the other's representation.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:key-event #:key-event-p #:make-key-event
           #:key-event-type #:key-event-char #:key-event-number
           #:key-event-data))

(defpackage #:nshell.domain.abbreviation
  (:documentation
   "Domain: fish-style abbreviations -- deciding whether the word before the
cursor is an abbreviation, whether it sits in command position, and what text it
expands to. Purely a function of the buffer and the abbreviation table; the
editing of the buffer is presentation's concern.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:abbreviation-boundary-p
           #:abbreviation-target-before-cursor
           #:abbreviation-command-position-p
           #:abbreviation-p
           #:make-abbreviation
           #:abbreviation-expansion
           #:abbreviation-position
           #:expand-abbreviation))

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
           #:redirect-input-kind-p #:redirect-output-kind-p #:redirect-stderr-kind-p
           #:redirect-append-kind-p #:map-redirect-entries #:redirect-input-spec
           #:redirect-input-file-target #:redirect-output-spec
           #:redirect-stderr-spec #:redirect-output-p
           #:redirect-output-destinations
           #:redirect-output-destinations-p
           #:redirect-output-destinations-stdout-target
           #:redirect-output-destinations-stdout-mode
           #:redirect-output-destinations-stderr-target
           #:redirect-output-destinations-stderr-mode
           #:tokenization-result-p
           #:tokenization-result-tokens
           #:tokenization-result-cursor-token
           #:tokenization-result-incomplete-p
           #:token-type #:token-value #:token-start #:token-end #:make-token
           #:ast-node-type #:make-command-node #:make-pipeline-node
                #:command-node-p #:pipeline-node-p #:sequence-node-p
                #:command-node-command #:command-node-command-quote-style #:command-node-args
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
                #:command-arg-value #:command-arg-quote-style
                #:arg-value #:arg-quote-style
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
from an old one. Importing the real process environment is an injection point
filled by infrastructure, so the domain never reads getenv itself.")
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

(defpackage #:nshell.domain.expansion
  (:documentation
   "Domain: word expansion -- tilde, parameter, arithmetic, brace, and glob --
applied according to each word's quoting style. Globbing needs the filesystem,
so it reaches it through the *GLOB-*-FN* hooks rather than calling DIRECTORY:
that is what keeps expansion testable without a disk.")
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
  (:export #:*glob-directory-files-fn* #:*glob-subdirectories-fn*
           #:glob-match-p
           #:expand-variables #:expand-tilde #:expand-glob #:expand-all
           #:expand-by-quote-style
           #:expand-command-name-fields-by-quote-style
           #:expand-command-name-by-quote-style
           #:expand-double-quoted #:expand-arithmetic #:evaluate-arithmetic
           #:expand-braces #:argv-reference-fields #:*positional-args*
           #:parameter-expansion-error #:parameter-expansion-error-name
           #:parameter-expansion-error-message))

(defpackage #:nshell.domain.completion
  (:documentation
   "Domain: the completion engine. Reads the cursor context out of a command
line, consults a knowledge base of commands, subcommands, and flags, and answers
with ranked candidates. The interesting half is the cl-prolog rulebase: the
exported predicates below are goals callers may query directly.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct #:string-prefix-p)
  (:export #:make-candidate #:candidate-text #:candidate-kind
            #:candidate-description #:candidate-score
            #:make-empty-knowledge-base #:kb-add-command #:kb-add-command-from-help
            #:kb-add-option
            #:kb-remove-command #:kb-command-present-p
            #:kb-command-subcommands #:kb-command-flags
            #:kb-command-option-values #:kb-command-exclusive-options
            #:kb-command-description
            #:make-fact #:make-rule #:fact-p #:rule-p
            #:assert-fact! #:assert-rule! #:prove #:prove-all #:predicate-true-p
            #:completion-rulebase
            ;; Completion logic predicates: the public vocabulary of the
            ;; cl-prolog rulebase produced by COMPLETION-RULEBASE.  Exporting
            ;; the predicate symbols lets callers (and the cl-weave/cl-prolog
            ;; query suites) write goals such as (completes "git" ?c) that
            ;; unify against the same interned symbols the rulebase stores.
            #:completes #:describes #:has-flag
            #:command-is #:suggests-dir #:suggests-file
            #:+command-path-builtin-specs+
            #:+type-builtin-spec+
            #:builtin-help-entries
            #:builtin-completion-command-specs
            #:external-completion-command-specs
            #:builtin-rule-facts
            #:builtin-rule-rules
            #:rule-complete
            #:complete
            #:completion-context-for #:completion-context-command
            #:completion-context-argument-prefix
            #:completion-context-argument-words
            #:completion-context-command-position-p
            #:completion-context-redirection-target-p
            #:completion-filesystem-fns
            #:command-path-candidates
            #:*path-command-directory-files-fn* #:*path-command-executable-p-fn*
            #:*file-completion-directory-files-fn*
            #:*file-completion-subdirectories-fn*))

(defpackage #:nshell.domain.history
  (:documentation
   "Domain: command history as a bounded value -- append, search, merge, delete,
and the cursor used to walk it with the arrow keys. Says nothing about where
history is stored; nshell.infrastructure.persistence owns the file.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:make-history-entry #:entry-text #:entry-timestamp #:entry-exit-code
           #:history-entry-texts
           #:command-history-p #:make-command-history
           #:history-add #:history-search #:history-entry-line-prefix-suffix #:history-all
           #:history-merge #:history-clear #:history-delete
           #:history-empty-p #:history-size #:history-capacity
           #:command-line-last-argument #:history-last-argument-at
           #:history-previous #:history-next #:history-reset-navigation))

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
            #:monitor-remove-job
            #:suspend-job #:foreground-job #:background-job
            #:complete-job))

(defpackage #:nshell.domain.configuration
  (:documentation
   "Domain: user configuration and colour themes as values, including the
defaults used when the config file is absent. Parsing and writing the file is
nshell.infrastructure.persistence's job.")
  (:use #:cl)
  (:export #:make-theme #:theme-color #:theme-name #:theme-set-color
           #:theme-p #:config-p
           #:make-config #:config-theme #:config-prompt
           #:default-theme #:default-config))

(defpackage #:nshell.domain.prompting
  (:documentation
   "Domain: the prompt as a model -- hostname, directory, last exit code,
duration -- and the rules that turn it into left and right segment lists. Git
status and the clock arrive through the *GIT-STATUS-RESOLVER* and
*PROMPT-TIME-RESOLVER* hooks so that rendering a prompt stays deterministic.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:make-prompt-model #:prompt-model-hostname #:prompt-model-cwd
           #:prompt-model-directory #:prompt-model-exit-code
           #:prompt-model-duration-ms #:prompt-model-segments
           #:prompt-model-right-segments #:prompt-segment
           #:make-prompt-segment #:prompt-segment-text
           #:prompt-segment-kind #:*git-status-resolver*
           #:*prompt-time-resolver*
           #:render-prompt-model #:render-right-prompt-model))

;; -- Application packages -----------------------------------
(defpackage #:nshell.application
  (:documentation
   "Application: the use cases. Owns the shell context -- the one mutable object
holding history, environment, aliases, functions, and the job monitor -- and
drives the domain over infrastructure through the function tables stored in it.
Executing a pipeline, running a builtin, and fg/bg/jobs/disown live here; this
is the only layer permitted to know both the domain and the ports.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct #:string-prefix-p)
  (:export #:*job-monitor* #:*shell-pgid* #:*foreground-job-pgid*
            #:make-event-dispatcher #:publish-event
            #:subscribe #:unsubscribe #:drain-events
            #:make-shell-context #:shell-context-p
            #:shell-context-history #:shell-context-config
            #:shell-context-knowledge-base #:shell-context-environment
            #:shell-context-dispatcher #:shell-context-job-monitor
            #:shell-context-alias-table #:shell-context-abbreviation-table
            #:shell-context-function-table #:shell-context-function-source-table
            #:shell-context-filesystem-fns
            #:shell-context-process-fns #:shell-context-terminal-fns
            #:shell-context-signal-fns #:shell-context-redirect-fns
            #:shell-context-history-fns #:shell-context-git-fns
            #:shell-context-execution-strategy #:shell-context-running
            #:shell-context-last-exit-code #:shell-context-input-state
            #:shell-context-job-processes #:shell-context-terminal-rows
            #:shell-context-terminal-cols
            #:lookup-builtin
            #:collect-source-lines #:source-lines
            #:execute-command-line #:execute-pipeline-use-case #:execute-pipeline
            #:execute-command-node-in-context
            #:execute-ast-in-context
            #:execute-external
            #:expand-command-alias-node
            #:job-listing #:job-listing-p
            #:job-listing-id #:job-listing-status #:job-listing-command
            #:format-job-listing
            #:fg #:bg #:jobs #:disown
            #:history-suggestion #:search-history-use-case
            #:interactive-history-search-use-case))

;; -- Infrastructure packages --------------------------------
(defpackage #:nshell.infrastructure.acl
  (:documentation
   "Infrastructure: the anti-corruption layer over the operating system. Every
sb-posix call the shell makes -- fork and exec, pipes, redirection, process
groups, waitpid, PTYs, signal handlers -- is behind this one package, plus the
git subprocess the prompt needs. Its exports are the ports the application layer
stores in the shell context, which is what makes the layers above it mockable.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:*exported-environment*
           #:spawn-pipeline #:spawn-pipeline-async #:wait-job
            #:spawn-async
            #:kill-process #:os-signal->domain
            #:redirect-output #:redirect-error #:redirect-output-and-error
            #:redirect-error-to-output
            #:redirect-input #:redirect-input-document #:redirect-input-string
            #:restore-redirects #:domain-signal->os
            #:install-signal-handlers
            #:open-pty #:with-pty #:pty-read #:pty-write #:pty-close #:make-pty-stream
            #:pty-spawn #:pty-process #:pty-process-p #:pty-process-pid
            #:pty-process-pgid #:pty-process-master-fd #:pty-process-stream
            #:set-process-group #:set-foreground-pgroup #:get-foreground-pgroup
            #:child-status #:child-status-p #:child-status-pid #:child-status-status
            #:reap-children #:get-terminal-size
            #:*external-command-timeout*
            #:run-external #:run-external-capture #:process-exit-status-code
            #:with-git-runner #:clear-git-status-cache
            #:get-git-status))

(defpackage #:nshell.infrastructure.terminal
  (:documentation
   "Infrastructure: the terminal device. Puts the tty into raw mode and restores
it, emits the ANSI sequences for cursor, colour, alternate screen, bracketed
paste, and SGR mouse, and decodes incoming bytes -- including escape sequences --
into the key events defined by nshell.domain.input, which it re-exports so the
line editor has a single place to import them from.")
  (:use #:cl)
  (:import-from #:nshell.domain.input
                #:key-event #:key-event-p #:make-key-event
                #:key-event-type #:key-event-char #:key-event-number
                #:key-event-data)
  (:export #:enable-raw-mode #:restore-terminal-mode
            #:ansi-clear-screen #:ansi-clear-line #:ansi-move-cursor
            #:ansi-color-code
            #:ansi-save-cursor #:ansi-restore-cursor
            #:ansi-hide-cursor #:ansi-show-cursor
            #:ansi-enable-bracketed-paste #:ansi-disable-bracketed-paste
            #:ansi-enable-sgr-mouse #:ansi-disable-sgr-mouse
            #:ansi-enable-alternate-screen #:ansi-disable-alternate-screen
            #:read-key-event
            #:key-event #:key-event-p #:make-key-event
            #:key-event-type #:key-event-char #:key-event-number
            #:key-event-data))

(defpackage #:nshell.infrastructure.persistence
  (:documentation
   "Infrastructure: state that outlives a session. Locates, reads, and appends
to the history file and loads and saves the config file, converting between
those on-disk formats and the domain values in nshell.domain.history and
nshell.domain.configuration.")
  (:use #:cl)
  (:export #:*history-file-path-override*
           #:load-history-file #:append-history-entry
           #:history-file-path
           #:load-config #:save-config))

;; -- Presentation packages ----------------------------------
(defpackage #:nshell.presentation
  (:documentation
   "Presentation: everything the user sees and types at. Holds the line editor's
input state and the reducer that advances it one key event at a time -- emacs
and vi bindings, kill ring, undo, incremental history search, completion cycling
-- plus syntax highlighting, autosuggestion, prompt drawing, and the REPL itself
in its interactive, batch, and script forms.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:input-state #:input-state-p #:make-input-state
            #:input-state-buffer #:input-state-cursor-pos
            #:input-state-completion-index
            #:input-state-completion-base-buffer
            #:input-state-completion-base-cursor
            #:input-state-last-candidates
            #:input-state-suggestion #:input-state-mode
            #:input-state-vi-visual-anchor
            #:input-state-abbreviation-expander
            #:input-state-kill-ring
            #:input-state-last-argument-start
            #:input-state-last-argument-end
            #:input-state-last-argument-index
            #:input-state-search-query
            #:input-state-search-original-buffer
            #:input-state-search-original-cursor
            #:input-state-search-index
            #:with-normalized-input-state
            #:apply-history-search-results-to-input-state
            #:reduce-input-state #:insert-newline-at-cursor
            #:output-event
            #:exported-environment-strings
            #:run-repl #:run-repl-batch #:run-repl-script
            #:trampoline #:render-prompt
            #:compute-suggestion #:accept-suggestion
             #:render-completions #:apply-completion
             #:highlight-line
             #:highlight-span-start #:highlight-span-end
             #:highlight-span-role
             #:highlight->ansi #:theme-color->ansi #:segment-kind->role))
)
