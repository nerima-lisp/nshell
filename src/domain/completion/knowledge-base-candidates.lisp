(in-package #:nshell.domain.completion)

(defparameter +option-value-candidate-description+ "option value")

(defun %sorted-candidates-by-text (candidates)
  (sort candidates #'string< :key #'candidate-text))

(defun %command-entry-candidate (name description)
  (make-candidate name
                  :kind :command
                  :description (or description "")))

(defun builtin-command-candidates (prefix)
  (%sorted-candidates-by-text
   (loop for entry in +builtin-command-catalog+
         for name = (%catalog-command-entry-command entry)
         when (%starts-with-p prefix name)
           collect (%command-entry-candidate name (%catalog-command-entry-description entry)))))

(defun knowledge-base-command-candidates (kb prefix)
  (loop for name in (kb-registered-commands kb)
        when (and (not (position #\Space name))
                  (%starts-with-p prefix name))
          collect (%command-entry-candidate name (kb-command-description kb name))))

(defun %unique-kb-argument-names (kb command)
  (%unique-string-values
   (append (kb-command-flags kb command) (kb-command-subcommands kb command))))

(define-value-struct %attached-option-value-prefix
  ((option nil)
   (value-prefix nil))
  :public-accessors nil
  :constructor %make-attached-option-value-prefix)

(define-value-struct %separate-option-value-prefix
  ((option nil)
   (value-prefix nil))
  :public-accessors nil
  :constructor %make-separate-option-value-prefix)

(defun %parse-attached-option-value-prefix (prefix)
  (let ((separator-position (position #\= prefix)))
    (when separator-position
      (%make-attached-option-value-prefix
       (subseq prefix 0 separator-position)
       (subseq prefix (1+ separator-position))))))

(defun %kb-option-values (kb command option)
  (%unique-string-values
   (loop for spec in (kb-command-option-values kb command)
         when (%kb-option-value-spec-for-option-p spec option)
           append (%kb-option-value-spec-values spec))))

(defun %kb-option-value-spec-for-option-p (spec opt-name)
  (and (%valid-kb-option-value-spec-p spec)
       (string= opt-name (%kb-option-value-spec-option spec))))

(defun %matching-kb-option-values (kb command option value-prefix)
  (loop for value in (%kb-option-values kb command option)
        when (and (stringp value)
                  (%starts-with-p value-prefix value))
          collect value))

(define-value-struct %argument-word-sequence
  ((words nil)
   (latest nil)
   (words-before-latest nil))
  :public-accessors nil
  :constructor %make-argument-word-sequence)

(defun %argument-word-sequence-from-words (words)
  (let ((latest nil)
        (words-before-latest nil))
    (dolist (word words)
      (when latest
        (push latest words-before-latest))
      (setf latest word))
    (%make-argument-word-sequence
     words
     latest
     (nreverse words-before-latest))))

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

(defun %attached-kb-option-value-candidates (kb command prefix)
  (let ((attached-prefix (%parse-attached-option-value-prefix prefix)))
    (when attached-prefix
      (let ((option (%attached-option-value-prefix-option attached-prefix))
            (value-prefix
              (%attached-option-value-prefix-value-prefix attached-prefix)))
        (%option-value-candidates
         (%matching-kb-option-values kb command option value-prefix)
         :text-function (lambda (value)
                          (%attached-option-value-candidate-text
                           option
                           value)))))))

(defun %argument-words-without-value-prefix (words prefix)
  (let* ((sequence (%argument-word-sequence-from-words words))
         (latest-word (%argument-word-sequence-latest sequence)))
    (if (and latest-word
             (string= latest-word prefix)
             (or (not (string= prefix ""))
                 (string= latest-word "")))
        (%argument-word-sequence-words-before-latest sequence)
        words)))

(defun %resolved-kb-command (knowledge-base command argument-words prefix)
  "Resolve the longest known command or subcommand path before the current word."
  (let ((resolved command))
    (dolist (word (%argument-words-without-value-prefix argument-words prefix)
                  resolved)
      (let ((candidate (format nil "~a ~a" resolved word)))
        (if (and (not (%starts-with-p "-" word))
                 (or (kb-command-present-p knowledge-base candidate)
                     (member word
                             (kb-command-subcommands knowledge-base resolved)
                             :test #'string=)))
            (setf resolved candidate)
            (return resolved))))))

(defun kb-resolve-command-path (knowledge-base command argument-words prefix)
  "Return the longest command path known before PREFIX."
  (%resolved-kb-command knowledge-base command argument-words prefix))

(defun %kb-option-value-kind-for-option (knowledge-base command option)
  (second
   (find option
         (kb-command-option-value-kinds knowledge-base command)
         :key #'first
         :test #'string=)))

(defun knowledge-base-option-value-kind
    (knowledge-base command argument-words prefix)
  "Return the filesystem value kind implied by the current option prefix."
  (let* ((resolved-command
           (%resolved-kb-command knowledge-base command argument-words prefix))
         (attached-prefix (%parse-attached-option-value-prefix prefix)))
    (or
     (and attached-prefix
          (%kb-option-value-kind-for-option
           knowledge-base
           resolved-command
           (%attached-option-value-prefix-option attached-prefix)))
     (let ((separate-prefix
             (%parse-separate-option-value-prefix argument-words prefix)))
       (and separate-prefix
            (%kb-option-value-kind-for-option
             knowledge-base
             resolved-command
             (%separate-option-value-prefix-option separate-prefix)))))))

(defun %previous-option-for-value-prefix (argument-words prefix)
  (%argument-word-sequence-latest
   (%argument-word-sequence-from-words
    (%argument-words-without-value-prefix argument-words prefix))))

(defun %parse-separate-option-value-prefix (argument-words prefix)
  (let ((option (%previous-option-for-value-prefix argument-words prefix)))
    (when option
      (%make-separate-option-value-prefix option prefix))))

(defun %separate-kb-option-value-candidates (kb command separate-prefix)
  (when (and separate-prefix
             (not (%starts-with-p "-"
                                  (%separate-option-value-prefix-value-prefix
                                   separate-prefix))))
    (%option-value-candidates
     (%matching-kb-option-values
      kb
      command
      (%separate-option-value-prefix-option separate-prefix)
      (%separate-option-value-prefix-value-prefix separate-prefix)))))

(defun %option-token-matches-p (option token)
  (or (string= option token)
      (and (< (length option) (length token))
           (%starts-with-p option token)
           (char= (char token (length option)) #\=))))

(defun %kb-exclusive-option-blocked-p (kb command option argument-words)
  (some (lambda (group)
          (and (member option group :test #'string=)
               (some (lambda (selected-option)
                       (some (lambda (word)
                               (%option-token-matches-p selected-option word))
                             argument-words))
                     group)))
        (kb-command-exclusive-options kb command)))

(defun %available-kb-argument-names (kb command prefix argument-words)
  (loop for name in (%unique-kb-argument-names kb command)
        when (and (%starts-with-p prefix name)
                  (not (%kb-exclusive-option-blocked-p kb command name argument-words)))
          collect name))

(defun %argument-name-candidate (name)
  (make-candidate name :kind :option :description ""))

(defun %kb-argument-name-candidates (kb command prefix argument-words)
  (%sorted-candidates-by-text
   (loop for name in (%available-kb-argument-names kb command prefix argument-words)
         collect (%argument-name-candidate name))))

(defun knowledge-base-argument-candidates (kb command prefix &key argument-words)
  (let ((resolved-command
          (%resolved-kb-command kb command argument-words prefix)))
    (when (kb-command-present-p kb resolved-command)
      (or (%attached-kb-option-value-candidates kb resolved-command prefix)
          (%separate-kb-option-value-candidates
           kb
           resolved-command
           (%parse-separate-option-value-prefix argument-words prefix))
          (%kb-argument-name-candidates
           kb resolved-command prefix argument-words)))))
