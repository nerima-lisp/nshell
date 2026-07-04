(in-package #:nshell/test)

(in-suite completion-rules-tests)

(test knowledge-base-constructor-is-internal-boundary
  (is (not (fboundp 'nshell.domain.completion::make-knowledge-base)))
  (is (fboundp 'nshell.domain.completion::%make-knowledge-base))
  (is (nshell.domain.completion::knowledge-base-p
       (nshell.domain.completion:make-empty-knowledge-base))))

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
  (let ((candidates (nshell.domain.completion::option-value-candidates
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
  (let ((entry (list :command "tool"
                     :description "tool description"
                     :flags '("--flag")
                     :subcommands '("run")
                     :exclusive-options '(("--json" "--yaml")))))
    (is (string= "tool"
                 (nshell.domain.completion::candidate-entry-command-name
                  entry)))
    (is (string= "tool description"
                 (nshell.domain.completion::candidate-entry-description
                  entry)))
    (is (string= ""
                 (nshell.domain.completion::candidate-entry-description
                  '(:command "empty-description"))))
    (is (equal '("--flag")
               (nshell.domain.completion::candidate-entry-flag-specs entry)))
    (is (equal '("run")
               (nshell.domain.completion::candidate-entry-subcommand-specs
                entry)))
    (is (equal '(("--json" "--yaml"))
               (nshell.domain.completion::candidate-entry-exclusive-option-groups
                entry)))))

(test entry-option-values-projects-option-value-spec-boundary
  (let ((entry (list :option-values '(("--mode" "fast" "safe")
                                      ("--format" "json")))))
    (is (equal '(("--mode" "fast" "safe")
                 ("--format" "json"))
               (nshell.domain.completion::entry-option-value-specs entry)))
    (let ((projection
            (nshell.domain.completion::project-entry-option-value-spec
             '("--mode" "fast"))))
      (is (string= "--mode"
                   (nshell.domain.completion::entry-option-value-spec-projection-option
                    projection)))
      (is (equal '("fast")
                 (nshell.domain.completion::entry-option-value-spec-projection-values
                  projection)))
      (is (nshell.domain.completion::entry-option-value-spec-projection-valid-p
           projection)))
    (is (string= "--mode"
                 (nshell.domain.completion::entry-option-value-spec-option
                  '("--mode" "fast"))))
    (is (equal '("fast")
               (nshell.domain.completion::entry-option-value-spec-values
                '("--mode" "fast"))))
    (is (nshell.domain.completion::entry-option-value-spec-for-option-p
         '("--mode" "fast")
         "--mode"))
    (is (not (nshell.domain.completion::entry-option-value-spec-for-option-p
              '("--format" "json")
              "--mode")))
    (is (not (nshell.domain.completion::entry-option-value-spec-projection-valid-p
              (nshell.domain.completion::project-entry-option-value-spec
               '(nil "ignored")))))
    (is (equal '("fast" "safe")
               (nshell.domain.completion::entry-option-values entry "--mode")))
    (is (null (nshell.domain.completion::entry-option-values entry "--missing")))))

(test parse-attached-option-value-prefix-captures-option-and-value-prefix
  (let ((prefix (nshell.domain.completion::parse-attached-option-value-prefix
                 "--mode=fa")))
    (is (string= "--mode"
                 (nshell.domain.completion::attached-option-value-prefix-option
                  prefix)))
    (is (string= "fa"
                 (nshell.domain.completion::attached-option-value-prefix-value-prefix
                  prefix))))
  (is (null (nshell.domain.completion::parse-attached-option-value-prefix
             "--mode"))))

(test parse-separate-option-value-prefix-captures-option-and-value-prefix
  (let ((prefix (nshell.domain.completion::parse-separate-option-value-prefix
                 '("--mode" "fa")
                 "fa")))
    (is (string= "--mode"
                 (nshell.domain.completion::separate-option-value-prefix-option
                  prefix)))
    (is (string= "fa"
                 (nshell.domain.completion::separate-option-value-prefix-value-prefix
                  prefix))))
  (let ((prefix (nshell.domain.completion::parse-separate-option-value-prefix
                 '("--mode")
                 "")))
    (is (string= "--mode"
                 (nshell.domain.completion::separate-option-value-prefix-option
                  prefix)))
    (is (string= ""
                 (nshell.domain.completion::separate-option-value-prefix-value-prefix
                  prefix)))))

(test knowledge-base-candidate-constructors-are-internal-boundaries
  (flet ((internal-symbol-p (name)
           (not (null (find-symbol name '#:nshell.domain.completion)))))
    (is (not (internal-symbol-p "MAKE-ATTACHED-OPTION-VALUE-PREFIX")))
    (is (not (internal-symbol-p "MAKE-SEPARATE-OPTION-VALUE-PREFIX")))
    (is (not (internal-symbol-p "MAKE-ENTRY-OPTION-VALUE-SPEC-PROJECTION")))
    (is (internal-symbol-p "%MAKE-ATTACHED-OPTION-VALUE-PREFIX"))
    (is (internal-symbol-p "%MAKE-SEPARATE-OPTION-VALUE-PREFIX"))
    (is (internal-symbol-p "%MAKE-ENTRY-OPTION-VALUE-SPEC-PROJECTION"))))

(test argument-words-without-value-prefix-removes-in-progress-value-word
  (is (equal '("--mode")
             (nshell.domain.completion::argument-words-without-value-prefix
              '("--mode" "fa")
              "fa")))
  (is (equal '("--mode")
             (nshell.domain.completion::argument-words-without-value-prefix
              '("--mode")
              "")))
  (is (null (nshell.domain.completion::previous-option-for-value-prefix
             '("fa")
             "fa"))))

(test kb-option-value-spec-projection-boundaries-name-domain-parts
  (let ((spec '("--mode" "fast" "safe")))
    (let ((projection
            (nshell.domain.completion::%kb-option-value-spec-projection spec)))
      (is (string= "--mode"
                   (nshell.domain.completion::kb-option-value-spec-projection-option
                    projection)))
      (is (equal '("fast" "safe")
                 (nshell.domain.completion::kb-option-value-spec-projection-values
                  projection)))
      (is (nshell.domain.completion::kb-option-value-spec-projection-valid-p
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
    (is (not (nshell.domain.completion::kb-option-value-spec-projection-valid-p
              (nshell.domain.completion::%kb-option-value-spec-projection
               '(nil "ignored")))))
    (is (equal '("--mode" "safe")
               (nshell.domain.completion::%make-kb-option-value-spec
                "--mode" '("safe"))))))

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
               (getf (nshell.domain.completion:kb-query kb "tool")
                     :exclusive-options)))))

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

(test unique-kb-string-values-deduplicates-preserving-first-occurrence
  "unique-kb-string-values keeps first occurrence and drops later duplicates."
  (flet ((uniq (&rest vals)
           (nshell.domain.completion::%unique-kb-string-values vals)))
    (is (null (uniq)))
    (is (equal '("a") (uniq "a" "a" "a")))
    (is (equal '("a" "b" "c") (uniq "a" "b" "a" "c" "b")))))

(test merge-kb-string-values-combines-and-deduplicates
  "merge-kb-string-values appends two lists and deduplicates."
  (flet ((merge* (a b)
           (nshell.domain.completion::%merge-kb-string-values a b)))
    (is (null (merge* nil nil)))
    (is (equal '("a" "b") (merge* nil '("a" "b"))))
    (is (equal '("a" "b" "c") (merge* '("a" "b") '("b" "c"))))))

(test merge-kb-command-facts-preserves-and-merges-entry-policy
  (let ((entry (list :subcommands '("run")
                     :flags '("--mode")
                     :option-values '(("--mode" "fast"))
                     :exclusive-options '(("--json" "--yaml"))
                     :description "catalog")))
    (is (eq entry
            (nshell.domain.completion::%merge-kb-command-facts
             entry
             :subcommands '("test" "run")
             :flags '("--mode" "--verbose")
             :option-values '(("--mode" "safe" "fast")
                              ("--format" "json"))
             :exclusive-options '(("--json" "--yaml")
                                  ("--compact" "--pretty")))))
    (is (equal '("run" "test")
               (nshell.domain.completion::%kb-command-entry-subcommands entry)))
    (is (equal '("--mode" "--verbose")
               (nshell.domain.completion::%kb-command-entry-flags entry)))
    (is (equal '(("--format" "json")
                 ("--mode" "fast" "safe"))
               (nshell.domain.completion::%kb-command-entry-option-values entry)))
    (is (equal '(("--json" "--yaml")
                 ("--compact" "--pretty"))
               (nshell.domain.completion::%kb-command-entry-exclusive-options
                entry)))
    (is (string= "catalog"
                 (nshell.domain.completion::%kb-command-entry-description
                  entry)))))

(test merge-kb-command-facts-updates-description-when-present
  (let ((entry (list :subcommands nil
                     :flags nil
                     :option-values nil
                     :exclusive-options nil
                     :description "catalog")))
    (nshell.domain.completion::%merge-kb-command-facts
     entry
     :description "dynamic loader")
    (is (string= "dynamic loader"
                 (nshell.domain.completion::%kb-command-entry-description
                  entry)))))

(test add-kb-command-entry-option-merges-through-entry-boundary
  (let ((entry (list :subcommands nil
                     :flags '("--mode")
                     :option-values '(("--mode" "fast"))
                     :exclusive-options nil
                     :description nil)))
    (is (eq entry
            (nshell.domain.completion::%add-kb-command-entry-option
             entry "--mode" '("safe" "fast"))))
    (is (equal '("--mode")
               (nshell.domain.completion::%kb-command-entry-flags entry)))
    (is (equal '(("--mode" "fast" "safe"))
               (nshell.domain.completion::%kb-command-entry-option-values
                entry)))))

(test normalize-kb-exclusive-option-groups-filters-singletons-and-deduplicates
  "normalize drops singleton groups and deduplicates values within each group."
  (flet ((norm (groups)
           (nshell.domain.completion::%normalize-kb-exclusive-option-groups groups)))
    (is (null (norm nil)))
    ;; singleton ("--a") is dropped; ("--a" "--b") is kept
    (is (equal '(("--a" "--b")) (norm '(("--a" "--b") ("--a")))))
    ;; duplicates within group: ("--c" "--d" "--c") → ("--c" "--d")
    (is (equal '(("--c" "--d")) (norm '(("--c" "--d" "--c")))))))
