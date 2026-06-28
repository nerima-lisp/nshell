(in-package #:nshell.domain.completion)
(defstruct (knowledge-base (:constructor make-knowledge-base ()))
  (commands (make-hash-table :test #'equal) :type hash-table))

(defun %ensure-kb-command-entry (kb cmd-name)
  (or (gethash cmd-name (knowledge-base-commands kb))
      (setf (gethash cmd-name (knowledge-base-commands kb))
	            (list :subcommands nil
	                  :flags nil
	                  :option-values nil
	                  :exclusive-options nil
	                  :description nil))))

(defun %unique-kb-string-values (values)
  (let ((seen nil)
        (result nil))
    (dolist (value values (nreverse result))
      (when (and (stringp value)
                 (not (member value seen :test #'string=)))
        (push value seen)
        (push value result)))))

(defun %merge-kb-option-values (option-values opt-name values)
  (let ((merged-values nil)
        (other-specs nil))
    (dolist (spec option-values)
      (if (and (consp spec)
               (stringp (first spec))
               (string= opt-name (first spec)))
          (setf merged-values (append merged-values (rest spec)))
          (push spec other-specs)))
    (cons (cons opt-name
                (%unique-kb-string-values
                 (append merged-values values)))
          (nreverse other-specs))))

(defun %merge-kb-string-values (existing incoming)
  (%unique-kb-string-values (append existing incoming)))

(defun %merge-kb-option-value-specs (existing incoming)
  (let ((merged existing))
    (dolist (spec incoming merged)
      (when (and (consp spec)
	                 (stringp (first spec)))
        (setf merged (%merge-kb-option-values merged
                                              (first spec)
                                              (rest spec)))))))

(defun %normalize-kb-exclusive-option-groups (groups)
  (let ((normalized nil))
    (dolist (group groups (nreverse normalized))
      (let ((options (%unique-kb-string-values group)))
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

(defun kb-add-command
    (kb cmd-name &key subcommands flags option-values exclusive-options description)
  (let ((entry (%ensure-kb-command-entry kb cmd-name)))
    (setf (getf entry :subcommands)
          (%merge-kb-string-values (getf entry :subcommands) subcommands)
          (getf entry :flags)
          (%merge-kb-string-values (getf entry :flags) flags)
          (getf entry :option-values)
          (%merge-kb-option-value-specs (getf entry :option-values) option-values)
          (getf entry :exclusive-options)
          (%merge-kb-exclusive-option-groups (getf entry :exclusive-options)
                                             exclusive-options)
          (getf entry :description)
          (or description (getf entry :description)))
    entry))

(defun kb-add-option (kb cmd-name opt-name &key values)
  (let ((entry (%ensure-kb-command-entry kb cmd-name)))
    (pushnew opt-name (getf entry :flags) :test #'string=)
    (when values
      (setf (getf entry :option-values)
            (%merge-kb-option-values (getf entry :option-values)
                                     opt-name
                                     values)))))

(defun kb-remove-command (kb cmd-name)
  (remhash cmd-name (knowledge-base-commands kb)))

(defun kb-query (kb cmd-name)
  (gethash cmd-name (knowledge-base-commands kb)))
