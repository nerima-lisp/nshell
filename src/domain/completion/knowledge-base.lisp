(in-package #:nshell.domain.completion)
(defstruct (knowledge-base
            (:constructor %make-knowledge-base ())
            (:conc-name %knowledge-base-))
  (commands (make-hash-table :test #'equal) :type hash-table))

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

(defstruct (kb-option-value-spec-projection
            (:constructor %make-kb-option-value-spec-projection
                (option values valid-p)))
  option
  values
  valid-p)

(defun %kb-option-value-spec-projection (spec)
  (if (consp spec)
      (%make-kb-option-value-spec-projection
       (first spec)
       (rest spec)
       (stringp (first spec)))
      (%make-kb-option-value-spec-projection nil nil nil)))

(defun %kb-option-value-spec-option (spec)
  (kb-option-value-spec-projection-option
   (%kb-option-value-spec-projection spec)))

(defun %kb-option-value-spec-values (spec)
  (kb-option-value-spec-projection-values
   (%kb-option-value-spec-projection spec)))

(defun %valid-kb-option-value-spec-p (spec)
  (kb-option-value-spec-projection-valid-p
   (%kb-option-value-spec-projection spec)))

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
           (%unique-kb-string-values
            (append merged-values values)))
          (nreverse other-specs))))

(defun %merge-kb-string-values (existing incoming)
  (%unique-kb-string-values (append existing incoming)))

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

(defun %kb-command-entry-subcommands (entry)
  (getf entry :subcommands))

(defun %kb-command-entry-flags (entry)
  (getf entry :flags))

(defun %kb-command-entry-option-values (entry)
  (getf entry :option-values))

(defun %kb-command-entry-exclusive-options (entry)
  (getf entry :exclusive-options))

(defun %kb-command-entry-description (entry)
  (getf entry :description))

(defun %kb-command-entry (kb cmd-name)
  (and kb (gethash cmd-name (%knowledge-base-commands kb))))

(defun kb-command-present-p (kb cmd-name)
  (not (null (%kb-command-entry kb cmd-name))))

(defun kb-command-subcommands (kb cmd-name)
  (%kb-command-entry-subcommands (%kb-command-entry kb cmd-name)))

(defun kb-command-flags (kb cmd-name)
  (%kb-command-entry-flags (%kb-command-entry kb cmd-name)))

(defun kb-command-option-values (kb cmd-name)
  (%kb-command-entry-option-values (%kb-command-entry kb cmd-name)))

(defun kb-command-exclusive-options (kb cmd-name)
  (%kb-command-entry-exclusive-options (%kb-command-entry kb cmd-name)))

(defun kb-command-description (kb cmd-name)
  (%kb-command-entry-description (%kb-command-entry kb cmd-name)))

(defun %merge-kb-command-entry-facts
    (entry &key subcommands flags option-values exclusive-options description)
  (setf (getf entry :subcommands)
        (%merge-kb-string-values (%kb-command-entry-subcommands entry)
                                 subcommands)
        (getf entry :flags)
        (%merge-kb-string-values (%kb-command-entry-flags entry) flags)
        (getf entry :option-values)
        (%merge-kb-option-value-specs (%kb-command-entry-option-values entry)
                                      option-values)
        (getf entry :exclusive-options)
        (%merge-kb-exclusive-option-groups
         (%kb-command-entry-exclusive-options entry)
         exclusive-options)
        (getf entry :description)
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

(defun %completion-help-lines (text)
  (let ((lines nil)
        (start 0)
        (length (length text)))
    (loop
      for position = (position #\Newline text :start start)
      do (let ((end (or position length)))
           (push (subseq text start end) lines))
      while position
      do (setf start (1+ position)))
    (nreverse lines)))

(defun %completion-help-token-delimiter-p (char)
  (find char '(#\Space #\Tab #\, #\; #\) #\( #\[ #\] #\{ #\})))

(defun %completion-help-option-end (line start)
  (or (position-if #'%completion-help-token-delimiter-p line :start start)
      (length line)))

(defun %completion-help-clean-option-token (token)
  (let* ((trimmed (string-trim '(#\Space #\Tab #\, #\; #\. #\: #\) #\( #\[ #\] #\{ #\})
                               token))
         (equals-position (position #\= trimmed)))
    (if equals-position
        (subseq trimmed 0 equals-position)
        trimmed)))

(defun %completion-help-option-token-p (token)
  (and (stringp token)
       (< 1 (length token))
       (char= (char token 0) #\-)
       (not (string= token "-"))
       (not (string= token "--"))))

(defun %completion-help-options-in-line (line)
  (let ((options nil)
        (start 0)
        (length (length line)))
    (loop while (< start length)
          for position = (position #\- line :start start)
          while position
          do (let* ((end (%completion-help-option-end line position))
                    (token (%completion-help-clean-option-token
                            (subseq line position end))))
               (when (%completion-help-option-token-p token)
                 (push token options))
               (setf start (max (1+ position) end))))
    (%unique-kb-string-values (nreverse options))))

(defun %completion-split-on-char (text delimiter)
  (let ((parts nil)
        (start 0)
        (length (length text)))
    (loop
      for position = (position delimiter text :start start)
      do (let ((end (or position length)))
           (push (subseq text start end) parts))
      while position
      do (setf start (1+ position)))
    (nreverse parts)))

(defun %completion-help-enum-value-p (value)
  (and (< 0 (length value))
       (not (position-if (lambda (char)
                           (find char '(#\Space #\Tab #\Newline #\Return)))
                         value))))

(defun %completion-help-enum-values (line)
  (let ((open-position (position #\( line)))
    (when open-position
      (let ((close-position (position #\) line :start (1+ open-position))))
        (when close-position
          (let ((content (subseq line (1+ open-position) close-position)))
            (when (position #\| content)
              (let ((values (remove-if-not
                             #'%completion-help-enum-value-p
                             (mapcar (lambda (value)
                                       (string-trim '(#\Space #\Tab #\' #\") value))
                                      (%completion-split-on-char content #\|)))))
                 (when values values)))))))))

(defun %completion-help-option-value-specs (options values)
  (when values
    (loop for option in options
          when (starts-with-p "--" option)
            collect (%make-kb-option-value-spec option values))))

(defun %completion-help-command-facts (help-text)
  (let ((flags nil)
        (option-values nil))
    (dolist (line (%completion-help-lines help-text))
      (let* ((options (%completion-help-options-in-line line))
             (values (%completion-help-enum-values line)))
        (setf flags (append flags options)
              option-values
              (append option-values
                      (%completion-help-option-value-specs options values)))))
    (list :flags (%unique-kb-string-values flags)
          :option-values option-values)))

(defun kb-add-command-from-help (kb cmd-name help-text &key description)
  "Add command completion metadata by parsing already-fetched help text."
  (let ((facts (%completion-help-command-facts help-text)))
    (kb-add-command kb cmd-name
                    :flags (getf facts :flags)
                    :option-values (getf facts :option-values)
                    :description description)))

(defun kb-remove-command (kb cmd-name)
  (remhash cmd-name (%knowledge-base-commands kb)))
