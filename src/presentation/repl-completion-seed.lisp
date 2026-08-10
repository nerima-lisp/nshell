;;; REPL completion seed data
(in-package #:nshell.presentation)

(defun seed-repl-completion-knowledge-base (knowledge-base)
  (dolist (spec (append (nshell.domain.completion:builtin-completion-command-specs)
                        (nshell.domain.completion:external-completion-command-specs)
                        (nshell.domain.completion:external-subcommand-completion-command-specs))
                knowledge-base)
    (destructuring-bind (command &key subcommands flags option-values option-value-kinds
                         exclusive-options description &allow-other-keys)
        spec
      (nshell.domain.completion:kb-add-command knowledge-base command
                                               :subcommands subcommands
                                               :flags flags
                                               :option-values option-values
                                               :option-value-kinds option-value-kinds
                                               :exclusive-options exclusive-options
                                               :description description))))
