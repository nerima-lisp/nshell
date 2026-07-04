(in-package #:nshell.application)

(defparameter +complete-option-specs+
  '(("-c" :kind :command :requirement "command")
    ("--command" :kind :command :requirement "command")
    ("-f" :kind :flag :requirement "flag")
    ("--flag" :kind :flag :requirement "flag")
    ("-l" :kind :long-option :requirement "option")
    ("--long-option" :kind :long-option :requirement "option")
    ("-s" :kind :short-option :requirement "option")
    ("--short-option" :kind :short-option :requirement "option")
    ("-a" :kind :arguments :requirement "arguments")
    ("--arguments" :kind :arguments :requirement "arguments")
    ("-d" :kind :description :requirement "description")
    ("--description" :kind :description :requirement "description")
    ("-e" :kind :erase)
    ("--erase" :kind :erase)))

(defun %complete-option-spec (option)
  (cdr (assoc option +complete-option-specs+ :test #'string=)))

(defun %complete-long-option-name (option)
  (if (and (>= (length option) 2)
           (string= option "--" :end1 2))
      option
      (concatenate 'string "--" option)))

(defun %complete-short-option-name (option)
  (if (and (plusp (length option))
           (char= (char option 0) #\-))
      option
      (concatenate 'string "-" option)))

(defun %complete-argument-values (arguments)
  (remove-if (lambda (value) (string= value ""))
             (uiop:split-string arguments
                                :separator (list #\Space #\Tab #\Newline))))

(defun %complete-apply-option
    (spec remaining command flags long-options short-options arguments description erase)
  (ecase (getf spec :kind)
    (:command
     (values (second remaining) flags long-options short-options arguments description
             erase (cddr remaining)))
    (:flag
     (values command (cons (second remaining) flags) long-options short-options
             arguments description erase (cddr remaining)))
    (:long-option
     (values command flags (cons (%complete-long-option-name (second remaining))
                                 long-options)
             short-options arguments description erase (cddr remaining)))
    (:short-option
     (values command flags long-options
             (cons (%complete-short-option-name (second remaining)) short-options)
             arguments description erase (cddr remaining)))
    (:arguments
     (values command flags long-options short-options
             (append arguments (%complete-argument-values (second remaining)))
             description erase (cddr remaining)))
    (:description
     (values command flags long-options short-options arguments (second remaining)
             erase (cddr remaining)))
    (:erase
     (values command flags long-options short-options arguments description
             t (cdr remaining)))))

(defun %complete-merge-strings (new existing)
  (remove-duplicates (append (or new nil) (or existing nil))
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

(defun %parse-complete-args (args)
  (let ((command nil)
        (flags nil)
        (long-options nil)
        (short-options nil)
        (arguments nil)
        (description nil)
        (erase nil)
        (remaining args))
    (%with-option-arguments (remaining option)
          (return)
        (return-from %parse-complete-args
              (values nil nil nil nil nil nil nil
                      (format nil "complete: unknown option ~a" option)))
      (return)
      ((%complete-option-spec option)
            (let ((spec (%complete-option-spec option)))
              (if (or (null (getf spec :requirement))
                      (rest remaining))
                  (multiple-value-bind
                        (new-command new-flags new-long-options new-short-options
                         new-arguments new-description new-erase new-remaining)
                      (%complete-apply-option spec remaining command flags
                                              long-options short-options arguments
                                              description erase)
                    (setf command new-command
                          flags new-flags
                          long-options new-long-options
                          short-options new-short-options
                          arguments new-arguments
                          description new-description
                          erase new-erase
                          remaining new-remaining))
                  (return-from %parse-complete-args
                    (values nil nil nil nil nil nil nil
                            (%required-argument-error "complete"
                                                      option
                                                      (getf spec :requirement))))))))
        (values command
                (nreverse flags)
                (nreverse long-options)
                (nreverse short-options)
                arguments
                description
                erase
                nil)))

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
        "complete -c command [-f flag ...] [-l option ...] [-s option ...] [-a arguments] [-d description] [-e]"))
      (erase
       (nshell.domain.completion:kb-remove-command
        (shell-context-knowledge-base context)
        command)
       (values nil 0))
      (t
       (let* ((kb (shell-context-knowledge-base context))
              (option-flags (append long-options short-options))
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
          :description (or description existing-description))
         (values nil 0))))))
