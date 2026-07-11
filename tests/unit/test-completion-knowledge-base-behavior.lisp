(in-package #:nshell/test)

(in-suite completion-rules-tests)

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
                (format nil "Commands:~%  run   execute the tool~%  test  verify behavior~%~%  --format=(json|yaml)~%  --verbose~%  -h, --help"))))
    (assert-symbol-boundaries
        :present (nshell.domain.completion::%make-completion-help-command-facts)
        :absent (nshell.domain.completion::make-completion-help-command-facts))
    (assert-completion-help-command-facts
        facts
      :subcommands '("run" "test")
      :flags '("--format" "--verbose" "-h" "--help")
      :option-values '(("--format" "json" "yaml")))))

(test add-command-from-help-projects-help-facts-through-public-kb-api
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command-from-help
     kb "tool"
     (format nil "Commands:~%  run   execute the tool~%  test  verify behavior~%~%  --format=(json|yaml)~%  --verbose~%  --mode=(fast|safe)")
     :description "parsed help")
    (is (equal '("run" "test")
               (nshell.domain.completion:kb-command-subcommands kb "tool")))
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
      (assert-symbol-boundaries
          :present (nshell.domain.completion::%make-kb-command-entry)
          :absent (nshell.domain.completion::make-kb-command-entry))
      (is (nshell.domain.completion::%kb-command-entry-p entry))
      (is (not (listp entry))))))

(test knowledge-base-query-api-does-not-expose-entry-plist
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command
     kb "tool"
     :subcommands '("run")
     :flags '("--mode")
     :option-values '(("--mode" "fast"))
     :exclusive-options '(("--json" "--yaml"))
     :description "tool command")
    (assert-symbol-boundaries
        :absent (nshell.domain.completion::kb-query))
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
