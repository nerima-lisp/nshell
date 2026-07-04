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
    (is (not (fboundp 'nshell.domain.completion::make-catalog-command-projection)))
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
  "Catalog-derived-data helpers should not leave unprefixed compatibility symbols."
  (labels ((defined-symbol-p (name)
             (multiple-value-bind (symbol status)
                 (find-symbol name "NSHELL.DOMAIN.COMPLETION")
               (and status (fboundp symbol)))))
    (dolist (old-name '("CATALOG-SUBCOMMAND-NAME"
                        "CATALOG-SUBCOMMAND-DESCRIPTION"
                        "CATALOG-COMMAND"
                        "CATALOG-DESCRIPTION"
                        "CATALOG-SYNOPSIS"
                        "CATALOG-SUBCOMMANDS"
                        "CATALOG-FLAGS"
                        "CATALOG-OPTION-VALUES"
                        "CATALOG-EXCLUSIVE-OPTIONS"
                        "CATALOG-COMMAND-PROJECTION-P"
                        "CATALOG-COMMAND-PROJECTION-COMMAND"
                        "CATALOG-COMMAND-PROJECTION-DESCRIPTION"
                        "CATALOG-COMMAND-PROJECTION-SYNOPSIS"
                        "CATALOG-COMMAND-PROJECTION-SUBCOMMANDS"
                        "CATALOG-COMMAND-PROJECTION-FLAGS"
                        "CATALOG-COMMAND-PROJECTION-OPTION-VALUES"
                        "CATALOG-COMMAND-PROJECTION-EXCLUSIVE-OPTIONS"
                        "CATALOG-ENTRY-COMMAND-PROJECTION"
                        "CATALOG-COMMAND-PROJECTIONS"
                        "CATALOG-COMMAND-FACT"
                        "CATALOG-DESCRIPTION-FACT"
                        "CATALOG-FLAG-FACTS"
                        "CATALOG-SUBCOMMAND-COMPLETION-FACTS"
                        "CATALOG-SUBCOMMAND-DESCRIPTION-FACTS"
                        "CATALOG-COMMAND-RULE-FACTS"
                        "CATALOG-COMMAND-WITH-SUBCOMMAND-RULE-FACTS"
                        "CATALOG-HELP-ENTRY"
                        "CATALOG-COMPLETION-METADATA"
                        "CATALOG-COMPLETION-COMMAND-SPEC"
                        "BUILTIN-COMMAND-FLAG-FACTS"
                        "EXTERNAL-COMMAND-RULE-FACTS"
                        "COMPLETION-COMMAND-SPECS-FROM-CATALOG"))
      (is (not (defined-symbol-p old-name))))
    (dolist (internal-name '("%CATALOG-SUBCOMMAND-NAME"
                             "%CATALOG-SUBCOMMAND-DESCRIPTION"
                             "%CATALOG-COMMAND"
                             "%CATALOG-DESCRIPTION"
                             "%CATALOG-SYNOPSIS"
                             "%CATALOG-SUBCOMMANDS"
                             "%CATALOG-FLAGS"
                             "%CATALOG-OPTION-VALUES"
                             "%CATALOG-EXCLUSIVE-OPTIONS"
                             "%CATALOG-COMMAND-PROJECTION-P"
                             "%CATALOG-COMMAND-PROJECTION-COMMAND"
                             "%CATALOG-COMMAND-PROJECTION-DESCRIPTION"
                             "%CATALOG-COMMAND-PROJECTION-SYNOPSIS"
                             "%CATALOG-COMMAND-PROJECTION-SUBCOMMANDS"
                             "%CATALOG-COMMAND-PROJECTION-FLAGS"
                             "%CATALOG-COMMAND-PROJECTION-OPTION-VALUES"
                             "%CATALOG-COMMAND-PROJECTION-EXCLUSIVE-OPTIONS"
                             "%CATALOG-ENTRY-COMMAND-PROJECTION"
                             "%CATALOG-COMMAND-PROJECTIONS"
                             "%CATALOG-COMMAND-FACT"
                             "%CATALOG-DESCRIPTION-FACT"
                             "%CATALOG-FLAG-FACTS"
                             "%CATALOG-SUBCOMMAND-COMPLETION-FACTS"
                             "%CATALOG-SUBCOMMAND-DESCRIPTION-FACTS"
                             "%CATALOG-COMMAND-RULE-FACTS"
                             "%CATALOG-COMMAND-WITH-SUBCOMMAND-RULE-FACTS"
                             "%CATALOG-HELP-ENTRY"
                             "%CATALOG-COMPLETION-METADATA"
                             "%CATALOG-COMPLETION-COMMAND-SPEC"
                             "%BUILTIN-COMMAND-FLAG-FACTS"
                             "%EXTERNAL-COMMAND-RULE-FACTS"
                             "%COMPLETION-COMMAND-SPECS-FROM-CATALOG"))
      (is (defined-symbol-p internal-name)))))

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
      (let ((flags-projection
            (nshell.domain.completion::%project-catalog-source-entry-property
             source-entry :flags))
          (synopsis-projection
            (nshell.domain.completion::%project-catalog-source-entry-property
             source-entry :synopsis)))
      (is (eq :flags
              (nshell.domain.completion::%catalog-entry-property-projection-key
               flags-projection)))
      (is (nshell.domain.completion::%catalog-entry-property-projection-present-p
           flags-projection))
      (is (not (nshell.domain.completion::%catalog-entry-property-projection-present-p
                synopsis-projection)))
      (is (null (nshell.domain.completion::%catalog-entry-property-projection-value
                 flags-projection))))
    (is (equal '(:synopsis :description :subcommands :flags :option-values :exclusive-options)
               (nshell.domain.completion::%command-catalog-preserved-properties)))))

