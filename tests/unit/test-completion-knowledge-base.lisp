(in-package #:nshell/test)

(in-suite completion-rules-tests)

(test knowledge-base-completion-uses-explicit-command-facts
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "custom" :flags '("--custom"))
    (let ((commands (nshell.domain.completion:complete kb "cu"))
          (arguments (completion-texts (nshell.domain.completion:complete kb "custom --c"))))
      (is (= 1 (length commands)))
      (is (string= "custom" (nshell.domain.completion:candidate-text (first commands))))
      (is (equal '("--custom") arguments)))))

(test knowledge-base-completes-attached-option-values
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :flags '("--color")
     :option-values '(("--color" "auto" "always" "never")))
    (is (equal '("--color=always" "--color=auto")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --color=a"))))
    (is (null (nshell.domain.completion:complete kb "tool --missing=a")))))

(test knowledge-base-completes-separate-option-values
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
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

(test knowledge-base-option-value-completion-dedupes-duplicates
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
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
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
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
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "tool")
    (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                            :values '("fast" "safe"))
    (is (equal '("--mode=fast")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --mode=f"))))))

(test knowledge-base-add-option-creates-command-entry
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                            :values '("fast" "safe"))
    (is (equal '("--mode")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --"))))
    (is (equal '("--mode=fast")
               (completion-texts
                (nshell.domain.completion:complete kb "tool --mode=f"))))))

(test knowledge-base-add-option-merges-repeated-values
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
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
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
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
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "tool" :description "first source")
    (nshell.domain.completion:kb-add-command kb "tool" :description "second source")
    (let ((candidate (completion-candidate-by-text
                      "tool"
                      (nshell.domain.completion:complete kb "to"))))
      (is (not (null candidate)))
      (is (string= "second source"
                   (nshell.domain.completion:candidate-description candidate))))))

(test knowledge-base-add-command-merges-exclusive-option-groups
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
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
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
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
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "deploy" :description "release service")
    (let ((candidate (completion-candidate-by-text
                      "deploy"
                      (nshell.domain.completion:complete kb "dep"))))
      (is (not (null candidate)))
      (is (string= "release service"
                   (nshell.domain.completion:candidate-description candidate))))))

(test path-command-completion-merges-with-kb-and-path-candidates
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
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
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "git")
    (nshell.domain.completion:kb-add-command kb "gitk")
    (nshell.domain.completion:kb-add-command kb "gist")
    (let ((texts (completion-texts
                  (nshell.domain.completion:complete kb "git"))))
      (is (equal '("git" "gitk") texts)))))

(test command-completion-ranks-case-sensitive-prefix-before-case-folded-match
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "ZZCase-tool")
    (nshell.domain.completion:kb-add-command kb "zzcase-tool")
    (let ((texts (completion-texts
                  (nshell.domain.completion:complete kb "zzcase"))))
      (is (equal '("zzcase-tool" "ZZCase-tool") texts)))))

(test command-completion-keeps-best-duplicate-metadata
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
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
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (with-path-command-adapters
        ((lambda (directory)
           (declare (ignore directory))
           (list #p"/mock/git"))
         (constantly t))
      (is (null (nshell.domain.completion:complete kb "echo g" :path "/mock"))))))

(test path-command-completion-skips-directory-prefixed-commands
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
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

(test normalize-kb-exclusive-option-groups-filters-singletons-and-deduplicates
  "normalize drops singleton groups and deduplicates values within each group."
  (flet ((norm (groups)
           (nshell.domain.completion::%normalize-kb-exclusive-option-groups groups)))
    (is (null (norm nil)))
    ;; singleton ("--a") is dropped; ("--a" "--b") is kept
    (is (equal '(("--a" "--b")) (norm '(("--a" "--b") ("--a")))))
    ;; duplicates within group: ("--c" "--d" "--c") → ("--c" "--d")
    (is (equal '(("--c" "--d")) (norm '(("--c" "--d" "--c")))))))
