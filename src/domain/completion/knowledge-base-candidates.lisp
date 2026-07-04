(in-package #:nshell.domain.completion)

(defparameter +option-value-candidate-description+ "option value")

(defun %sorted-candidates-by-text (candidates)
  (sort candidates #'string< :key #'candidate-text))

(defun %candidate-entry-command-name (entry)
  (getf entry :command))

(defun %candidate-entry-description (entry)
  (if (%kb-command-entry-p entry)
      (or (%kb-command-entry-description entry) "")
      (or (getf entry :description) "")))

(defun %candidate-entry-flag-specs (entry)
  (if (%kb-command-entry-p entry)
      (%kb-command-entry-flags entry)
      (getf entry :flags)))

(defun %candidate-entry-subcommand-specs (entry)
  (if (%kb-command-entry-p entry)
      (%kb-command-entry-subcommands entry)
      (getf entry :subcommands)))

(defun %candidate-entry-exclusive-option-groups (entry)
  (if (%kb-command-entry-p entry)
      (%kb-command-entry-exclusive-options entry)
      (getf entry :exclusive-options)))

(defun %command-entry-candidate (name entry)
  (make-candidate name
                  :kind :command
                  :description (%candidate-entry-description entry)))

(defun builtin-command-candidates (prefix)
  (%sorted-candidates-by-text
   (loop for entry in +builtin-command-catalog+
         for name = (%candidate-entry-command-name entry)
         when (%starts-with-p prefix name)
           collect (%command-entry-candidate name entry))))

(defun knowledge-base-command-candidates (kb prefix)
  (let ((results '()))
    (%map-kb-commands
     kb
     (lambda (name entry)
       (when (%starts-with-p prefix name)
         (push (%command-entry-candidate name entry) results))))
    (nreverse results)))

(defun %unique-entry-argument-names (entry)
  (let ((seen (make-hash-table :test #'equal))
        (names '()))
    (dolist (source (list (%candidate-entry-flag-specs entry)
                          (%candidate-entry-subcommand-specs entry)))
      (dolist (name source)
        (when (and (stringp name) (not (gethash name seen)))
          (setf (gethash name seen) t)
          (push name names))))
    (nreverse names)))

(defstruct (%attached-option-value-prefix
            (:constructor %make-attached-option-value-prefix (option value-prefix))
            (:conc-name %attached-option-value-prefix-))
  option
  value-prefix)

(defstruct (%separate-option-value-prefix
            (:constructor %make-separate-option-value-prefix (option value-prefix))
            (:conc-name %separate-option-value-prefix-))
  option
  value-prefix)

(defun %parse-attached-option-value-prefix (prefix)
  (let ((separator-position (position #\= prefix)))
    (when separator-position
      (%make-attached-option-value-prefix
       (subseq prefix 0 separator-position)
       (subseq prefix (1+ separator-position))))))

(defun %unique-string-values (values)
  (let ((seen (make-hash-table :test #'equal))
        (unique-values '()))
    (dolist (value values)
      (when (and (stringp value) (not (gethash value seen)))
        (setf (gethash value seen) t)
        (push value unique-values)))
    (nreverse unique-values)))

(defun %entry-option-value-specs (entry)
  (if (%kb-command-entry-p entry)
      (%kb-command-entry-option-values entry)
      (getf entry :option-values)))

(defstruct (%entry-option-value-spec-projection
            (:constructor %make-entry-option-value-spec-projection
                (option values valid-p))
            (:conc-name %entry-option-value-spec-projection-))
  option
  values
  valid-p)

(defun %project-entry-option-value-spec (spec)
  (if (consp spec)
      (%make-entry-option-value-spec-projection
       (first spec)
       (rest spec)
       (stringp (first spec)))
      (%make-entry-option-value-spec-projection nil nil nil)))

(defun %entry-option-value-spec-option (spec)
  (%entry-option-value-spec-projection-option
   (%project-entry-option-value-spec spec)))

(defun %entry-option-value-spec-values (spec)
  (%entry-option-value-spec-projection-values
   (%project-entry-option-value-spec spec)))

(defun %entry-option-value-spec-for-option-p (spec option)
  (let ((projection (%project-entry-option-value-spec spec)))
    (and (%entry-option-value-spec-projection-valid-p projection)
         (string= option
                  (%entry-option-value-spec-projection-option projection)))))

(defun %entry-option-values (entry option)
  (%unique-string-values
   (loop for spec in (%entry-option-value-specs entry)
         when (%entry-option-value-spec-for-option-p spec option)
           append (%entry-option-value-spec-values spec))))

(defun %matching-entry-option-values (entry option value-prefix)
  (loop for value in (%entry-option-values entry option)
        when (and (stringp value)
                  (%starts-with-p value-prefix value))
          collect value))

(defun %option-value-candidate (text)
  (make-candidate text
                  :kind :option
                  :description +option-value-candidate-description+))

(defun %attached-option-value-candidate-text (option value)
  (concatenate 'string option "=" value))

(defun %option-value-candidates (values &key (text-function #'identity))
  (%sorted-candidates-by-text
   (loop for value in values
         collect (%option-value-candidate (funcall text-function value)))))

(defun %attached-option-value-candidates (entry prefix)
  (let ((attached-prefix (%parse-attached-option-value-prefix prefix)))
    (when attached-prefix
      (let ((option (%attached-option-value-prefix-option attached-prefix))
            (value-prefix
              (%attached-option-value-prefix-value-prefix attached-prefix)))
        (%option-value-candidates
         (%matching-entry-option-values entry option value-prefix)
         :text-function (lambda (value)
                          (%attached-option-value-candidate-text
                           option
                           value)))))))

(defun %latest-argument-word (words)
  (loop for word in words
        finally (return word)))

(defun %argument-words-before-latest (words)
  (loop for remaining on words
        while (rest remaining)
        collect (first remaining)))

(defun %argument-words-without-value-prefix (words prefix)
  (let ((latest-word (%latest-argument-word words)))
    (if (and latest-word
             (not (string= prefix ""))
             (string= latest-word prefix))
        (%argument-words-before-latest words)
        words)))

(defun %previous-option-for-value-prefix (argument-words prefix)
  (%latest-argument-word
   (%argument-words-without-value-prefix argument-words prefix)))

(defun %parse-separate-option-value-prefix (argument-words prefix)
  (let ((option (%previous-option-for-value-prefix argument-words prefix)))
    (when option
      (%make-separate-option-value-prefix option prefix))))

(defun %separate-option-value-candidates (entry separate-prefix)
  (when (and separate-prefix
             (not (%starts-with-p "-"
                                  (%separate-option-value-prefix-value-prefix
                                   separate-prefix))))
    (%option-value-candidates
     (%matching-entry-option-values
      entry
      (%separate-option-value-prefix-option separate-prefix)
      (%separate-option-value-prefix-value-prefix separate-prefix)))))

(defun %option-token-matches-p (option token)
  (or (string= option token)
      (and (< (length option) (length token))
           (%starts-with-p option token)
           (char= (char token (length option)) #\=))))

(defun %exclusive-option-blocked-p (entry option argument-words)
  (some (lambda (group)
          (and (member option group :test #'string=)
               (some (lambda (selected-option)
                       (some (lambda (word)
                               (%option-token-matches-p selected-option word))
                             argument-words))
                     group)))
        (%candidate-entry-exclusive-option-groups entry)))

(defun %available-entry-argument-names (entry prefix argument-words)
  (loop for name in (%unique-entry-argument-names entry)
        when (and (%starts-with-p prefix name)
                  (not (%exclusive-option-blocked-p
                        entry
                        name
                        argument-words)))
          collect name))

(defun %argument-name-candidate (name)
  (make-candidate name :kind :option :description ""))

(defun %entry-argument-name-candidates (entry prefix argument-words)
  (%sorted-candidates-by-text
   (loop for name in (%available-entry-argument-names
                      entry
                      prefix
                      argument-words)
         collect (%argument-name-candidate name))))

(defun knowledge-base-argument-candidates (kb command prefix &key argument-words)
  (let ((entry (%kb-command-entry kb command)))
    (when entry
      (or (%attached-option-value-candidates entry prefix)
          (%separate-option-value-candidates
           entry
           (%parse-separate-option-value-prefix argument-words prefix))
          (%entry-argument-name-candidates entry prefix argument-words)))))