(test command-catalog-static-helper-boundaries-are-internal
  "Static catalog helpers should only exist behind percent-prefixed boundaries."
  (labels ((defined-symbol-p (name)
             (multiple-value-bind (symbol status)
                 (find-symbol name "NSHELL.DOMAIN.COMPLETION")
               (and status (or (fboundp symbol)
                               (ignore-errors
                                (typep (symbol-value symbol) 'function)))))))
    (dolist (old-name '("CATALOG-ENTRY-PROPERTY-PROJECTION"
                        "MAKE-CATALOG-ENTRY-PROPERTY-PROJECTION"
                        "CATALOG-ENTRY-PROPERTY-PROJECTION-KEY"
                        "CATALOG-ENTRY-PROPERTY-PROJECTION-VALUE"
                        "CATALOG-ENTRY-PROPERTY-PROJECTION-PRESENT-P"
                        "CATALOG-ENTRY-PROPERTY-PRESENT-P"
                        "CATALOG-ENTRY-PROPERTY-VALUE"
                        "CATALOG-ENTRY-COMMAND"
                        "COMMAND-CATALOG-PRESERVED-PROPERTIES"
                        "CATALOG-ENTRY-PROPERTY"
                        "COMMAND-CATALOG-ENTRY"
                        "%PROJECT-CATALOG-ENTRY-PROPERTY"
                        "%CATALOG-ENTRY-PROPERTY-PRESENT-P"
                        "%CATALOG-ENTRY-PROPERTY"
                        "%COMMAND-CATALOG-ENTRY"
                        "COMMAND-CATALOG"))
      (is (not (defined-symbol-p old-name))))
    (dolist (internal-name '("%MAKE-CATALOG-ENTRY-PROPERTY-PROJECTION"
                             "%CATALOG-ENTRY-PROPERTY-PROJECTION-P"
                        "%CATALOG-ENTRY-PROPERTY-PROJECTION-KEY"
                        "%CATALOG-ENTRY-PROPERTY-PROJECTION-VALUE"
                        "%CATALOG-ENTRY-PROPERTY-PROJECTION-PRESENT-P"
                        "%PROJECT-CATALOG-SOURCE-ENTRY-PROPERTY"
                        "%CATALOG-ENTRY-PROPERTY-VALUE"
                        "%CATALOG-SOURCE-ENTRY-PROPERTY-PRESENT-P"
                        "%CATALOG-SOURCE-ENTRY-PROPERTY-VALUE"
                             "%CATALOG-SOURCE-ENTRY-PROPERTY"
                             "%CATALOG-SOURCE-ENTRY-COMMAND"
                             "%CATALOG-COMMAND-ENTRY-P"
                             "%CATALOG-COMMAND-ENTRY-COMMAND"
                             "%CATALOG-COMMAND-ENTRY-SYNOPSIS"
                             "%CATALOG-COMMAND-ENTRY-DESCRIPTION"
                             "%CATALOG-COMMAND-ENTRY-SUBCOMMANDS"
                             "%CATALOG-COMMAND-ENTRY-FLAGS"
                             "%CATALOG-COMMAND-ENTRY-OPTION-VALUES"
                             "%CATALOG-COMMAND-ENTRY-EXCLUSIVE-OPTIONS"
                             "%CATALOG-ENTRY-COMMAND"
                             "%COMMAND-CATALOG-PRESERVED-PROPERTIES"
                             "%BUILD-COMMAND-CATALOG-ENTRY"
                             "%COMMAND-CATALOG"))
      (is (defined-symbol-p internal-name)))
    (is (not (fboundp 'nshell.domain.completion::%catalog-entry-property-key)))))

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
