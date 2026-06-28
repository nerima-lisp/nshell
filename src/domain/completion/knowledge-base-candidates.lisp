(in-package #:nshell.domain.completion)

(defun builtin-command-candidates (prefix)
  (sort (loop for entry in +builtin-command-catalog+
              for name = (getf entry :command)
              when (starts-with-p prefix name)
                collect (make-candidate name
                                        :kind :command
                                        :description (or (getf entry :description) "")))
        #'string<
        :key #'candidate-text))

(defun knowledge-base-command-candidates (kb prefix)
  (let ((results '()))
    (maphash (lambda (name entry)
               (when (starts-with-p prefix name)
                 (push (make-candidate name
                                       :kind :command
                                       :description (or (getf entry :description) ""))
                       results)))
             (knowledge-base-commands kb))
    results))

(defun unique-entry-argument-names (entry)
  (let ((seen (make-hash-table :test #'equal))
        (names '()))
    (dolist (source (list (getf entry :flags)
                          (getf entry :subcommands)))
      (dolist (name source)
        (when (and (stringp name) (not (gethash name seen)))
          (setf (gethash name seen) t)
          (push name names))))
    (nreverse names)))

(defun split-attached-option-value-prefix (prefix)
  (let ((separator-position (position #\= prefix)))
    (when separator-position
      (values (subseq prefix 0 separator-position)
              (subseq prefix (1+ separator-position))
              t))))

(defun unique-string-values (values)
  (let ((seen (make-hash-table :test #'equal))
        (unique-values '()))
    (dolist (value values)
      (when (and (stringp value) (not (gethash value seen)))
        (setf (gethash value seen) t)
        (push value unique-values)))
    (nreverse unique-values)))

(defun entry-option-values (entry option)
  (unique-string-values
   (loop for spec in (getf entry :option-values)
         when (and (consp spec)
                   (stringp (first spec))
                   (string= option (first spec)))
           append (rest spec))))

(defun attached-option-value-candidates (entry prefix)
  (multiple-value-bind (option value-prefix attached-p)
      (split-attached-option-value-prefix prefix)
    (when attached-p
      (sort (loop for value in (entry-option-values entry option)
                  when (and (stringp value)
                            (starts-with-p value-prefix value))
                    collect (make-candidate (concatenate 'string option "=" value)
                                            :kind :option
                                            :description "option value"))
            #'string<
            :key #'candidate-text))))

(defun previous-option-for-value-prefix (argument-words prefix)
  (let ((words argument-words))
    (when words
      (cond
        ((string= prefix "")
         (car (last words)))
        ((string= (car (last words)) prefix)
         (car (last (butlast words))))
        (t
         (car (last words)))))))

(defun separate-option-value-candidates (entry previous-option value-prefix)
  (when (and previous-option
             (not (starts-with-p "-" value-prefix)))
    (sort (loop for value in (entry-option-values entry previous-option)
                when (and (stringp value)
                          (starts-with-p value-prefix value))
                  collect (make-candidate value
                                          :kind :option
                                          :description "option value"))
          #'string<
          :key #'candidate-text)))

(defun option-token-matches-p (option token)
  (or (string= option token)
      (and (< (length option) (length token))
           (starts-with-p option token)
           (char= (char token (length option)) #\=))))

(defun exclusive-option-blocked-p (entry option argument-words)
  (some (lambda (group)
          (and (member option group :test #'string=)
               (some (lambda (selected-option)
                       (some (lambda (word)
                               (option-token-matches-p selected-option word))
                             argument-words))
                     group)))
        (getf entry :exclusive-options)))

(defun knowledge-base-argument-candidates (kb command prefix &key argument-words)
  (let ((entry (kb-query kb command)))
    (when entry
      (or (attached-option-value-candidates entry prefix)
          (separate-option-value-candidates
           entry
           (previous-option-for-value-prefix argument-words prefix)
           prefix)
          (sort (loop for name in (unique-entry-argument-names entry)
                      when (and (starts-with-p prefix name)
                                (not (exclusive-option-blocked-p entry
                                                                  name
                                                                  argument-words)))
                        collect (make-candidate name :kind :option :description ""))
                #'string<
                :key #'candidate-text)))))
