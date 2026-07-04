(in-package #:nshell/test)

(in-suite completion-rules-tests)

(defun %test-catalog-entry (&rest source-entry)
  (first (nshell.domain.completion::%command-catalog (list source-entry))))

(test knowledge-base-constructor-is-internal-boundary
  (is (not (fboundp 'nshell.domain.completion::make-knowledge-base)))
  (is (fboundp 'nshell.domain.completion::%make-knowledge-base))
  (is (not (fboundp 'nshell.domain.completion::knowledge-base-commands)))
  (is (fboundp 'nshell.domain.completion::%knowledge-base-commands))
  (is (nshell.domain.completion::knowledge-base-p
       (nshell.domain.completion:make-empty-knowledge-base))))

(test knowledge-base-command-storage-is-traversed-through-boundary
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base))
        (commands nil))
    (nshell.domain.completion:kb-add-command kb "zeta")
    (nshell.domain.completion:kb-add-command kb "alpha")
    (nshell.domain.completion::%map-kb-commands
     kb
     (lambda (name entry)
       (push (cons name entry) commands)))
    (setf commands (nreverse commands))
    (is (equal '("alpha" "zeta") (mapcar #'car commands)))
    (is (every #'nshell.domain.completion::%kb-command-entry-p
               (mapcar #'cdr commands)))))

(test command-candidate-helpers-are-internal-boundaries
  (flet ((defined-symbol-p (name)
           (nth-value 1 (find-symbol name '#:nshell.domain.completion))))
    (is (not (defined-symbol-p "SORTED-CANDIDATES-BY-TEXT")))
    (is (not (defined-symbol-p "COMMAND-ENTRY-CANDIDATE"))))
  (is (fboundp 'nshell.domain.completion::%sorted-candidates-by-text))
  (is (fboundp 'nshell.domain.completion::%command-entry-candidate)))

(test knowledge-base-completion-uses-explicit-command-facts
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "custom" :flags '("--custom"))
    (let ((commands (nshell.domain.completion:complete kb "cu"))
          (arguments (completion-texts (nshell.domain.completion:complete kb "custom --c"))))
      (is (= 1 (length commands)))
      (is (string= "custom" (nshell.domain.completion:candidate-text (first commands))))
      (is (equal '("--custom") arguments)))))

(test knowledge-base-completes-attached-option-values
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :flags '("--color")
     :option-values '(("--color" "auto" "always" "never")))
    (is (equal '("--color=always" "--color=auto")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --color=a"))))
    (is (null (nshell.domain.completion:complete kb "tool --missing=a")))))

(test knowledge-base-completes-separate-option-values
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :flags '("--color" "-o")
     :option-values '(("--color" "auto" "always" "never")
                      ("-o" "json" "yaml" "wide")))
    (is (equal '("always" "auto")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --color a"))))
    (is (equal '("always" "auto" "never")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --color "))))
    (is (equal '("yaml")
               (completion-texts
                (nshell.domain.completion:complete kb "tool -o y"))))
    (is (equal '("--color")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --"))))))

(test option-value-candidates-project-values-through-shared-boundary
  (let ((candidates (nshell.domain.completion::%option-value-candidates
                     '("zsh" "bash")
                     :text-function (lambda (value)
                                      (concatenate 'string "--shell=" value)))))
    (is (equal '("--shell=bash" "--shell=zsh")
               (completion-texts candidates)))
    (is (every (lambda (candidate)
                 (and (eq :option
                          (nshell.domain.completion:candidate-kind candidate))
                      (string= "option value"
                               (nshell.domain.completion:candidate-description
                               candidate))))
               candidates))))

(test entry-candidate-projection-boundaries-name-command-entry-parts
  (let ((entry (%test-catalog-entry
                :command "tool"
                :description "tool description"
                :flags '("--flag")
                :subcommands '("run")
                :exclusive-options '(("--json" "--yaml"))))
        (empty-description-entry (%test-catalog-entry
                                  :command "empty-description")))
    (is (string= "tool"
                 (nshell.domain.completion::%candidate-entry-command-name
                  entry)))
    (is (string= "tool description"
                 (nshell.domain.completion::%candidate-entry-description
                  entry)))
    (is (string= ""
                 (nshell.domain.completion::%candidate-entry-description
                  empty-description-entry)))
    (is (equal '("--flag")
               (nshell.domain.completion::%candidate-entry-flag-specs entry)))
    (is (equal '("run")
               (nshell.domain.completion::%candidate-entry-subcommand-specs
                entry)))
    (is (equal '(("--json" "--yaml"))
               (nshell.domain.completion::%candidate-entry-exclusive-option-groups
                entry)))))

(test entry-candidate-projection-reads-knowledge-base-entry-boundary
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :subcommands '("run")
     :flags '("--flag")
     :option-values '(("--flag" "value"))
     :exclusive-options '(("--json" "--yaml"))
     :description "tool description")
    (let ((entry (nshell.domain.completion::%kb-command-entry kb "tool")))
      (is (string= "tool description"
                   (nshell.domain.completion::%candidate-entry-description
                    entry)))
      (is (equal '("--flag")
                 (nshell.domain.completion::%candidate-entry-flag-specs
                  entry)))
      (is (equal '("run")
                 (nshell.domain.completion::%candidate-entry-subcommand-specs
                  entry)))
      (is (equal '(("--json" "--yaml"))
                 (nshell.domain.completion::%candidate-entry-exclusive-option-groups
                  entry)))
      (is (equal '(("--flag" "value"))
                 (nshell.domain.completion::%entry-option-value-specs
                  entry))))))

(test candidate-entry-projection-helpers-are-internal-boundaries
  (flet ((defined-symbol-p (name)
           (nth-value 1 (find-symbol name '#:nshell.domain.completion))))
    (is (not (defined-symbol-p "CANDIDATE-ENTRY-COMMAND-NAME")))
    (is (not (defined-symbol-p "CANDIDATE-ENTRY-DESCRIPTION")))
    (is (not (defined-symbol-p "CANDIDATE-ENTRY-FLAG-SPECS")))
    (is (not (defined-symbol-p "CANDIDATE-ENTRY-SUBCOMMAND-SPECS")))
    (is (not (defined-symbol-p "CANDIDATE-ENTRY-EXCLUSIVE-OPTION-GROUPS"))))
  (is (fboundp 'nshell.domain.completion::%candidate-entry-command-name))
  (is (fboundp 'nshell.domain.completion::%candidate-entry-description))
  (is (fboundp 'nshell.domain.completion::%candidate-entry-flag-specs))
  (is (fboundp 'nshell.domain.completion::%candidate-entry-subcommand-specs))
  (is (fboundp 'nshell.domain.completion::%candidate-entry-exclusive-option-groups)))

(test entry-option-values-projects-option-value-spec-boundary
  (let ((entry (%test-catalog-entry
                :command "tool"
                :option-values '(("--mode" "fast" "safe")
                                 ("--format" "json")))))
    (is (equal '(("--mode" "fast" "safe")
                 ("--format" "json"))
               (nshell.domain.completion::%entry-option-value-specs entry)))
    (let ((projection
            (nshell.domain.completion::%project-option-value-spec-list
             '("--mode" "fast"))))
      (is (string= "--mode"
                   (nshell.domain.completion::%option-value-spec-list-projection-option
                    projection)))
      (is (equal '("fast")
                 (nshell.domain.completion::%option-value-spec-list-projection-values
                  projection)))
      (is (nshell.domain.completion::%option-value-spec-list-projection-valid-p
            projection)))
    (is (string= "--mode"
                 (nshell.domain.completion::%entry-option-value-spec-option
                  '("--mode" "fast"))))
    (is (equal '("fast")
               (nshell.domain.completion::%entry-option-value-spec-values
                '("--mode" "fast"))))
    (is (nshell.domain.completion::%entry-option-value-spec-for-option-p
         '("--mode" "fast")
         "--mode"))
    (is (not (nshell.domain.completion::%entry-option-value-spec-for-option-p
              '("--format" "json")
              "--mode")))
    (is (not (nshell.domain.completion::%option-value-spec-list-projection-valid-p
              (nshell.domain.completion::%project-option-value-spec-list
               '(nil "ignored")))))
    (is (equal '("fast" "safe")
               (nshell.domain.completion::%entry-option-values entry "--mode")))
    (is (null (nshell.domain.completion::%entry-option-values
               entry
               "--missing")))))

(test entry-option-value-spec-projection-is-internal-boundary
  (flet ((defined-symbol-p (name)
           (nth-value 1 (find-symbol name '#:nshell.domain.completion))))
    (is (not (defined-symbol-p "UNIQUE-STRING-VALUES")))
    (is (not (defined-symbol-p "ENTRY-OPTION-VALUE-SPECS")))
    (is (not (defined-symbol-p "ENTRY-OPTION-VALUE-SPEC-OPTION")))
    (is (not (defined-symbol-p "ENTRY-OPTION-VALUE-SPEC-VALUES")))
    (is (not (defined-symbol-p "ENTRY-OPTION-VALUE-SPEC-FOR-OPTION-P")))
    (is (not (defined-symbol-p "ENTRY-OPTION-VALUES")))
    (is (not (defined-symbol-p "MATCHING-ENTRY-OPTION-VALUES")))
    (is (not (defined-symbol-p "OPTION-VALUE-CANDIDATE")))
    (is (not (defined-symbol-p "ATTACHED-OPTION-VALUE-CANDIDATE-TEXT")))
    (is (not (defined-symbol-p "OPTION-VALUE-CANDIDATES")))
    (is (not (defined-symbol-p "ATTACHED-OPTION-VALUE-CANDIDATES")))
    (is (not (defined-symbol-p "SEPARATE-OPTION-VALUE-CANDIDATES")))
    (is (not (defined-symbol-p "MAKE-ENTRY-OPTION-VALUE-SPEC-PROJECTION")))
    (is (not (defined-symbol-p "ENTRY-OPTION-VALUE-SPEC-PROJECTION-OPTION")))
    (is (not (defined-symbol-p "ENTRY-OPTION-VALUE-SPEC-PROJECTION-VALUES")))
    (is (not (defined-symbol-p "ENTRY-OPTION-VALUE-SPEC-PROJECTION-VALID-P"))))
  (is (fboundp 'nshell.domain.completion::%unique-string-values))
  (is (fboundp 'nshell.domain.completion::%entry-option-value-specs))
  (is (fboundp 'nshell.domain.completion::%entry-option-value-spec-option))
  (is (fboundp 'nshell.domain.completion::%entry-option-value-spec-values))
  (is (fboundp
        'nshell.domain.completion::%entry-option-value-spec-for-option-p))
  (is (fboundp 'nshell.domain.completion::%entry-option-values))
  (is (fboundp 'nshell.domain.completion::%matching-entry-option-values))
  (is (fboundp 'nshell.domain.completion::%option-value-candidate))
  (is (fboundp
        'nshell.domain.completion::%attached-option-value-candidate-text))
  (is (fboundp 'nshell.domain.completion::%option-value-candidates))
  (is (fboundp 'nshell.domain.completion::%attached-option-value-candidates))
  (is (fboundp 'nshell.domain.completion::%separate-option-value-candidates))
  (is (fboundp 'nshell.domain.completion::%option-value-spec-list-projection-p))
  (is (fboundp 'nshell.domain.completion::%option-value-spec-list-projection-option))
  (is (fboundp 'nshell.domain.completion::%option-value-spec-list-projection-values))
  (is (fboundp 'nshell.domain.completion::%option-value-spec-list-projection-valid-p)))

(test option-value-spec-list-projection-owns-raw-list-boundary
  (let ((projection
          (nshell.domain.completion::%project-option-value-spec-list
           '("--mode" "fast" "safe"))))
    (is (nshell.domain.completion::%option-value-spec-list-projection-p
         projection))
    (is (string= "--mode"
                 (nshell.domain.completion::%option-value-spec-list-projection-option
                  projection)))
    (is (equal '("fast" "safe")
               (nshell.domain.completion::%option-value-spec-list-projection-values
                projection)))
    (is (nshell.domain.completion::%option-value-spec-list-projection-valid-p
         projection)))
  (is (not (nshell.domain.completion::%option-value-spec-list-projection-valid-p
            (nshell.domain.completion::%project-option-value-spec-list
             '(nil "ignored")))))
  (is (not (nshell.domain.completion::%option-value-spec-list-projection-valid-p
            (nshell.domain.completion::%project-option-value-spec-list
             :invalid)))))

(test parse-attached-option-value-prefix-captures-option-and-value-prefix
  (let ((prefix (nshell.domain.completion::%parse-attached-option-value-prefix
                 "--mode=fa")))
    (is (string= "--mode"
                 (nshell.domain.completion::%attached-option-value-prefix-option
                  prefix)))
    (is (string= "fa"
                 (nshell.domain.completion::%attached-option-value-prefix-value-prefix
                  prefix))))
  (is (null (nshell.domain.completion::%parse-attached-option-value-prefix
             "--mode"))))

(test parse-separate-option-value-prefix-captures-option-and-value-prefix
  (let ((prefix (nshell.domain.completion::%parse-separate-option-value-prefix
                 '("--mode" "fa")
                 "fa")))
    (is (string= "--mode"
                 (nshell.domain.completion::%separate-option-value-prefix-option
                  prefix)))
    (is (string= "fa"
                 (nshell.domain.completion::%separate-option-value-prefix-value-prefix
                  prefix))))
  (let ((prefix (nshell.domain.completion::%parse-separate-option-value-prefix
                 '("--mode")
                 "")))
    (is (string= "--mode"
                 (nshell.domain.completion::%separate-option-value-prefix-option
                  prefix)))
    (is (string= ""
                 (nshell.domain.completion::%separate-option-value-prefix-value-prefix
                  prefix)))))

(test option-value-prefix-projections-are-internal-boundaries
  (flet ((defined-symbol-p (name)
           (nth-value 1 (find-symbol name '#:nshell.domain.completion))))
    (is (not (defined-symbol-p "ATTACHED-OPTION-VALUE-PREFIX-OPTION")))
    (is (not (defined-symbol-p "ATTACHED-OPTION-VALUE-PREFIX-VALUE-PREFIX")))
    (is (not (defined-symbol-p "SEPARATE-OPTION-VALUE-PREFIX-OPTION")))
    (is (not (defined-symbol-p "SEPARATE-OPTION-VALUE-PREFIX-VALUE-PREFIX")))
    (is (not (defined-symbol-p "PARSE-ATTACHED-OPTION-VALUE-PREFIX")))
    (is (not (defined-symbol-p "PARSE-SEPARATE-OPTION-VALUE-PREFIX"))))
  (is (fboundp 'nshell.domain.completion::%attached-option-value-prefix-option))
  (is (fboundp 'nshell.domain.completion::%attached-option-value-prefix-value-prefix))
  (is (fboundp 'nshell.domain.completion::%separate-option-value-prefix-option))
  (is (fboundp 'nshell.domain.completion::%separate-option-value-prefix-value-prefix))
  (is (fboundp 'nshell.domain.completion::%parse-attached-option-value-prefix))
  (is (fboundp 'nshell.domain.completion::%parse-separate-option-value-prefix)))

(test knowledge-base-candidate-constructors-are-internal-boundaries
  (flet ((internal-symbol-p (name)
           (not (null (find-symbol name '#:nshell.domain.completion)))))
    (is (not (internal-symbol-p "MAKE-ATTACHED-OPTION-VALUE-PREFIX")))
    (is (not (internal-symbol-p "MAKE-SEPARATE-OPTION-VALUE-PREFIX")))
    (is (internal-symbol-p "%MAKE-ATTACHED-OPTION-VALUE-PREFIX"))
    (is (internal-symbol-p "%MAKE-SEPARATE-OPTION-VALUE-PREFIX"))
    (is (not (fboundp 'nshell.domain.completion::%make-entry-option-value-spec-projection)))))

(test argument-words-without-value-prefix-removes-in-progress-value-word
  (is (equal '("--mode")
             (nshell.domain.completion::%argument-words-without-value-prefix
              '("--mode" "fa")
              "fa")))
  (is (equal '("--mode")
             (nshell.domain.completion::%argument-words-without-value-prefix
              '("--mode")
              "")))
  (is (null (nshell.domain.completion::%previous-option-for-value-prefix
             '("fa")
             "fa"))))

(test argument-word-sequence-projects-latest-and-prior-words
  (let ((sequence
          (nshell.domain.completion::%argument-word-sequence-from-words
           '("--mode" "fast"))))
    (is (equal '("--mode" "fast")
               (nshell.domain.completion::%argument-word-sequence-words
                sequence)))
    (is (string= "fast"
                 (nshell.domain.completion::%argument-word-sequence-latest
                  sequence)))
    (is (equal '("--mode")
               (nshell.domain.completion::%argument-word-sequence-words-before-latest
                sequence)))))

(test argument-candidate-helpers-are-internal-boundaries
  (flet ((defined-symbol-p (name)
           (nth-value 1 (find-symbol name '#:nshell.domain.completion))))
    (is (not (defined-symbol-p "UNIQUE-ENTRY-ARGUMENT-NAMES")))
    (is (not (defined-symbol-p "LATEST-ARGUMENT-WORD")))
    (is (not (defined-symbol-p "ARGUMENT-WORDS-BEFORE-LATEST")))
    (is (not (defined-symbol-p "ARGUMENT-WORD-SEQUENCE-FROM-WORDS")))
    (is (not (defined-symbol-p "ARGUMENT-WORD-SEQUENCE-LATEST")))
    (is (not (defined-symbol-p "ARGUMENT-WORDS-WITHOUT-VALUE-PREFIX")))
    (is (not (defined-symbol-p "PREVIOUS-OPTION-FOR-VALUE-PREFIX")))
    (is (not (defined-symbol-p "OPTION-TOKEN-MATCHES-P")))
    (is (not (defined-symbol-p "EXCLUSIVE-OPTION-BLOCKED-P")))
    (is (not (defined-symbol-p "AVAILABLE-ENTRY-ARGUMENT-NAMES")))
    (is (not (defined-symbol-p "ARGUMENT-NAME-CANDIDATE")))
    (is (not (defined-symbol-p "ENTRY-ARGUMENT-NAME-CANDIDATES"))))
  (is (fboundp 'nshell.domain.completion::%unique-entry-argument-names))
  (is (fboundp 'nshell.domain.completion::%argument-word-sequence-from-words))
  (is (fboundp 'nshell.domain.completion::%argument-word-sequence-latest))
  (is (fboundp
       'nshell.domain.completion::%argument-word-sequence-words-before-latest))
  (is (fboundp
       'nshell.domain.completion::%argument-words-without-value-prefix))
  (is (fboundp
       'nshell.domain.completion::%previous-option-for-value-prefix))
  (is (fboundp 'nshell.domain.completion::%option-token-matches-p))
  (is (fboundp 'nshell.domain.completion::%exclusive-option-blocked-p))
  (is (fboundp 'nshell.domain.completion::%available-entry-argument-names))
  (is (fboundp 'nshell.domain.completion::%argument-name-candidate))
  (is (fboundp 'nshell.domain.completion::%entry-argument-name-candidates)))

(test kb-option-value-spec-projection-boundaries-name-domain-parts
  (let ((spec '("--mode" "fast" "safe")))
    (let ((projection
            (nshell.domain.completion::%project-option-value-spec-list spec)))
      (is (string= "--mode"
                   (nshell.domain.completion::%option-value-spec-list-projection-option
                    projection)))
      (is (equal '("fast" "safe")
                 (nshell.domain.completion::%option-value-spec-list-projection-values
                  projection)))
      (is (nshell.domain.completion::%option-value-spec-list-projection-valid-p
           projection)))
    (is (string= "--mode"
                 (nshell.domain.completion::%kb-option-value-spec-option spec)))
    (is (equal '("fast" "safe")
               (nshell.domain.completion::%kb-option-value-spec-values spec)))
    (is (nshell.domain.completion::%valid-kb-option-value-spec-p spec))
    (is (nshell.domain.completion::%kb-option-value-spec-for-option-p
         spec "--mode"))
    (is (not (nshell.domain.completion::%kb-option-value-spec-for-option-p
              spec "--other")))
    (is (not (nshell.domain.completion::%valid-kb-option-value-spec-p
              '(nil "ignored"))))
    (is (not (nshell.domain.completion::%option-value-spec-list-projection-valid-p
              (nshell.domain.completion::%project-option-value-spec-list
               '(nil "ignored")))))
    (is (equal '("--mode" "safe")
               (nshell.domain.completion::%make-kb-option-value-spec
                "--mode" '("safe"))))))

(test kb-option-value-spec-projection-is-internal-boundary
  (is (not (fboundp 'nshell.domain.completion::make-option-value-spec-list-projection)))
  (is (not (fboundp 'nshell.domain.completion::option-value-spec-list-projection-option)))
  (is (not (fboundp 'nshell.domain.completion::option-value-spec-list-projection-values)))
  (is (not (fboundp 'nshell.domain.completion::option-value-spec-list-projection-valid-p)))
  (is (not (fboundp 'nshell.domain.completion::project-option-value-spec-list)))
  (is (not (fboundp 'nshell.domain.completion::make-kb-option-value-spec-projection)))
  (is (not (fboundp 'nshell.domain.completion::kb-option-value-spec-projection-option)))
  (is (not (fboundp 'nshell.domain.completion::kb-option-value-spec-projection-values)))
  (is (not (fboundp 'nshell.domain.completion::kb-option-value-spec-projection-valid-p)))
  (is (fboundp 'nshell.domain.completion::%make-option-value-spec-list-projection))
  (is (fboundp 'nshell.domain.completion::%option-value-spec-list-projection-option))
  (is (fboundp 'nshell.domain.completion::%option-value-spec-list-projection-values))
  (is (fboundp 'nshell.domain.completion::%option-value-spec-list-projection-valid-p))
  (is (fboundp 'nshell.domain.completion::%project-option-value-spec-list))
  (is (not (fboundp 'nshell.domain.completion::%make-kb-option-value-spec-projection)))
  (is (not (fboundp 'nshell.domain.completion::%kb-option-value-spec-projection-option)))
  (is (not (fboundp 'nshell.domain.completion::%kb-option-value-spec-projection-values)))
  (is (not (fboundp 'nshell.domain.completion::%kb-option-value-spec-projection-valid-p))))

(test knowledge-base-option-value-completion-dedupes-duplicates
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :flags '("--mode")
     :option-values '(("--mode" "auto" "auto" "always" "always" "never")))
    (is (equal '("--mode=always" "--mode=auto")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --mode=a"))))
    (is (equal '("always" "auto")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --mode a"))))))

(test knowledge-base-option-value-completion-merges-duplicate-option-specs
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :flags '("--mode")
     :option-values '(("--mode" "auto")
                      ("--mode" "always" "auto")
                      ("--other" "ignored")))
    (is (equal '("--mode=always" "--mode=auto")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --mode=a"))))
    (is (equal '("always" "auto")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --mode a"))))))

(test knowledge-base-option-values-can-be-added-incrementally
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "tool")
    (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                            :values '("fast" "safe"))
    (is (equal '("--mode=fast")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --mode=f"))))))

(test knowledge-base-add-option-creates-command-entry
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                            :values '("fast" "safe"))
    (is (equal '("--mode")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --"))))
    (is (equal '("--mode=fast")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --mode=f"))))))

(test knowledge-base-add-option-merges-repeated-values
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "tool")
    (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                            :values '("fast" "safe"))
    (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                            :values '("safe" "slow"))
    (is (equal '("--mode=fast")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --mode=f"))))
    (is (equal '("safe" "slow")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --mode s"))))))

(test knowledge-base-add-command-merges-repeated-command-facts
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :subcommands '("run")
     :flags '("--mode")
     :option-values '(("--mode" "fast"))
     :description "first source")
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :subcommands '("test" "run")
     :flags '("--verbose" "--mode")
     :option-values '(("--mode" "safe" "fast")
                      ("--format" "json")))
    (is (equal '("--mode" "--verbose" "run" "test")
               (completion-texts
                (nshell.domain.completion:complete kb "tool "))))
    (is (equal '("--mode=fast")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --mode=f"))))
    (is (equal '("safe")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --mode s"))))
    (is (equal '("--format=json")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --format=j"))))
    (let ((candidate (completion-candidate-by-text
                      "tool"
                      (nshell.domain.completion:complete kb "to"))))
      (is (not (null candidate)))
      (is (string= "first source"
                   (nshell.domain.completion:candidate-description candidate))))))

(test knowledge-base-add-command-updates-description-when-provided
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "tool" :description "first source")
    (nshell.domain.completion:kb-add-command kb "tool" :description "second source")
    (let ((candidate (completion-candidate-by-text
                      "tool"
                      (nshell.domain.completion:complete kb "to"))))
      (is (not (null candidate)))
      (is (string= "second source"
                   (nshell.domain.completion:candidate-description candidate))))))

(test knowledge-base-add-command-merges-exclusive-option-groups
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :exclusive-options '(("--json" "--yaml" "--json")
                          ("--single")))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :exclusive-options '(("--json" "--yaml")
                          ("--compact" "--pretty")))
    (is (equal '(("--json" "--yaml")
                 ("--compact" "--pretty"))
               (nshell.domain.completion:kb-command-exclusive-options
                kb "tool")))))

(test knowledge-base-hides-mutually-exclusive-options-after-selection
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :flags '("--color" "--no-color" "--verbose")
     :exclusive-options '(("--color" "--no-color")))
    (is (equal '("--color" "--no-color" "--verbose")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --"))))
    (is (equal '("--verbose")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --color --"))))
    (is (equal '("--verbose")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --color=always --"))))))

(test knowledge-base-command-completion-carries-description
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "deploy" :description "release service")
    (let ((candidate (completion-candidate-by-text
                      "deploy"
                      (nshell.domain.completion:complete kb "dep"))))
      (is (not (null candidate)))
      (is (string= "release service"
                   (nshell.domain.completion:candidate-description candidate))))))

(test path-command-completion-merges-with-kb-and-path-candidates
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "cargo")
    (with-path-command-adapters
        ((lambda (directory)
           (declare (ignore directory))
           (list #p"/mock/cat" #p"/mock/cargo" #p"/mock/readme"))
         (lambda (entry)
           (not (string= "readme" (file-namestring entry)))))
      (let ((texts (completion-texts
                    (nshell.domain.completion:complete kb "c" :path "/mock:/other"))))
        (is (equal '("cd" "complete" "contains" "count" "cargo" "cat") texts))))))

(test command-completion-ranks-exact-match-first
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "git")
    (nshell.domain.completion:kb-add-command kb "gitk")
    (nshell.domain.completion:kb-add-command kb "gist")
    (let ((texts (completion-texts
                  (nshell.domain.completion:complete kb "git"))))
      (is (equal '("git" "gitk") texts)))))

(test command-completion-ranks-case-sensitive-prefix-before-case-folded-match
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "ZZCase-tool")
    (nshell.domain.completion:kb-add-command kb "zzcase-tool")
    (let ((texts (completion-texts
                  (nshell.domain.completion:complete kb "zzcase"))))
      (is (equal '("zzcase-tool" "ZZCase-tool") texts)))))

(test command-completion-keeps-best-duplicate-metadata
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "tool" :description "managed command")
    (with-path-command-adapters
        ((lambda (directory)
           (declare (ignore directory))
           (list #p"/mock/tool"))
         (constantly t))
      (let ((candidates (nshell.domain.completion:complete kb "to" :path "/mock")))
        (is (= 1 (length candidates)))
        (is (string= "tool"
                     (nshell.domain.completion:candidate-text (first candidates))))
        (is (string= "managed command"
                     (nshell.domain.completion:candidate-description
                      (first candidates))))))))

(test path-command-completion-ignores-argument-position
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (with-path-command-adapters
        ((lambda (directory)
           (declare (ignore directory))
           (list #p"/mock/git"))
         (constantly t))
      (is (null (nshell.domain.completion:complete kb "echo g" :path "/mock"))))))

(test path-command-completion-skips-directory-prefixed-commands
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (with-path-command-adapters
        ((lambda (directory)
           (declare (ignore directory))
           (list #p"/mock/git"))
         (constantly t))
      (is (null (nshell.domain.completion:complete kb "./g" :path "/mock"))))))

(test unique-string-values-deduplicates-preserving-first-occurrence
  "unique-string-values keeps first occurrence and drops later duplicates."
  (flet ((uniq (&rest vals)
           (nshell.domain.completion::%unique-string-values vals)))
    (is (null (uniq)))
    (is (equal '("a") (uniq "a" "a" "a")))
    (is (equal '("a" "b" "c") (uniq "a" "b" "a" "c" "b")))))

(test merge-string-values-combines-and-deduplicates
  "merge-string-values appends two lists and deduplicates."
  (flet ((merge* (a b)
           (nshell.domain.completion::%merge-string-values a b)))
    (is (null (merge* nil nil)))
    (is (equal '("a" "b") (merge* nil '("a" "b"))))
    (is (equal '("a" "b" "c") (merge* '("a" "b") '("b" "c"))))))

(test merge-kb-command-facts-preserves-and-merges-entry-policy
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :subcommands '("run")
     :flags '("--mode")
     :option-values '(("--mode" "fast"))
     :exclusive-options '(("--json" "--yaml"))
     :description "catalog")
    (let ((entry (nshell.domain.completion::%kb-command-entry kb "tool")))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :subcommands '("test" "run")
       :flags '("--mode" "--verbose")
       :option-values '(("--mode" "safe" "fast")
                        ("--format" "json"))
       :exclusive-options '(("--json" "--yaml")
                            ("--compact" "--pretty")))
      (is (eq entry
              (nshell.domain.completion::%kb-command-entry kb "tool"))))
    (is (equal '("run" "test")
               (nshell.domain.completion:kb-command-subcommands kb "tool")))
    (is (equal '("--mode" "--verbose")
               (nshell.domain.completion:kb-command-flags kb "tool")))
    (is (equal '(("--format" "json")
                 ("--mode" "fast" "safe"))
               (nshell.domain.completion:kb-command-option-values kb "tool")))
    (is (equal '(("--json" "--yaml")
                 ("--compact" "--pretty"))
               (nshell.domain.completion:kb-command-exclusive-options
                kb "tool")))
    (is (string= "catalog"
                 (nshell.domain.completion:kb-command-description
                  kb "tool")))))

(test merge-kb-command-facts-updates-description-when-present
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "tool" :description "catalog")
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :description "dynamic loader")
    (is (string= "dynamic loader"
                 (nshell.domain.completion:kb-command-description
                  kb "tool")))))

(test add-kb-command-entry-option-merges-through-entry-boundary
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :flags '("--mode")
     :option-values '(("--mode" "fast")))
    (let ((entry (nshell.domain.completion::%kb-command-entry kb "tool")))
      (nshell.domain.completion:kb-add-option
       kb "tool" "--mode" :values '("safe" "fast"))
      (is (eq entry
              (nshell.domain.completion::%kb-command-entry kb "tool"))))
    (is (equal '("--mode")
               (nshell.domain.completion:kb-command-flags kb "tool")))
    (is (equal '(("--mode" "fast" "safe"))
               (nshell.domain.completion:kb-command-option-values
                kb "tool")))))

(test completion-help-command-facts-are-private-values
  (let ((facts (nshell.domain.completion::%completion-help-command-facts
                (format nil "  --format=(json|yaml)~%  --verbose~%  -h, --help"))))
    (is (nshell.domain.completion::%completion-help-command-facts-p facts))
    (is (not (listp facts)))
    (is (not (fboundp
              'nshell.domain.completion::make-completion-help-command-facts)))
    (is (fboundp
         'nshell.domain.completion::%make-completion-help-command-facts))
    (is (equal '("--format" "--verbose" "-h" "--help")
               (nshell.domain.completion::%completion-help-command-facts-flags
                facts)))
    (is (equal '(("--format" "json" "yaml"))
               (nshell.domain.completion::%completion-help-command-facts-option-values
                facts)))))

(test add-command-from-help-projects-help-facts-through-public-kb-api
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command-from-help
     kb "tool"
     (format nil "  --format=(json|yaml)~%  --verbose~%  --mode=(fast|safe)")
     :description "parsed help")
    (is (equal '("--format" "--verbose" "--mode")
               (nshell.domain.completion:kb-command-flags kb "tool")))
    (is (equal '(("--mode" "fast" "safe")
                 ("--format" "json" "yaml"))
               (nshell.domain.completion:kb-command-option-values kb "tool")))
    (is (string= "parsed help"
                 (nshell.domain.completion:kb-command-description
                  kb "tool")))))

(test knowledge-base-command-entries-are-private-aggregate-values
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "tool")
    (let ((entry (nshell.domain.completion::%kb-command-entry kb "tool")))
      (is (nshell.domain.completion::%kb-command-entry-p entry))
      (is (not (listp entry)))
      (is (not (fboundp 'nshell.domain.completion::make-kb-command-entry)))
      (is (fboundp 'nshell.domain.completion::%make-kb-command-entry)))))

(test knowledge-base-query-api-does-not-expose-entry-plist
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :subcommands '("run")
     :flags '("--mode")
     :option-values '(("--mode" "fast"))
     :exclusive-options '(("--json" "--yaml"))
     :description "tool command")
    (is (not (fboundp 'nshell.domain.completion::kb-query)))
    (is (nshell.domain.completion:kb-command-present-p kb "tool"))
    (is (not (nshell.domain.completion:kb-command-present-p kb "missing")))
    (is (equal '("run")
               (nshell.domain.completion:kb-command-subcommands kb "tool")))
    (is (equal '("--mode")
               (nshell.domain.completion:kb-command-flags kb "tool")))
    (is (equal '(("--mode" "fast"))
               (nshell.domain.completion:kb-command-option-values kb "tool")))
    (is (equal '(("--json" "--yaml"))
               (nshell.domain.completion:kb-command-exclusive-options
                kb "tool")))
    (is (string= "tool command"
                 (nshell.domain.completion:kb-command-description
                  kb "tool")))))

(test normalize-kb-exclusive-option-groups-filters-singletons-and-deduplicates
  "normalize drops singleton groups and deduplicates values within each group."
  (flet ((norm (groups)
           (nshell.domain.completion::%normalize-kb-exclusive-option-groups groups)))
    (is (null (norm nil)))
    ;; singleton ("--a") is dropped; ("--a" "--b") is kept
    (is (equal '(("--a" "--b")) (norm '(("--a" "--b") ("--a")))))
    ;; duplicates within group: ("--c" "--d" "--c") → ("--c" "--d")
    (is (equal '(("--c" "--d")) (norm '(("--c" "--d" "--c")))))))
