(in-package #:nshell.domain.completion)
(defstruct (knowledge-base
            (:constructor %make-knowledge-base ())
            (:conc-name %knowledge-base-))
  (commands (make-hash-table :test #'equal) :type hash-table))

(defstruct (%kb-command-entry
            (:constructor %make-kb-command-entry
                (&key subcommands flags option-values exclusive-options
                      description))
            (:conc-name %kb-command-entry-))
  (subcommands nil :type list)
  (flags nil :type list)
  (option-values nil :type list)
  (exclusive-options nil :type list)
  description)

(defun make-empty-knowledge-base ()
  (%make-knowledge-base))

(defun %map-kb-commands (kb function)
  (dolist (cmd-name (sort (loop for key being the hash-keys of (%knowledge-base-commands kb)
                                collect key)
                          #'string<))
    (funcall function cmd-name (gethash cmd-name (%knowledge-base-commands kb)))))

(defun %ensure-kb-command-entry (kb cmd-name)
  (or (gethash cmd-name (%knowledge-base-commands kb))
      (setf (gethash cmd-name (%knowledge-base-commands kb))
            (%make-kb-command-entry))))

(defun %unique-string-values (values)
  (let ((seen nil)
        (result nil))
    (dolist (value values (nreverse result))
      (when (and (stringp value)
                 (not (member value seen :test #'string=)))
        (push value seen)
        (push value result)))))

(defun %kb-option-value-spec-option (spec)
  (and (consp spec)
       (first spec)))

(defun %kb-option-value-spec-values (spec)
  (if (consp spec)
      (rest spec)
      nil))

(defun %valid-kb-option-value-spec-p (spec)
  (stringp (%kb-option-value-spec-option spec)))

(defun %kb-option-value-spec-for-option-p (spec opt-name)
  (and (%valid-kb-option-value-spec-p spec)
       (string= opt-name (%kb-option-value-spec-option spec))))

(defun %make-kb-option-value-spec (opt-name values)
  (cons opt-name values))

(defun %merge-kb-option-values (option-values opt-name values)
  (let ((merged-values nil)
        (other-specs nil))
    (dolist (spec option-values)
      (if (%kb-option-value-spec-for-option-p spec opt-name)
          (setf merged-values
                (append merged-values (%kb-option-value-spec-values spec)))
          (push spec other-specs)))
    (cons (%make-kb-option-value-spec
           opt-name
           (%unique-string-values
            (append merged-values values)))
          (nreverse other-specs))))

(defun %merge-string-values (existing incoming)
  (%unique-string-values (append existing incoming)))

(defun %merge-kb-option-value-specs (existing incoming)
  (let ((merged existing))
    (dolist (spec incoming merged)
      (when (%valid-kb-option-value-spec-p spec)
        (setf merged (%merge-kb-option-values merged
                                              (%kb-option-value-spec-option spec)
                                              (%kb-option-value-spec-values spec)))))))

(defun %normalize-kb-exclusive-option-groups (groups)
  (let ((normalized nil))
    (dolist (group groups (nreverse normalized))
      (let ((options (%unique-string-values group)))
        (when (rest options)
          (push options normalized))))))

(defun %merge-kb-exclusive-option-groups (existing incoming)
  (let ((seen nil)
        (merged nil))
    (dolist (group (append existing
                           (%normalize-kb-exclusive-option-groups incoming))
             (nreverse merged))
      (when (and (consp group)
                 (not (member group seen :test #'equal)))
        (push group seen)
        (push group merged)))))

(defun %kb-command-entry (kb cmd-name)
  (and kb (gethash cmd-name (%knowledge-base-commands kb))))

(defun kb-command-present-p (kb cmd-name)
  (not (null (%kb-command-entry kb cmd-name))))

(defmacro %define-kb-command-accessor (name accessor)
  `(defun ,name (kb cmd-name)
     (let ((entry (%kb-command-entry kb cmd-name)))
       (and entry
            (,accessor entry)))))

(%define-kb-command-accessor kb-command-subcommands
  %kb-command-entry-subcommands)
(%define-kb-command-accessor kb-command-flags
  %kb-command-entry-flags)
(%define-kb-command-accessor kb-command-option-values
  %kb-command-entry-option-values)
(%define-kb-command-accessor kb-command-exclusive-options
  %kb-command-entry-exclusive-options)
(%define-kb-command-accessor kb-command-description
  %kb-command-entry-description)

(defun %merge-kb-command-entry-facts
    (entry &key subcommands flags option-values exclusive-options description)
  (setf (%kb-command-entry-subcommands entry)
        (%merge-string-values (%kb-command-entry-subcommands entry)
                                 subcommands)
        (%kb-command-entry-flags entry)
        (%merge-string-values (%kb-command-entry-flags entry) flags)
        (%kb-command-entry-option-values entry)
        (%merge-kb-option-value-specs (%kb-command-entry-option-values entry)
                                      option-values)
        (%kb-command-entry-exclusive-options entry)
        (%merge-kb-exclusive-option-groups
         (%kb-command-entry-exclusive-options entry)
         exclusive-options)
        (%kb-command-entry-description entry)
        (or description (%kb-command-entry-description entry)))
  entry)

(defun %add-kb-command-entry-option (entry opt-name values)
  (%merge-kb-command-entry-facts
   entry
   :flags (list opt-name)
   :option-values (when values
                    (list (%make-kb-option-value-spec opt-name values)))))

(defun %merge-kb-command-facts
    (entry &key subcommands flags option-values exclusive-options description)
  (%merge-kb-command-entry-facts
   entry
   :subcommands subcommands
   :flags flags
   :option-values option-values
   :exclusive-options exclusive-options
   :description description))

(defun kb-add-command
    (kb cmd-name &key subcommands flags option-values exclusive-options description)
  (let ((entry (%ensure-kb-command-entry kb cmd-name)))
    (%merge-kb-command-facts entry
                             :subcommands subcommands
                             :flags flags
                             :option-values option-values
                             :exclusive-options exclusive-options
                             :description description)))

(defun kb-add-option (kb cmd-name opt-name &key values)
  (let ((entry (%ensure-kb-command-entry kb cmd-name)))
    (%add-kb-command-entry-option entry opt-name values)))

(defun kb-remove-command (kb cmd-name)
  (remhash cmd-name (%knowledge-base-commands kb)))
