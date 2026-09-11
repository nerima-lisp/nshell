(in-package #:nshell.application)

(defun %complete-merge-strings (new existing)
  (remove-duplicates (append new existing)
                     :test #'string=))

(defun %complete-option-values-for (option-values option)
  (cdr (assoc option option-values :test #'string=)))

(defun %complete-merge-option-values (existing options values)
  (if (or (null options) (null values))
      existing
      (let ((merged existing))
        (dolist (option options merged)
          (setf merged
                (acons option
                       (%complete-merge-strings
                        values
                        (%complete-option-values-for merged option))
                       (remove option merged
                               :key #'first
                               :test #'string=)))))))

(defun %complete-ensure-knowledge-base (context)
  "Return CONTEXT's completion knowledge base, lazily creating one when the
session has none -- batch mode (`nshell -c ...`) never seeds *KB*, so without
this `complete -c ...` would call KB-ADD-COMMAND/KB-REMOVE-COMMAND on NIL and
crash instead of registering the completion, the same class of non-interactive
gap as the NIL history in builtin-commands-history.lisp."
  (or (shell-context-knowledge-base context)
      (setf (shell-context-knowledge-base context)
            (nshell.domain.completion:make-empty-knowledge-base))))

(defun %complete-do-complete (context line)
  "Print each completion candidate for LINE on its own line (fish's `complete
-C`, the scriptable completion entry point). A NIL knowledge base falls back
to PATH/filesystem candidates rather than crashing -- see the TYPECASE in
%COMPLETION-CANDIDATES (candidate-routing.lisp) -- so no lazy KB creation is
needed here the way the mutating `-c`/`-e` paths below need one."
  (let* ((environment (shell-context-environment context))
         (path (and environment (nshell.domain.environment:env-get environment "PATH")))
         (candidates (nshell.domain.completion:complete
                      (shell-context-knowledge-base context)
                      line
                      :path path
                      :filesystem (shell-context-filesystem context)
                      :alias-table (shell-context-alias-table context)
                      :function-table (shell-context-function-table context))))
    (values (when candidates
              (format nil "~{~a~%~}"
                      (mapcar #'nshell.domain.completion:candidate-text candidates)))
            0)))

(defun %complete-upsert-command (kb command flags long-options short-options arguments description)
  (let* ((option-flags (append long-options short-options))
         (generic-arguments (and (null option-flags) arguments))
         (merged-subcommands
           (%complete-merge-strings
            generic-arguments
            (nshell.domain.completion:kb-command-subcommands kb command)))
         (merged-flags
           (%complete-merge-strings (append flags option-flags)
                                    (nshell.domain.completion:kb-command-flags
                                     kb command)))
         (merged-option-values
           (%complete-merge-option-values
            (nshell.domain.completion:kb-command-option-values kb command)
            option-flags
            arguments))
         (existing-description
           (nshell.domain.completion:kb-command-description kb command)))
    (nshell.domain.completion:kb-add-command
     kb command
     :subcommands merged-subcommands
     :flags merged-flags
     :option-values merged-option-values
     :description (or description existing-description))))

(defun %builtin-complete (context args)
  (if (and args (member (first args) '("-C" "--do-complete") :test #'string=))
      (if (rest args)
          (%complete-do-complete context (second args))
          (values (%required-argument-error "complete" (first args) "a line") 2))
      (multiple-value-bind
            (command flags long-options short-options arguments description erase error)
          (%parse-complete-args args)
        (cond
          (error
           (values error 2))
          ((null command)
           (%builtin-usage
            "complete"
            ;; Assembled rather than written as one literal: the synopsis is longer
            ;; than 100 columns and a string cannot be split across source lines.
            (concatenate 'string
                         "complete -c command [-f flag ...] [-l option ...]"
                         " [-s option ...] [-a arguments] [-d description] [-e]"
                         " | complete -C line")))
          (erase
           (nshell.domain.completion:kb-remove-command
            (%complete-ensure-knowledge-base context)
            command)
           (values nil 0))
          (t
           (%complete-upsert-command (%complete-ensure-knowledge-base context)
                                     command
                                     flags
                                     long-options
                                     short-options
                                     arguments
                                     description)
           (values nil 0))))))
