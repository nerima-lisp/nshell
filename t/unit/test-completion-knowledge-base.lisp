(in-package #:nshell/test)

(defun %test-catalog-entry (&rest source-entry)
  (first (nshell.domain.completion::%command-catalog (list source-entry))))

(describe "completion-rules-tests"
  (it "knowledge-base-constructor-is-internal-boundary"
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :present (nshell.domain.completion::make-knowledge-base)
        :absent (nshell.domain.completion::%make-knowledge-base))
    (expect (nshell.domain.completion::knowledge-base-p
         (nshell.domain.completion:make-empty-knowledge-base)) :to-be-truthy)
    (expect (nshell.domain.completion::rule-knowledge-base-p
         (nshell.domain.completion:make-empty-knowledge-base)) :to-be-truthy))

  (it "knowledge-base-command-registry-is-queried-through-public-accessors"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "zeta")
      (nshell.domain.completion:kb-add-command kb "alpha")
      (expect '("alpha" "zeta") :to-equal (nshell.domain.completion::kb-registered-commands kb))))

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

  (it "builtin-command-candidates-project-catalog-entry-name-and-description"
    (let ((entry (%test-catalog-entry
                  :command "tool"
                  :description "tool description"))
          (empty-description-entry (%test-catalog-entry
                                    :command "empty-description")))
      (expect "tool" :to-equal (nshell.domain.completion::%catalog-command-entry-command entry))
      (expect "tool description" :to-equal (nshell.domain.completion::%catalog-command-entry-description
                    entry))
      (expect nil :to-equal (nshell.domain.completion::%catalog-command-entry-description
                    empty-description-entry))))

  (it "knowledge-base-command-accessors-read-back-added-facts"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :subcommands '("run")
       :flags '("--flag")
       :option-values '(("--flag" "value"))
       :exclusive-options '(("--json" "--yaml"))
       :description "tool description")
      (expect "tool description" :to-equal (nshell.domain.completion:kb-command-description kb "tool"))
      (expect '("--flag") :to-equal (nshell.domain.completion:kb-command-flags kb "tool"))
      (expect '("run") :to-equal (nshell.domain.completion:kb-command-subcommands kb "tool"))
      (expect '(("--json" "--yaml")) :to-equal (nshell.domain.completion:kb-command-exclusive-options
                  kb "tool"))
      (expect '(("--flag" "value")) :to-equal (nshell.domain.completion:kb-command-option-values
                  kb "tool"))))

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
                  nshell.domain.completion::%kb-option-value-spec-for-option-p)))

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
        :absent (nshell.domain.completion::unique-kb-argument-names
                 nshell.domain.completion::latest-argument-word
                 nshell.domain.completion::argument-words-before-latest
                 nshell.domain.completion::argument-word-sequence-from-words
                 nshell.domain.completion::argument-word-sequence-latest
                 nshell.domain.completion::argument-words-without-value-prefix
                 nshell.domain.completion::previous-option-for-value-prefix
                 nshell.domain.completion::option-token-matches-p
                 nshell.domain.completion::kb-exclusive-option-blocked-p
                 nshell.domain.completion::available-kb-argument-names
                 nshell.domain.completion::argument-name-candidate
                 nshell.domain.completion::kb-argument-name-candidates))
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :present (nshell.domain.completion::%unique-kb-argument-names
                  nshell.domain.completion::%argument-word-sequence-from-words
                  nshell.domain.completion::%argument-word-sequence-latest
                  nshell.domain.completion::%argument-word-sequence-words-before-latest
                  nshell.domain.completion::%argument-words-without-value-prefix
                  nshell.domain.completion::%previous-option-for-value-prefix
                  nshell.domain.completion::%option-token-matches-p
                  nshell.domain.completion::%kb-exclusive-option-blocked-p
                  nshell.domain.completion::%available-kb-argument-names
                  nshell.domain.completion::%argument-name-candidate
                  nshell.domain.completion::%kb-argument-name-candidates))))
