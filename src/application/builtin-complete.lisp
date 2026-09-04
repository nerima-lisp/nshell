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
                     " [-s option ...] [-a arguments] [-d description] [-e]")))
      (erase
       (nshell.domain.completion:kb-remove-command
        (shell-context-knowledge-base context)
        command)
       (values nil 0))
      (t
       (%complete-upsert-command (shell-context-knowledge-base context)
                                 command
                                 flags
                                 long-options
                                 short-options
                                 arguments
                                 description)
       (values nil 0)))))
