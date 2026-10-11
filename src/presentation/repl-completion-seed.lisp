;;; REPL completion seed data
(in-package #:nshell.presentation)

;;; Keep process I/O outside the domain by supplying Git-backed hooks
;;; for completion requests that carry the current directory.

(defun %seed-git-branch-lister (directory)
  (multiple-value-bind (output exit-code)
      (nshell.infrastructure.acl:%run-git
       directory '("for-each-ref" "--format=%(refname:short)" "refs/heads/"))
    (when (zerop exit-code)
      (nshell.domain.completion:%git-output-lines output))))

(defun %seed-git-modified-path-lister (directory)
  (multiple-value-bind (output exit-code)
      (nshell.infrastructure.acl:%run-git
       directory '("status" "--porcelain" "--untracked-files=no"))
    (when (zerop exit-code)
      (nshell.domain.completion:%git-porcelain-status-paths output))))

(defun seed-repl-completion-knowledge-base (knowledge-base)
  (setf nshell.domain.completion:*git-branch-lister* (function %seed-git-branch-lister)
        nshell.domain.completion:*git-modified-path-lister* (function %seed-git-modified-path-lister))
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
