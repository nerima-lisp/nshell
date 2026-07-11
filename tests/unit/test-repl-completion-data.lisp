(in-package #:nshell/test)

(in-suite repl-tests)

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
    (is (not (null help-entry)))
    (is (not (null repl-entry)))
    (is (string= (nshell.domain.completion::%catalog-command-entry-synopsis entry)
                 (getf help-entry :synopsis))
        command)
    (is (string= (nshell.domain.completion::%catalog-command-entry-description entry)
                 (getf help-entry :description))
        command)
    (is (string= (nshell.domain.completion::%catalog-command-entry-description entry)
                 (getf (rest repl-entry) :description))
        command)
    (is (equal (nshell.domain.completion::%catalog-command-entry-flags entry)
               (getf (rest repl-entry) :flags))
        command)
    (is (equal (nshell.domain.completion::%catalog-command-entry-option-values entry)
               (getf (rest repl-entry) :option-values))
        command)
    (is (equal (nshell.domain.completion::%catalog-command-entry-exclusive-options entry)
               (getf (rest repl-entry) :exclusive-options))
        command)))

(defun %assert-builtin-catalog-alignment (catalog help-entries repl-specs)
  (is (equal (%builtin-entry-commands catalog)
             (%builtin-entry-commands help-entries)))
  (is (equal (%builtin-entry-commands catalog)
             (mapcar #'first repl-specs)))
  (dolist (entry catalog)
    (let* ((command (%builtin-entry-command entry))
           (help-entry (%builtin-entry-by-command command help-entries))
           (repl-entry (%builtin-entry-by-command command repl-specs :command-fn #'first)))
      (%assert-builtin-projection entry help-entry repl-entry))))

(test repl-command-specs-are-unique
  "The REPL completion seed data should not define the same command twice."
  (let* ((commands (mapcar #'first (%repl-completion-command-specs)))
         (unique-commands (remove-duplicates commands :test #'string=)))
    (is (= (length commands) (length unique-commands)))))

(test repl-command-specs-track-builtin-help
  "The REPL completion seed should stay aligned with the canonical builtin completion helper."
  (is (equal (%repl-completion-command-specs)
             (nshell.domain.completion:builtin-completion-command-specs)))
  (let ((help-commands (%builtin-entry-commands
                        (nshell.domain.completion:builtin-help-entries))))
    (is (equal help-commands
               (mapcar #'first (%repl-completion-command-specs))))))

(test builtin-catalog-projects-into-help-and-repl-seed
  "The canonical builtin catalog should project into help entries and REPL seed data without drift."
  (%assert-builtin-catalog-alignment
   nshell.domain.completion::+builtin-command-catalog+
   (nshell.domain.completion:builtin-help-entries)
   (%repl-completion-command-specs)))

(test catalog-command-spec-projects-completion-metadata
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
    (is (equal "zz" (first spec)))
    (is (equal '("run" "test") (getf (rest spec) :subcommands)))
    (is (equal '("--mode" "--json" "--yaml") (getf (rest spec) :flags)))
    (is (equal '(("--mode" "fast" "safe"))
               (getf (rest spec) :option-values)))
    (is (equal '(("--json" "--yaml"))
               (getf (rest spec) :exclusive-options)))
    (is (string= "synthetic command"
                 (getf (rest spec) :description)))))

(test catalog-command-projection-boundary-feeds-all-derived-data
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
    (is (equal "zz"
               (nshell.domain.completion::%catalog-command-projection-command
                projection)))
    (assert-package-function-boundaries
        :package "NSHELL.DOMAIN.COMPLETION"
        :absent (nshell.domain.completion::make-catalog-command-projection))
    (is (equal '("run" (:name "test" :description "run tests"))
               (nshell.domain.completion::%catalog-command-projection-subcommands
                projection)))
    (is (equal '(:command "zz"
                 :synopsis "zz [subcommand]"
                 :description "synthetic command")
               (nshell.domain.completion::%catalog-help-entry projection)))
    (is (equal '("zz"
                 :subcommands ("run" "test")
                 :flags ("--mode")
                 :option-values (("--mode" "fast" "safe"))
                 :exclusive-options (("--json" "--yaml"))
                 :description "synthetic command")
               (nshell.domain.completion::%catalog-completion-command-spec
                projection)))
    (is (equal '((nshell.domain.completion::completes "zz" "zz")
                 (nshell.domain.completion::describes "zz" "synthetic command")
                 (nshell.domain.completion::completes "zz" "run")
                 (nshell.domain.completion::completes "zz" "test")
                 (nshell.domain.completion::describes "test" "run tests")
                 (nshell.domain.completion::has-flag "zz" "--mode"))
               (nshell.domain.completion::%catalog-command-with-subcommand-rule-facts
                projection)))))

(test catalog-derived-data-helpers-are-internal-boundaries
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

(test command-catalog-entry-projection-boundaries-separate-source-plists-from-entries
  "Static catalog normalization should parse source plists into private catalog entries."
  (let* ((source-entry (list :command "zz"
                            :description "synthetic command"
                            :flags nil
                            :option-values nil))
         (entry (first (nshell.domain.completion::%command-catalog
                        (list source-entry)))))
    (is (equal "zz" (nshell.domain.completion::%catalog-entry-command entry)))
    (is (nshell.domain.completion::%catalog-command-entry-p entry))
    (is (not (listp entry)))
    (is (not (fboundp 'nshell.domain.completion::make-catalog-command-entry)))
    (is (nshell.domain.completion::%catalog-source-entry-property-present-p
         source-entry :flags))
    (is (nshell.domain.completion::%catalog-source-entry-property-present-p
         source-entry :option-values))
    (is (equal (list :flags nil)
               (nshell.domain.completion::%catalog-source-entry-property
                source-entry :flags)))
    (multiple-value-bind (key value present-p)
        (nshell.domain.completion::%catalog-source-entry-property-values
         source-entry :flags)
      (is (eq :flags key))
      (is (not (null present-p)))
      (is (null value)))
    (multiple-value-bind (key value present-p)
        (nshell.domain.completion::%catalog-source-entry-property-values
         source-entry :synopsis)
      (is (eq :synopsis key))
      (is (not present-p))
      (is (null value)))))

(test command-catalog-static-helper-boundaries-are-internal
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

(test pbt-builtin-catalog-projects-into-help-and-repl-seed
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

(test repl-command-data-seeds-completion-knowledge-base
  "REPL completion command data is converted into command and flag facts."
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.presentation::seed-repl-completion-knowledge-base kb)
    (let ((command-texts (completion-texts
                          (nshell.domain.completion:complete kb "a"))))
      (is (member "abbr" command-texts :test #'string=))
      (is (member "alias" command-texts :test #'string=)))
    (is (member "type"
                (completion-texts
                 (nshell.domain.completion:complete kb "ty"))
                :test #'string=))
    (is (member "--query"
                (completion-texts
                 (nshell.domain.completion:complete kb "type --"))
                :test #'string=))
    (is (member "-t"
                (completion-texts
                 (nshell.domain.completion:complete kb "type -"))
                :test #'string=))
    (is (member "-q"
                (completion-texts
                 (nshell.domain.completion:complete kb "abbr -"))
                :test #'string=))
    (is (member "--show"
                (completion-texts
                 (nshell.domain.completion:complete kb "abbr --"))
                :test #'string=))
    (is (member "-x"
                (completion-texts
                 (nshell.domain.completion:complete kb "set -"))
                :test #'string=))
    (is (member "--query"
                (completion-texts
                 (nshell.domain.completion:complete kb "set --"))
                :test #'string=))
    (is (member "replace"
                (completion-texts
                 (nshell.domain.completion:complete kb "string r"))
                :test #'string=))
    (is (member "--all"
                (completion-texts
                 (nshell.domain.completion:complete kb "string --"))
                :test #'string=))))

(test repl-completion-seeds-common-external-command-metadata
  "Completion-only external command data should seed REPL command, subcommand, and flag facts."
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.presentation::seed-repl-completion-knowledge-base kb)
    (let ((kubectl (completion-candidate-by-text
                    "kubectl"
                    (nshell.domain.completion:complete kb "ku"))))
      (is (not (null kubectl)))
      (is (string= "control Kubernetes clusters"
                   (nshell.domain.completion:candidate-description kubectl))))
    (is (member "switch"
                (completion-texts
                 (nshell.domain.completion:complete kb "git sw"))
                :test #'string=))
    (is (member "pr"
                (completion-texts
                 (nshell.domain.completion:complete kb "gh pr"))
                :test #'string=))
    (is (member "--tls"
                (completion-texts
                 (nshell.domain.completion:complete kb "docker --t"))
                :test #'string=))
    (is (member "--request"
                (completion-texts
                 (nshell.domain.completion:complete kb "curl --req"))
                :test #'string=))
    (is (member "--color"
                (completion-texts
                 (nshell.domain.completion:complete kb "rg --colo"))
                :test #'string=))))

(test type-command-flags-follow-the-catalog
  "The type command should expose every catalogued flag through REPL completion."
  (let* ((type-entry (find "type"
                           nshell.domain.completion::+builtin-command-catalog+
                           :key #'nshell.domain.completion::%catalog-command-entry-command
                           :test #'string=))
         (kb (nshell.domain.completion:make-empty-knowledge-base)))
    (is (not (null type-entry))
        "type entry should exist in the builtin command catalog")
    (nshell.presentation::seed-repl-completion-knowledge-base kb)
    (let ((short-candidates (completion-texts
                             (nshell.domain.completion:complete kb "type -")))
          (long-candidates (completion-texts
                            (nshell.domain.completion:complete kb "type --"))))
      (dolist (flag (nshell.domain.completion::%catalog-command-entry-flags type-entry))
        (is (member flag (if (and (>= (length flag) 2)
                                  (char= #\- (char flag 0))
                                  (char= #\- (char flag 1)))
                             long-candidates
                             short-candidates)
                    :test #'string=)
            flag)))))
