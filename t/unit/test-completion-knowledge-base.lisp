(in-package #:nshell/test)

(defun %test-catalog-entry (&rest source-entry)
  (first (nshell.domain.completion::%command-catalog (list source-entry))))

(describe "completion-rules-tests"
  (it "knowledge-base-constructor-is-internal-boundary"
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :present (nshell.domain.completion::%make-knowledge-base
                  nshell.domain.completion::%knowledge-base-commands)
        :absent (nshell.domain.completion::make-knowledge-base
                 nshell.domain.completion::knowledge-base-commands))
    (expect (nshell.domain.completion::knowledge-base-p
         (nshell.domain.completion:make-empty-knowledge-base)) :to-be-truthy))

  (it "knowledge-base-command-storage-is-traversed-through-boundary"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base))
          (commands nil))
      (nshell.domain.completion:kb-add-command kb "zeta")
      (nshell.domain.completion:kb-add-command kb "alpha")
      (nshell.domain.completion::%map-kb-commands
       kb
       (lambda (name entry)
         (push (cons name entry) commands)))
      (setf commands (nreverse commands))
      (expect '("alpha" "zeta") :to-equal (mapcar #'car commands))
      (expect (every #'nshell.domain.completion::%kb-command-entry-p
                 (mapcar #'cdr commands)) :to-be-truthy)))

  (it "command-candidate-helpers-are-internal-boundaries"
    (assert-package-symbol-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :absent (nshell.domain.completion::sorted-candidates-by-text
                 nshell.domain.completion::command-entry-candidate))
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :present (nshell.domain.completion::%sorted-candidates-by-text
                  nshell.domain.completion::%command-entry-candidate)))

  (it "knowledge-base-completion-uses-explicit-command-facts"
    (with-empty-completion-knowledge-base (kb)
      (nshell.domain.completion:kb-add-command kb "custom" :flags '("--custom"))
      (let ((commands (nshell.domain.completion:complete kb "cu")))
        (expect 1 :to-equal (length commands))
        (expect "custom" :to-equal (nshell.domain.completion:candidate-text (first commands)))
        (assert-completion-texts-for '("--custom") kb "custom --c"))))

  (it "knowledge-base-completes-attached-option-values"
    (with-empty-completion-knowledge-base (kb)
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :flags '("--color")
       :option-values '(("--color" "auto" "always" "never")))
      (assert-completion-texts '("--color=always" "--color=auto")
        (nshell.domain.completion:complete kb "tool --color=a"))
      (expect (nshell.domain.completion:complete kb "tool --missing=a") :to-be-null)))

  (it "knowledge-base-completes-separate-option-values"
    (with-empty-completion-knowledge-base (kb)
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :flags '("--color" "-o")
       :option-values '(("--color" "auto" "always" "never")
                        ("-o" "json" "yaml" "wide")))
      (assert-completion-texts '("always" "auto")
        (nshell.domain.completion:complete kb "tool --color a"))
      (assert-completion-texts-for '("always" "auto" "never") kb "tool --color ")
      (assert-completion-texts-for '("yaml") kb "tool -o y")
      (assert-completion-texts-for '("--color") kb "tool --")))

  (it "option-value-candidates-project-values-through-shared-boundary"
    (let ((candidates (nshell.domain.completion::%option-value-candidates
                       '("zsh" "bash")
                       :text-function (lambda (value)
                                        (concatenate 'string "--shell=" value)))))
      (assert-completion-texts '("--shell=bash" "--shell=zsh") candidates)
      (expect (every (lambda (candidate)
                   (and (eq :option
                            (nshell.domain.completion:candidate-kind candidate))
                        (string= "option value"
                                 (nshell.domain.completion:candidate-description
                                 candidate))))
                 candidates) :to-be-truthy)))

  (it "entry-candidate-projection-boundaries-name-command-entry-parts"
    (let ((entry (%test-catalog-entry
                  :command "tool"
                  :description "tool description"
                  :flags '("--flag")
                  :subcommands '("run")
                  :exclusive-options '(("--json" "--yaml"))))
          (empty-description-entry (%test-catalog-entry
                                    :command "empty-description")))
      (expect "tool" :to-equal (nshell.domain.completion::%candidate-entry-command-name
                    entry))
      (expect "tool description" :to-equal (nshell.domain.completion::%candidate-entry-description
                    entry))
      (expect "" :to-equal (nshell.domain.completion::%candidate-entry-description
                    empty-description-entry))
      (expect '("--flag") :to-equal (nshell.domain.completion::%candidate-entry-flag-specs entry))
      (expect '("run") :to-equal (nshell.domain.completion::%candidate-entry-subcommand-specs
                  entry))
      (expect '(("--json" "--yaml")) :to-equal (nshell.domain.completion::%candidate-entry-exclusive-option-groups
                  entry))))

  (it "entry-candidate-projection-reads-knowledge-base-entry-boundary"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :subcommands '("run")
       :flags '("--flag")
       :option-values '(("--flag" "value"))
       :exclusive-options '(("--json" "--yaml"))
       :description "tool description")
      (let ((entry (nshell.domain.completion::%kb-command-entry kb "tool")))
        (expect "tool description" :to-equal (nshell.domain.completion::%candidate-entry-description
                      entry))
        (expect '("--flag") :to-equal (nshell.domain.completion::%candidate-entry-flag-specs
                    entry))
        (expect '("run") :to-equal (nshell.domain.completion::%candidate-entry-subcommand-specs
                    entry))
        (expect '(("--json" "--yaml")) :to-equal (nshell.domain.completion::%candidate-entry-exclusive-option-groups
                    entry))
        (expect '(("--flag" "value")) :to-equal (nshell.domain.completion::%entry-option-value-specs
                    entry)))))

  (it "candidate-entry-projection-helpers-are-internal-boundaries"
    (assert-package-symbol-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :absent (nshell.domain.completion::candidate-entry-command-name
                 nshell.domain.completion::candidate-entry-description
                 nshell.domain.completion::candidate-entry-flag-specs
                 nshell.domain.completion::candidate-entry-subcommand-specs
                 nshell.domain.completion::candidate-entry-exclusive-option-groups))
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :present (nshell.domain.completion::%candidate-entry-command-name
                  nshell.domain.completion::%candidate-entry-description
                  nshell.domain.completion::%candidate-entry-flag-specs
                  nshell.domain.completion::%candidate-entry-subcommand-specs
                  nshell.domain.completion::%candidate-entry-exclusive-option-groups)))

  (it "entry-option-values-projects-option-value-spec-boundary"
    (let ((entry (%test-catalog-entry
                  :command "tool"
                  :option-values '(("--mode" "fast" "safe")
                                   ("--format" "json")))))
      (expect '(("--mode" "fast" "safe")
                   ("--format" "json")) :to-equal (nshell.domain.completion::%entry-option-value-specs entry))
      (expect "--mode" :to-equal (nshell.domain.completion::%entry-option-value-spec-option
                    '("--mode" "fast")))
      (expect '("fast") :to-equal (nshell.domain.completion::%entry-option-value-spec-values
                  '("--mode" "fast")))
      (expect (nshell.domain.completion::%entry-option-value-spec-for-option-p
           '("--mode" "fast")
           "--mode") :to-be-truthy)
      (expect (nshell.domain.completion::%entry-option-value-spec-for-option-p
                '("--format" "json")
                "--mode") :to-be-falsy)
      (expect (nshell.domain.completion::%valid-kb-option-value-spec-p
                '(nil "ignored")) :to-be-falsy)
      (expect '("fast" "safe") :to-equal (nshell.domain.completion::%entry-option-values entry "--mode"))
      (expect (nshell.domain.completion::%entry-option-values
                 entry
                 "--missing") :to-be-null)))

  (it "entry-option-value-spec-helpers-are-internal-boundaries"
    (assert-package-symbol-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :absent (nshell.domain.completion::unique-string-values
                 nshell.domain.completion::entry-option-value-specs
                 nshell.domain.completion::entry-option-value-spec-option
                 nshell.domain.completion::entry-option-value-spec-values
                 nshell.domain.completion::entry-option-value-spec-for-option-p
                 nshell.domain.completion::entry-option-values
                 nshell.domain.completion::matching-entry-option-values
                 nshell.domain.completion::option-value-candidate
                 nshell.domain.completion::attached-option-value-candidate-text
                 nshell.domain.completion::option-value-candidates
                 nshell.domain.completion::attached-option-value-candidates
                 nshell.domain.completion::separate-option-value-candidates))
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :present (nshell.domain.completion::%unique-string-values
                  nshell.domain.completion::%entry-option-value-specs
                  nshell.domain.completion::%entry-option-value-spec-option
                  nshell.domain.completion::%entry-option-value-spec-values
                  nshell.domain.completion::%entry-option-value-spec-for-option-p
                  nshell.domain.completion::%entry-option-values
                  nshell.domain.completion::%matching-entry-option-values
                  nshell.domain.completion::%option-value-candidate
                  nshell.domain.completion::%attached-option-value-candidate-text
                  nshell.domain.completion::%option-value-candidates
                  nshell.domain.completion::%attached-option-value-candidates
                  nshell.domain.completion::%separate-option-value-candidates)))

  (it "parse-attached-option-value-prefix-captures-option-and-value-prefix"
    (let ((prefix (nshell.domain.completion::%parse-attached-option-value-prefix
                   "--mode=fa")))
      (expect "--mode" :to-equal (nshell.domain.completion::%attached-option-value-prefix-option
                    prefix))
      (expect "fa" :to-equal (nshell.domain.completion::%attached-option-value-prefix-value-prefix
                    prefix)))
    (expect (nshell.domain.completion::%parse-attached-option-value-prefix
               "--mode") :to-be-null))

  (it "parse-separate-option-value-prefix-captures-option-and-value-prefix"
    (let ((prefix (nshell.domain.completion::%parse-separate-option-value-prefix
                   '("--mode" "fa")
                   "fa")))
      (expect "--mode" :to-equal (nshell.domain.completion::%separate-option-value-prefix-option
                    prefix))
      (expect "fa" :to-equal (nshell.domain.completion::%separate-option-value-prefix-value-prefix
                    prefix)))
    (let ((prefix (nshell.domain.completion::%parse-separate-option-value-prefix
                   '("--mode")
                   "")))
      (expect "--mode" :to-equal (nshell.domain.completion::%separate-option-value-prefix-option
                    prefix))
      (expect "" :to-equal (nshell.domain.completion::%separate-option-value-prefix-value-prefix
                    prefix))))

  (it "option-value-prefix-projections-are-internal-boundaries"
    (assert-package-symbol-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :absent (nshell.domain.completion::attached-option-value-prefix-option
                 nshell.domain.completion::attached-option-value-prefix-value-prefix
                 nshell.domain.completion::separate-option-value-prefix-option
                 nshell.domain.completion::separate-option-value-prefix-value-prefix
                 nshell.domain.completion::parse-attached-option-value-prefix
                 nshell.domain.completion::parse-separate-option-value-prefix))
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :present (nshell.domain.completion::%attached-option-value-prefix-option
                  nshell.domain.completion::%attached-option-value-prefix-value-prefix
                  nshell.domain.completion::%separate-option-value-prefix-option
                  nshell.domain.completion::%separate-option-value-prefix-value-prefix
                  nshell.domain.completion::%parse-attached-option-value-prefix
                  nshell.domain.completion::%parse-separate-option-value-prefix)))

  (it "knowledge-base-candidate-constructors-are-internal-boundaries"
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :present (nshell.domain.completion::%make-attached-option-value-prefix
                  nshell.domain.completion::%make-separate-option-value-prefix)
        :absent (nshell.domain.completion::make-attached-option-value-prefix
                 nshell.domain.completion::make-separate-option-value-prefix)))

  (it "argument-words-without-value-prefix-removes-in-progress-value-word"
    (expect '("--mode") :to-equal (nshell.domain.completion::%argument-words-without-value-prefix
                '("--mode" "fa")
                "fa"))
    (expect '("--mode") :to-equal (nshell.domain.completion::%argument-words-without-value-prefix
                '("--mode")
                ""))
    (expect (nshell.domain.completion::%previous-option-for-value-prefix
               '("fa")
               "fa") :to-be-null))

  (it "argument-word-sequence-projects-latest-and-prior-words"
    (let ((sequence
            (nshell.domain.completion::%argument-word-sequence-from-words
             '("--mode" "fast"))))
      (expect '("--mode" "fast") :to-equal (nshell.domain.completion::%argument-word-sequence-words
                  sequence))
      (expect "fast" :to-equal (nshell.domain.completion::%argument-word-sequence-latest
                    sequence))
      (expect '("--mode") :to-equal (nshell.domain.completion::%argument-word-sequence-words-before-latest
                  sequence))))

  (it "argument-candidate-helpers-are-internal-boundaries"
    (assert-package-symbol-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :absent (nshell.domain.completion::unique-entry-argument-names
                 nshell.domain.completion::latest-argument-word
                 nshell.domain.completion::argument-words-before-latest
                 nshell.domain.completion::argument-word-sequence-from-words
                 nshell.domain.completion::argument-word-sequence-latest
                 nshell.domain.completion::argument-words-without-value-prefix
                 nshell.domain.completion::previous-option-for-value-prefix
                 nshell.domain.completion::option-token-matches-p
                 nshell.domain.completion::exclusive-option-blocked-p
                 nshell.domain.completion::available-entry-argument-names
                 nshell.domain.completion::argument-name-candidate
                 nshell.domain.completion::entry-argument-name-candidates))
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :present (nshell.domain.completion::%unique-entry-argument-names
                  nshell.domain.completion::%argument-word-sequence-from-words
                  nshell.domain.completion::%argument-word-sequence-latest
                  nshell.domain.completion::%argument-word-sequence-words-before-latest
                  nshell.domain.completion::%argument-words-without-value-prefix
                  nshell.domain.completion::%previous-option-for-value-prefix
                  nshell.domain.completion::%option-token-matches-p
                  nshell.domain.completion::%exclusive-option-blocked-p
                  nshell.domain.completion::%available-entry-argument-names
                  nshell.domain.completion::%argument-name-candidate
                  nshell.domain.completion::%entry-argument-name-candidates)))

  (it "kb-option-value-spec-helpers-name-domain-parts"
    (let ((spec '("--mode" "fast" "safe")))
      (expect "--mode" :to-equal (nshell.domain.completion::%kb-option-value-spec-option spec))
      (expect '("fast" "safe") :to-equal (nshell.domain.completion::%kb-option-value-spec-values spec))
      (expect (nshell.domain.completion::%valid-kb-option-value-spec-p spec) :to-be-truthy)
      (expect (nshell.domain.completion::%kb-option-value-spec-for-option-p
           spec "--mode") :to-be-truthy)
      (expect (nshell.domain.completion::%kb-option-value-spec-for-option-p
                spec "--other") :to-be-falsy)
      (expect (nshell.domain.completion::%valid-kb-option-value-spec-p
                '(nil "ignored")) :to-be-falsy)
      (expect '("--mode" "safe") :to-equal (nshell.domain.completion::%make-kb-option-value-spec
                  "--mode" '("safe")))))

  (it "kb-option-value-spec-helpers-are-internal-boundaries"
    (assert-package-symbol-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :absent (nshell.domain.completion::make-kb-option-value-spec
                 nshell.domain.completion::kb-option-value-spec-option
                 nshell.domain.completion::kb-option-value-spec-values))
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :present (nshell.domain.completion::%kb-option-value-spec-option
                  nshell.domain.completion::%kb-option-value-spec-values
                  nshell.domain.completion::%valid-kb-option-value-spec-p
                  nshell.domain.completion::%kb-option-value-spec-for-option-p))))
