(in-package #:nshell.application)

(nshell.util:define-value-struct %complete-parse-state
    ((command nil)
     (flags nil :copy :list)
     (long-options nil :copy :list)
     (short-options nil :copy :list)
     (arguments nil :copy :list)
     (description nil)
     (erase nil))
  :constructor %allocate-complete-parse-state
  :public-accessors nil)

(defun %make-complete-parse-state ()
  (%allocate-complete-parse-state nil nil nil nil nil nil nil))

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
             (host-kit:split-string arguments
                                    :separator (list #\Space #\Tab #\Newline))))

(defun %complete-apply-option-value (spec state value)
  (ecase (getf spec :kind)
    (:command
     (%allocate-complete-parse-state
      value
      (%complete-parse-state-flags state)
      (%complete-parse-state-long-options state)
      (%complete-parse-state-short-options state)
      (%complete-parse-state-arguments state)
      (%complete-parse-state-description state)
      (%complete-parse-state-erase state)))
    (:flag
     (%allocate-complete-parse-state
      (%complete-parse-state-command state)
      (cons value (%complete-parse-state-flags state))
      (%complete-parse-state-long-options state)
      (%complete-parse-state-short-options state)
      (%complete-parse-state-arguments state)
      (%complete-parse-state-description state)
      (%complete-parse-state-erase state)))
    (:long-option
     (%allocate-complete-parse-state
      (%complete-parse-state-command state)
      (%complete-parse-state-flags state)
      (cons (%complete-long-option-name value)
            (%complete-parse-state-long-options state))
      (%complete-parse-state-short-options state)
      (%complete-parse-state-arguments state)
      (%complete-parse-state-description state)
      (%complete-parse-state-erase state)))
    (:short-option
     (%allocate-complete-parse-state
      (%complete-parse-state-command state)
      (%complete-parse-state-flags state)
      (%complete-parse-state-long-options state)
      (cons (%complete-short-option-name value)
            (%complete-parse-state-short-options state))
      (%complete-parse-state-arguments state)
      (%complete-parse-state-description state)
      (%complete-parse-state-erase state)))
    (:arguments
     (%allocate-complete-parse-state
      (%complete-parse-state-command state)
      (%complete-parse-state-flags state)
      (%complete-parse-state-long-options state)
      (%complete-parse-state-short-options state)
      (append (%complete-parse-state-arguments state)
              (%complete-argument-values value))
      (%complete-parse-state-description state)
      (%complete-parse-state-erase state)))
    (:description
     (%allocate-complete-parse-state
      (%complete-parse-state-command state)
      (%complete-parse-state-flags state)
      (%complete-parse-state-long-options state)
      (%complete-parse-state-short-options state)
      (%complete-parse-state-arguments state)
      value
      (%complete-parse-state-erase state)))
    (:erase
     (%allocate-complete-parse-state
      (%complete-parse-state-command state)
      (%complete-parse-state-flags state)
      (%complete-parse-state-long-options state)
      (%complete-parse-state-short-options state)
      (%complete-parse-state-arguments state)
      (%complete-parse-state-description state)
      t))))

(defun %complete-apply-option (spec remaining state)
  (let ((value (second remaining)))
    (values (%complete-apply-option-value spec state value)
            (if (eq (getf spec :kind) :erase)
                (cdr remaining)
                (cddr remaining)))))

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

(defun %complete-state->values (state)
  (values (%complete-parse-state-command state)
          (%complete-parse-state-flags state)
          (%complete-parse-state-long-options state)
          (%complete-parse-state-short-options state)
          (%complete-parse-state-arguments state)
          (%complete-parse-state-description state)
          (%complete-parse-state-erase state)))

(defun %complete-parse-error (message)
  (values nil nil nil nil nil nil nil message))

(defun %parse-complete-args (args)
  (labels ((unknown-option (option)
             (%complete-parse-error
              (format nil "complete: unknown option ~a" option)))
           (missing-argument (option spec)
             (%complete-parse-error
              (%required-argument-error "complete"
                                        option
                                        (getf spec :requirement))))
           (finalize (state)
             (multiple-value-bind (command flags long-options short-options
                                   arguments description erase)
                 (%complete-state->values state)
               (values command
                       (nreverse flags)
                       (nreverse long-options)
                       (nreverse short-options)
                       arguments
                       description
                       erase
                       nil)))
           (parse (remaining state)
             (if (endp remaining)
                 (finalize state)
                 (let ((option (first remaining)))
                   (cond
                     ((string= option "--")
                      (finalize state))
                     ((%builtin-option-like-p option)
                      (let ((spec (%complete-option-spec option)))
                        (if spec
                            (if (or (null (getf spec :requirement))
                                    (rest remaining))
                                (multiple-value-bind (next-state next-remaining)
                                    (%complete-apply-option spec remaining state)
                                  (parse next-remaining next-state))
                                (missing-argument option spec))
                            (unknown-option option))))
                     (t
                      (finalize state)))))))
    (parse args (%make-complete-parse-state))))

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
