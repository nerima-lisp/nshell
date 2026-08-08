(in-package #:nshell/test)

(describe "completion-rules-tests"
  (it "knowledge-base-option-value-completion-dedupes-duplicates"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :flags '("--mode")
       :option-values '(("--mode" "auto" "auto" "always" "always" "never")))
      (expect '("--mode=always" "--mode=auto") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode=a")))
      (expect '("always" "auto") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode a")))))

  (it "knowledge-base-option-value-completion-merges-duplicate-option-specs"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :flags '("--mode")
       :option-values '(("--mode" "auto")
                        ("--mode" "always" "auto")
                        ("--other" "ignored")))
      (expect '("--mode=always" "--mode=auto") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode=a")))
      (expect '("always" "auto") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode a")))))

  (it "knowledge-base-option-values-can-be-added-incrementally"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "tool")
      (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                              :values '("fast" "safe"))
      (expect '("--mode=fast") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode=f")))))

  (it "knowledge-base-add-option-creates-command-entry"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                              :values '("fast" "safe"))
      (expect '("--mode") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --")))
      (expect '("--mode=fast") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode=f")))))

  (it "knowledge-base-add-option-merges-repeated-values"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "tool")
      (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                              :values '("fast" "safe"))
      (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                              :values '("safe" "slow"))
      (expect '("--mode=fast") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode=f")))
      (expect '("safe" "slow") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode s")))))

  (it "knowledge-base-add-command-merges-repeated-command-facts"
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
      (expect '("--mode" "--verbose" "run" "test") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool ")))
      (expect '("--mode=fast") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode=f")))
      (expect '("safe") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode s")))
      (expect '("--format=json") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --format=j")))
      (let ((candidate (completion-candidate-by-text
                        "tool"
                        (nshell.domain.completion:complete kb "to"))))
        (expect (null candidate) :to-be-falsy)
        (expect "first source" :to-equal (nshell.domain.completion:candidate-description candidate)))))

  (it "knowledge-base-add-command-updates-description-when-provided"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "tool" :description "first source")
      (nshell.domain.completion:kb-add-command kb "tool" :description "second source")
      (let ((candidate (completion-candidate-by-text
                        "tool"
                        (nshell.domain.completion:complete kb "to"))))
        (expect (null candidate) :to-be-falsy)
        (expect "second source" :to-equal (nshell.domain.completion:candidate-description candidate)))))

  (it "knowledge-base-add-command-merges-exclusive-option-groups"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :exclusive-options '(("--json" "--yaml" "--json")
                            ("--single")))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :exclusive-options '(("--json" "--yaml")
                            ("--compact" "--pretty")))
      (expect '(("--json" "--yaml")
                   ("--compact" "--pretty")) :to-equal (nshell.domain.completion:kb-command-exclusive-options
                  kb "tool"))))

  (it "knowledge-base-hides-mutually-exclusive-options-after-selection"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :flags '("--color" "--no-color" "--verbose")
       :exclusive-options '(("--color" "--no-color")))
      (expect '("--color" "--no-color" "--verbose") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --")))
      (expect '("--verbose") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --color --")))
      (expect '("--verbose") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --color=always --")))))

  (it "knowledge-base-command-completion-carries-description"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "deploy" :description "release service")
      (let ((candidate (completion-candidate-by-text
                        "deploy"
                        (nshell.domain.completion:complete kb "dep"))))
        (expect (null candidate) :to-be-falsy)
        (expect "release service" :to-equal (nshell.domain.completion:candidate-description candidate)))))

  (it "path-command-completion-merges-with-kb-and-path-candidates"
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
          (expect '("cd" "complete" "contains" "count" "cargo" "cat") :to-equal texts)))))

  (it "command-completion-ranks-exact-match-first"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "git")
      (nshell.domain.completion:kb-add-command kb "gitk")
      (nshell.domain.completion:kb-add-command kb "gist")
      (let ((texts (completion-texts
                    (nshell.domain.completion:complete kb "git"))))
        (expect '("git" "gitk") :to-equal texts))))

  (it "command-completion-ranks-case-sensitive-prefix-before-case-folded-match"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "ZZCase-tool")
      (nshell.domain.completion:kb-add-command kb "zzcase-tool")
      (let ((texts (completion-texts
                    (nshell.domain.completion:complete kb "zzcase"))))
        (expect '("zzcase-tool" "ZZCase-tool") :to-equal texts))))

  (it "command-completion-keeps-best-duplicate-metadata"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "tool" :description "managed command")
      (with-path-command-adapters
          ((lambda (directory)
             (declare (ignore directory))
             (list #p"/mock/tool"))
           (constantly t))
        (let ((candidates (nshell.domain.completion:complete kb "to" :path "/mock")))
          (expect 1 :to-equal (length candidates))
          (expect "tool" :to-equal (nshell.domain.completion:candidate-text (first candidates)))
          (expect "managed command" :to-equal (nshell.domain.completion:candidate-description
                        (first candidates)))))))

  (it "path-command-completion-ignores-argument-position"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-path-command-adapters
          ((lambda (directory)
             (declare (ignore directory))
             (list #p"/mock/git"))
           (constantly t))
        (expect (nshell.domain.completion:complete kb "echo g" :path "/mock") :to-be-null))))

  (it "path-command-completion-skips-directory-prefixed-commands"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-path-command-adapters
          ((lambda (directory)
             (declare (ignore directory))
             (list #p"/mock/git"))
           (constantly t))
        (expect (nshell.domain.completion:complete kb "./g" :path "/mock") :to-be-null))))

  (it "unique-string-values-deduplicates-preserving-first-occurrence"
    "unique-string-values keeps first occurrence and drops later duplicates."
    (flet ((uniq (&rest vals)
             (nshell.domain.completion::%unique-string-values vals)))
      (expect (uniq) :to-be-null)
      (expect '("a") :to-equal (uniq "a" "a" "a"))
      (expect '("a" "b" "c") :to-equal (uniq "a" "b" "a" "c" "b"))))

  (it "merge-string-values-combines-and-deduplicates"
    "merge-string-values appends two lists and deduplicates."
    (flet ((merge* (a b)
             (nshell.domain.completion::%merge-string-values a b)))
      (expect (merge* nil nil) :to-be-null)
      (expect '("a" "b") :to-equal (merge* nil '("a" "b")))
      (expect '("a" "b" "c") :to-equal (merge* '("a" "b") '("b" "c")))))

  (it "merge-kb-command-facts-preserves-and-merges-entry-policy"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :subcommands '("run")
       :flags '("--mode")
       :option-values '(("--mode" "fast"))
       :exclusive-options '(("--json" "--yaml"))
       :description "catalog")
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :subcommands '("test" "run")
       :flags '("--mode" "--verbose")
       :option-values '(("--mode" "safe" "fast")
                        ("--format" "json"))
       :exclusive-options '(("--json" "--yaml")
                            ("--compact" "--pretty")))
      (expect '("run" "test") :to-equal (nshell.domain.completion:kb-command-subcommands kb "tool"))
      (expect '("--mode" "--verbose") :to-equal (nshell.domain.completion:kb-command-flags kb "tool"))
      (expect '(("--format" "json")
                   ("--mode" "fast" "safe")) :to-equal (nshell.domain.completion:kb-command-option-values kb "tool"))
      (expect '(("--json" "--yaml")
                   ("--compact" "--pretty")) :to-equal (nshell.domain.completion:kb-command-exclusive-options
                  kb "tool"))
      (expect "catalog" :to-equal (nshell.domain.completion:kb-command-description
                    kb "tool"))))

  (it "merge-kb-command-facts-updates-description-when-present"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "tool" :description "catalog")
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :description "dynamic loader")
      (expect "dynamic loader" :to-equal (nshell.domain.completion:kb-command-description
                    kb "tool"))))

  (it "add-kb-command-entry-option-merges-through-entry-boundary"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :flags '("--mode")
       :option-values '(("--mode" "fast")))
      (nshell.domain.completion:kb-add-option
       kb "tool" "--mode" :values '("safe" "fast"))
      (expect '("--mode") :to-equal (nshell.domain.completion:kb-command-flags kb "tool"))
      (expect '(("--mode" "fast" "safe")) :to-equal (nshell.domain.completion:kb-command-option-values
                  kb "tool"))))

  (it "completion-help-command-facts-are-private-values"
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

  (it "add-command-from-help-projects-help-facts-through-public-kb-api"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command-from-help
       kb "tool"
       (format nil "Commands:~%  run   execute the tool~%  test  verify behavior~%~%  --format=(json|yaml)~%  --verbose~%  --mode=(fast|safe)")
       :description "parsed help")
      (expect '("run" "test") :to-equal (nshell.domain.completion:kb-command-subcommands kb "tool"))
      (expect '("--format" "--verbose" "--mode") :to-equal (nshell.domain.completion:kb-command-flags kb "tool"))
      (expect '(("--format" "json" "yaml")
                   ("--mode" "fast" "safe")) :to-equal (nshell.domain.completion:kb-command-option-values kb "tool"))
      (expect "parsed help" :to-equal (nshell.domain.completion:kb-command-description
                    kb "tool"))))

  (it "knowledge-base-query-api-does-not-expose-entry-plist"
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
      (expect (nshell.domain.completion:kb-command-present-p kb "tool") :to-be-truthy)
      (expect (nshell.domain.completion:kb-command-present-p kb "missing") :to-be-falsy)
      (expect '("run") :to-equal (nshell.domain.completion:kb-command-subcommands kb "tool"))
      (expect '("--mode") :to-equal (nshell.domain.completion:kb-command-flags kb "tool"))
      (expect '(("--mode" "fast")) :to-equal (nshell.domain.completion:kb-command-option-values kb "tool"))
      (expect '(("--json" "--yaml")) :to-equal (nshell.domain.completion:kb-command-exclusive-options
                  kb "tool"))
      (expect "tool command" :to-equal (nshell.domain.completion:kb-command-description
                    kb "tool"))))

  (it "normalize-kb-exclusive-option-groups-filters-singletons-and-deduplicates"
    "normalize drops singleton groups and deduplicates values within each group."
    (flet ((norm (groups)
             (nshell.domain.completion::%normalize-kb-exclusive-option-groups groups)))
      (expect (norm nil) :to-be-null)
      ;; singleton ("--a") is dropped; ("--a" "--b") is kept
      (expect '(("--a" "--b")) :to-equal (norm '(("--a" "--b") ("--a"))))
      ;; duplicates within group: ("--c" "--d" "--c") → ("--c" "--d")
      (expect '(("--c" "--d")) :to-equal (norm '(("--c" "--d" "--c")))))))
