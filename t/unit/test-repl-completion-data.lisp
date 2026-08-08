(in-package #:nshell/test)

(defun %builtin-entry-command (entry)
  (if (nshell.domain.completion::%catalog-command-entry-p entry)
      (nshell.domain.completion::%catalog-command-entry-command entry)
      (getf entry :command)))

(defun %builtin-entry-by-command (command entries &key (command-fn #'%builtin-entry-command))
  (find command entries
        :key command-fn
        :test #'string=))

(defun %builtin-entry-commands (entries &key (command-fn #'%builtin-entry-command))
  (mapcar command-fn entries))

(defun %repl-completion-command-specs ()
  (nshell.domain.completion:builtin-completion-command-specs))

(defun %assert-builtin-projection (entry help-entry repl-entry)
  (let ((command (%builtin-entry-command entry)))
    (expect (null help-entry) :to-be-falsy)
    (expect (null repl-entry) :to-be-falsy)
    (expect (nshell.domain.completion::%catalog-command-entry-synopsis entry) :to-equal (getf help-entry :synopsis))
    (expect (nshell.domain.completion::%catalog-command-entry-description entry) :to-equal (getf help-entry :description))
    (expect (nshell.domain.completion::%catalog-command-entry-description entry) :to-equal (getf (rest repl-entry) :description))
    (expect (nshell.domain.completion::%catalog-command-entry-flags entry) :to-equal (getf (rest repl-entry) :flags))
    (expect (nshell.domain.completion::%catalog-command-entry-option-values entry) :to-equal (getf (rest repl-entry) :option-values))
    (expect (nshell.domain.completion::%catalog-command-entry-exclusive-options entry) :to-equal (getf (rest repl-entry) :exclusive-options))))

(defun %assert-builtin-catalog-alignment (catalog help-entries repl-specs)
  (expect (%builtin-entry-commands catalog) :to-equal (%builtin-entry-commands help-entries))
  (expect (%builtin-entry-commands catalog) :to-equal (mapcar #'first repl-specs))
  (dolist (entry catalog)
    (let* ((command (%builtin-entry-command entry))
           (help-entry (%builtin-entry-by-command command help-entries))
           (repl-entry (%builtin-entry-by-command command repl-specs :command-fn #'first)))
      (%assert-builtin-projection entry help-entry repl-entry))))

(describe "repl-tests"
  (it "repl-command-specs-are-unique"
    "The REPL completion seed data should not define the same command twice."
    (let* ((commands (mapcar #'first (%repl-completion-command-specs)))
           (unique-commands (remove-duplicates commands :test #'string=)))
      (expect (length commands) :to-equal (length unique-commands))))

  (it "repl-command-specs-track-builtin-help"
    "The REPL completion seed should stay aligned with the canonical builtin completion helper."
    (expect (%repl-completion-command-specs) :to-equal (nshell.domain.completion:builtin-completion-command-specs))
    (let ((help-commands (%builtin-entry-commands
                          (nshell.domain.completion:builtin-help-entries))))
      (expect help-commands :to-equal (mapcar #'first (%repl-completion-command-specs)))))

  (it "builtin-catalog-projects-into-help-and-repl-seed"
    "The canonical builtin catalog should project into help entries and REPL seed data without drift."
    (%assert-builtin-catalog-alignment
     nshell.domain.completion::+builtin-command-catalog+
     (nshell.domain.completion:builtin-help-entries)
     (%repl-completion-command-specs)))

  (it "catalog-command-spec-projects-completion-metadata"
    "Catalog rows should project option metadata into REPL completion specs without knowledge-base involvement."
    (let* ((catalog (nshell.domain.completion::%command-catalog
                     (list (list :command "zz"
                                 :description "synthetic command"
                                 :subcommands (list "run"
                                                    (list :name "test"
                                                          :description "run tests"))
                                 :flags '("--mode" "--json" "--yaml")
                                 :option-values '(("--mode" "fast" "safe"))
                                 :exclusive-options '(("--json" "--yaml"))))))
           (spec (first (nshell.domain.completion::%completion-command-specs-from-catalog
                         catalog))))
      (expect "zz" :to-equal (first spec))
      (expect '("run" "test") :to-equal (getf (rest spec) :subcommands))
      (expect '("--mode" "--json" "--yaml") :to-equal (getf (rest spec) :flags))
      (expect '(("--mode" "fast" "safe")) :to-equal (getf (rest spec) :option-values))
      (expect '(("--json" "--yaml")) :to-equal (getf (rest spec) :exclusive-options))
      (expect "synthetic command" :to-equal (getf (rest spec) :description))))

  (it "catalog-command-projection-boundary-feeds-all-derived-data"
    "Catalog rows should be converted once before deriving help entries, completion specs, and rule facts."
    (let* ((entry (first
                   (nshell.domain.completion::%command-catalog
                    (list (list :command "zz"
                                :synopsis "zz [subcommand]"
                                :description "synthetic command"
                                :subcommands (list "run"
                                                   (list :name "test"
                                                         :description "run tests"))
                                :flags '("--mode")
                                :option-values '(("--mode" "fast" "safe"))
                                :exclusive-options '(("--json" "--yaml")))))))
           (projection (nshell.domain.completion::%catalog-entry-command-projection
                        entry)))
      (expect "zz" :to-equal (nshell.domain.completion::%catalog-command-projection-command
                  projection))
      (assert-package-function-boundaries
          :package "NSHELL.DOMAIN.COMPLETION"
          :absent (nshell.domain.completion::make-catalog-command-projection))
      (expect '("run" (:name "test" :description "run tests")) :to-equal (nshell.domain.completion::%catalog-command-projection-subcommands
                  projection))
      (expect '(:command "zz"
                   :synopsis "zz [subcommand]"
                   :description "synthetic command") :to-equal (nshell.domain.completion::%catalog-help-entry projection))
      (expect '("zz"
                   :subcommands ("run" "test")
                   :flags ("--mode")
                   :option-values (("--mode" "fast" "safe"))
                   :exclusive-options (("--json" "--yaml"))
                   :description "synthetic command") :to-equal (nshell.domain.completion::%catalog-completion-command-spec
                  projection))
      (expect '((nshell.domain.completion::completes "zz" "zz")
                   (nshell.domain.completion::describes "zz" "synthetic command")
                   (nshell.domain.completion::completes "zz" "run")
                   (nshell.domain.completion::completes "zz" "test")
                   (nshell.domain.completion::describes "test" "run tests")
                   (nshell.domain.completion::has-flag "zz" "--mode")
                   (nshell.domain.completion::option-value "zz" "--mode" "fast")
                   (nshell.domain.completion::option-value "zz" "--mode" "safe")
                   (nshell.domain.completion::exclusive-group "zz" ("--json" "--yaml"))) :to-equal (nshell.domain.completion::%catalog-command-with-subcommand-rule-facts
                  projection))))

  (it "catalog-derived-data-helpers-are-internal-boundaries"
    "Catalog-derived-data helpers should not leave unprefixed legacy symbols."
    (assert-package-symbol-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :absent (nshell.domain.completion::catalog-subcommand-name
                 nshell.domain.completion::catalog-subcommand-description
                 nshell.domain.completion::catalog-command
                 nshell.domain.completion::catalog-description
                 nshell.domain.completion::catalog-synopsis
                 nshell.domain.completion::catalog-subcommands
                 nshell.domain.completion::catalog-flags
                 nshell.domain.completion::catalog-option-values
                 nshell.domain.completion::catalog-exclusive-options
                 nshell.domain.completion::catalog-command-projection-p
                 nshell.domain.completion::catalog-command-projection-command
                 nshell.domain.completion::catalog-command-projection-description
                 nshell.domain.completion::catalog-command-projection-synopsis
                 nshell.domain.completion::catalog-command-projection-subcommands
                 nshell.domain.completion::catalog-command-projection-flags
                 nshell.domain.completion::catalog-command-projection-option-values
                 nshell.domain.completion::catalog-command-projection-exclusive-options
                 nshell.domain.completion::catalog-entry-command-projection
                 nshell.domain.completion::catalog-command-projections
                 nshell.domain.completion::catalog-command-fact
                 nshell.domain.completion::catalog-description-fact
                 nshell.domain.completion::catalog-flag-facts
                 nshell.domain.completion::catalog-subcommand-completion-facts
                 nshell.domain.completion::catalog-subcommand-description-facts
                 nshell.domain.completion::catalog-command-rule-facts
                 nshell.domain.completion::catalog-command-with-subcommand-rule-facts
                 nshell.domain.completion::catalog-help-entry
                 nshell.domain.completion::catalog-completion-metadata
                 nshell.domain.completion::catalog-completion-command-spec
                 nshell.domain.completion::builtin-command-flag-facts
                 nshell.domain.completion::external-command-rule-facts
                 nshell.domain.completion::completion-command-specs-from-catalog))
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :present (nshell.domain.completion::%catalog-subcommand-name
                  nshell.domain.completion::%catalog-subcommand-description
                  nshell.domain.completion::%catalog-command
                  nshell.domain.completion::%catalog-description
                  nshell.domain.completion::%catalog-synopsis
                  nshell.domain.completion::%catalog-subcommands
                  nshell.domain.completion::%catalog-flags
                  nshell.domain.completion::%catalog-option-values
                  nshell.domain.completion::%catalog-exclusive-options
                  nshell.domain.completion::%catalog-command-projection-p
                  nshell.domain.completion::%catalog-command-projection-command
                  nshell.domain.completion::%catalog-command-projection-description
                  nshell.domain.completion::%catalog-command-projection-synopsis
                  nshell.domain.completion::%catalog-command-projection-subcommands
                  nshell.domain.completion::%catalog-command-projection-flags
                  nshell.domain.completion::%catalog-command-projection-option-values
                  nshell.domain.completion::%catalog-command-projection-exclusive-options
                  nshell.domain.completion::%catalog-entry-command-projection
                  nshell.domain.completion::%catalog-command-projections
                  nshell.domain.completion::%catalog-command-fact
                  nshell.domain.completion::%catalog-description-fact
                  nshell.domain.completion::%catalog-flag-facts
                  nshell.domain.completion::%catalog-subcommand-completion-facts
                  nshell.domain.completion::%catalog-subcommand-description-facts
                  nshell.domain.completion::%catalog-command-rule-facts
                  nshell.domain.completion::%catalog-command-with-subcommand-rule-facts
                  nshell.domain.completion::%catalog-help-entry
                  nshell.domain.completion::%catalog-completion-metadata
                  nshell.domain.completion::%catalog-completion-command-spec
                  nshell.domain.completion::%builtin-command-flag-facts
                  nshell.domain.completion::%external-command-rule-facts
                  nshell.domain.completion::%completion-command-specs-from-catalog)))

  (it "command-catalog-entry-projection-boundaries-separate-source-plists-from-entries"
    "Static catalog normalization should parse source plists into private catalog entries."
    (let* ((source-entry (list :command "zz"
                              :description "synthetic command"
                              :flags nil
                              :option-values nil))
           (entry (first (nshell.domain.completion::%command-catalog
                          (list source-entry)))))
      (expect "zz" :to-equal (nshell.domain.completion::%catalog-entry-command entry))
      (expect (nshell.domain.completion::%catalog-command-entry-p entry) :to-be-truthy)
      (expect (listp entry) :to-be-falsy)
      (expect (fboundp 'nshell.domain.completion::make-catalog-command-entry) :to-be-falsy)
      (expect (nshell.domain.completion::%catalog-source-entry-property-present-p
           source-entry :flags) :to-be-truthy)
      (expect (nshell.domain.completion::%catalog-source-entry-property-present-p
           source-entry :option-values) :to-be-truthy)
      (expect (list :flags nil) :to-equal (nshell.domain.completion::%catalog-source-entry-property
                  source-entry :flags))
      (multiple-value-bind (key value present-p)
          (nshell.domain.completion::%catalog-source-entry-property-values
           source-entry :flags)
        (expect :flags :to-be key)
        (expect (null present-p) :to-be-falsy)
        (expect value :to-be-null))
      (multiple-value-bind (key value present-p)
          (nshell.domain.completion::%catalog-source-entry-property-values
           source-entry :synopsis)
        (expect :synopsis :to-be key)
        (expect present-p :to-be-falsy)
        (expect value :to-be-null))))

  (it "command-catalog-static-helper-boundaries-are-internal"
    "Static catalog helpers should only exist behind percent-prefixed boundaries."
    (assert-package-symbol-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :absent (nshell.domain.completion::catalog-entry-property-projection
                 nshell.domain.completion::make-catalog-entry-property-projection
                 nshell.domain.completion::catalog-entry-property-projection-key
                 nshell.domain.completion::catalog-entry-property-projection-value
                 nshell.domain.completion::catalog-entry-property-projection-present-p
                 nshell.domain.completion::catalog-entry-property-present-p
                 nshell.domain.completion::catalog-entry-property-value
                 nshell.domain.completion::catalog-entry-command
                 nshell.domain.completion::command-catalog-preserved-properties
                 nshell.domain.completion::catalog-entry-property
                 nshell.domain.completion::command-catalog-entry
                 nshell.domain.completion::project-catalog-entry-property
                 nshell.domain.completion::catalog-entry-property-present-p
                 nshell.domain.completion::catalog-entry-property
                 nshell.domain.completion::command-catalog-entry
                 nshell.domain.completion::command-catalog))
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :present (nshell.domain.completion::%catalog-source-entry-property-values
                  nshell.domain.completion::%catalog-entry-property-value
                  nshell.domain.completion::%catalog-source-entry-property-present-p
                  nshell.domain.completion::%catalog-source-entry-property-value
                  nshell.domain.completion::%catalog-source-entry-property
                  nshell.domain.completion::%catalog-source-entry-command
                  nshell.domain.completion::%catalog-command-entry-p
                  nshell.domain.completion::%catalog-command-entry-command
                  nshell.domain.completion::%catalog-command-entry-synopsis
                  nshell.domain.completion::%catalog-command-entry-description
                  nshell.domain.completion::%catalog-command-entry-subcommands
                  nshell.domain.completion::%catalog-command-entry-flags
                  nshell.domain.completion::%catalog-command-entry-option-values
                  nshell.domain.completion::%catalog-command-entry-exclusive-options
                  nshell.domain.completion::%catalog-entry-command
                  nshell.domain.completion::%build-command-catalog-entry
                  nshell.domain.completion::%command-catalog)
        :absent (nshell.domain.completion::%catalog-entry-property-key
                 nshell.domain.completion::%catalog-entry-property-projection
                 nshell.domain.completion::%make-catalog-entry-property-projection
                 nshell.domain.completion::%catalog-entry-property-projection-key
                 nshell.domain.completion::%catalog-entry-property-projection-value
                 nshell.domain.completion::%catalog-entry-property-projection-present-p
                 nshell.domain.completion::%project-catalog-source-entry-property
                 nshell.domain.completion::%command-catalog-preserved-properties)))

  (it "pbt-builtin-catalog-projects-into-help-and-repl-seed"
    "Each builtin catalog entry should project consistently into help and REPL seed data."
    (let ((catalog nshell.domain.completion::+builtin-command-catalog+)
          (help-entries (nshell.domain.completion:builtin-help-entries))
          (repl-specs (%repl-completion-command-specs)))
      (check-property (:trials 50)
          ((index (gen-in-range 0 (1- (length catalog))) nil))
        (let ((entry (nth index catalog)))
          (and entry
               (let* ((command (%builtin-entry-command entry))
                      (help-entry (%builtin-entry-by-command command help-entries))
                      (repl-entry (%builtin-entry-by-command command repl-specs :command-fn #'first)))
                 (and help-entry
                      repl-entry
                      (progn
                        (%assert-builtin-projection entry help-entry repl-entry)
                        t))))))))

  (it "repl-command-data-seeds-completion-knowledge-base"
    "REPL completion command data is converted into command and flag facts."
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.presentation::seed-repl-completion-knowledge-base kb)
      (let ((command-texts (completion-texts
                            (nshell.domain.completion:complete kb "a"))))
        (expect (member "abbr" command-texts :test #'string=) :to-be-truthy)
        (expect (member "alias" command-texts :test #'string=) :to-be-truthy))
      (expect (member "type"
                  (completion-texts
                   (nshell.domain.completion:complete kb "ty"))
                  :test #'string=) :to-be-truthy)
      (expect (member "--query"
                  (completion-texts
                   (nshell.domain.completion:complete kb "type --"))
                  :test #'string=) :to-be-truthy)
      (expect (member "-t"
                  (completion-texts
                   (nshell.domain.completion:complete kb "type -"))
                  :test #'string=) :to-be-truthy)
      (expect (member "-q"
                  (completion-texts
                   (nshell.domain.completion:complete kb "abbr -"))
                  :test #'string=) :to-be-truthy)
      (expect (member "--show"
                  (completion-texts
                   (nshell.domain.completion:complete kb "abbr --"))
                  :test #'string=) :to-be-truthy)
      (expect (member "-x"
                  (completion-texts
                   (nshell.domain.completion:complete kb "set -"))
                  :test #'string=) :to-be-truthy)
      (expect (member "--query"
                  (completion-texts
                   (nshell.domain.completion:complete kb "set --"))
                  :test #'string=) :to-be-truthy)
      (expect (member "replace"
                  (completion-texts
                   (nshell.domain.completion:complete kb "string r"))
                  :test #'string=) :to-be-truthy)
      (expect (member "--all"
                  (completion-texts
                   (nshell.domain.completion:complete kb "string --"))
                  :test #'string=) :to-be-truthy)))

  (it "repl-completion-seeds-common-external-command-metadata"
    "Completion-only external command data should seed REPL command, subcommand, and flag facts."
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.presentation::seed-repl-completion-knowledge-base kb)
      (let ((kubectl (completion-candidate-by-text
                      "kubectl"
                      (nshell.domain.completion:complete kb "ku"))))
        (expect (null kubectl) :to-be-falsy)
        (expect "control Kubernetes clusters" :to-equal (nshell.domain.completion:candidate-description kubectl)))
      (expect (member "switch"
                  (completion-texts
                   (nshell.domain.completion:complete kb "git sw"))
                  :test #'string=) :to-be-truthy)
      (expect (member "pr"
                  (completion-texts
                   (nshell.domain.completion:complete kb "gh pr"))
                  :test #'string=) :to-be-truthy)
      (expect (member "--tls"
                  (completion-texts
                   (nshell.domain.completion:complete kb "docker --t"))
                  :test #'string=) :to-be-truthy)
      (expect (member "--request"
                  (completion-texts
                   (nshell.domain.completion:complete kb "curl --req"))
                  :test #'string=) :to-be-truthy)
      (expect (member "--color"
                  (completion-texts
                   (nshell.domain.completion:complete kb "rg --colo"))
                  :test #'string=) :to-be-truthy)))

  (it "repl-completion-seeds-expanded-external-subcommand-metadata"
    "Curated nested command metadata should be available without executing help."
    (with-seeded-completion-knowledge-base (kb)
      (assert-completion-texts-cases kb
        (:input "git diff --stage" :expected ("--staged"))
        (:input "docker compose u" :expected ("up"))
        (:input "docker compose up --d" :expected ("--detach"))
        (:input "kubectl apply --dr" :expected ("--dry-run")))))

  (it "type-command-flags-follow-the-catalog"
    "The type command should expose every catalogued flag through REPL completion."
    (let* ((type-entry (find "type"
                             nshell.domain.completion::+builtin-command-catalog+
                             :key #'nshell.domain.completion::%catalog-command-entry-command
                             :test #'string=))
           (kb (nshell.domain.completion:make-empty-knowledge-base)))
      (expect (null type-entry) :to-be-falsy)
      (nshell.presentation::seed-repl-completion-knowledge-base kb)
      (let ((short-candidates (completion-texts
                               (nshell.domain.completion:complete kb "type -")))
            (long-candidates (completion-texts
                              (nshell.domain.completion:complete kb "type --"))))
        (dolist (flag (nshell.domain.completion::%catalog-command-entry-flags type-entry))
          (expect (member flag (if (and (>= (length flag) 2)
                                    (char= #\- (char flag 0))
                                    (char= #\- (char flag 1)))
                               long-candidates
                               short-candidates)
                      :test #'string=) :to-be-truthy))))))
