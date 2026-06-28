(in-package #:nshell/test)

(in-suite repl-tests)

(defun %builtin-entry-command (entry)
  (getf entry :command))

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
    (is (string= (getf entry :synopsis)
                 (getf help-entry :synopsis))
        command)
    (is (string= (getf entry :description)
                 (getf help-entry :description))
        command)
    (is (string= (getf entry :description)
                 (getf (rest repl-entry) :description))
        command)
    (is (equal (getf entry :flags)
               (getf (rest repl-entry) :flags))
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
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
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
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
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
    (is (member "--tls"
                (completion-texts
                 (nshell.domain.completion:complete kb "docker --t"))
                :test #'string=))))

(test type-command-flags-follow-the-catalog
  "The type command should expose every catalogued flag through REPL completion."
  (let* ((type-entry (find "type"
                           nshell.domain.completion::+builtin-command-catalog+
                           :key (lambda (entry) (getf entry :command))
                           :test #'string=))
         (kb (nshell.domain.completion:make-knowledge-base)))
    (is (not (null type-entry))
        "type entry should exist in the builtin command catalog")
    (nshell.presentation::seed-repl-completion-knowledge-base kb)
    (let ((short-candidates (completion-texts
                             (nshell.domain.completion:complete kb "type -")))
          (long-candidates (completion-texts
                            (nshell.domain.completion:complete kb "type --"))))
      (dolist (flag (getf type-entry :flags))
        (is (member flag (if (and (>= (length flag) 2)
                                  (char= #\- (char flag 0))
                                  (char= #\- (char flag 1)))
                             long-candidates
                             short-candidates)
                    :test #'string=)
            flag)))))
