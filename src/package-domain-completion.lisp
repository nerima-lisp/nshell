;;; Package definition for the completion domain.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage #:nshell.domain.completion
    (:documentation
     "Domain: the completion engine. Reads the cursor context out of a command
line, consults a knowledge base of commands, subcommands, and flags, and answers
with ranked candidates. The interesting half is the cl-prolog-kit rulebase: the
exported predicates below are goals callers may query directly.")
    (:use #:cl)
    (:import-from #:nshell.util #:define-value-struct #:string-prefix-p)
    (:export #:make-candidate #:candidate-text #:candidate-kind
             #:candidate-description #:candidate-score
             #:make-empty-knowledge-base #:kb-add-command #:kb-add-command-from-help
             #:kb-add-option
             #:kb-remove-command #:kb-command-present-p
             #:kb-command-subcommands #:kb-command-flags
             #:kb-command-option-values #:kb-command-option-value-kinds
             #:kb-command-exclusive-options
             #:kb-command-description
             #:kb-resolve-command-path #:knowledge-base-option-value-kind
             #:make-fact #:make-rule #:fact-p #:rule-p
             #:assert-fact! #:assert-rule! #:prove #:prove-all
             #:completion-rulebase
             ;; Completion logic predicates are the public vocabulary of the
             ;; cl-prolog-kit rulebase produced by COMPLETION-RULEBASE.
             #:completes #:describes #:has-flag
             #:command-is #:suggests-dir #:suggests-file
             #:+command-path-builtin-specs+
             #:+type-builtin-spec+
             #:builtin-help-entries
             #:builtin-completion-command-specs
             #:external-completion-command-specs
             #:external-subcommand-completion-command-specs
             #:builtin-rule-facts
             #:builtin-rule-rules
             #:rule-complete
             #:complete
             #:completion-context-for #:completion-context-command
             #:completion-context-argument-prefix
             #:completion-context-argument-words
             #:completion-context-command-position-p
             #:completion-context-redirection-target-p
             #:filesystem-candidates-for-value-kind
             #:command-path-candidates)))
