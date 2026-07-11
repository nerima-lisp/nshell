(in-package #:nshell.domain.completion)

(defstruct (%completion-help-command-facts
            (:constructor %make-completion-help-command-facts
                (subcommands flags option-values))
            (:conc-name %completion-help-command-facts-))
  (subcommands nil :type list :read-only t)
  (flags nil :type list :read-only t)
  (option-values nil :type list :read-only t))

(defstruct (%completion-help-scan-state
            (:constructor %make-completion-help-scan-state ())
            (:conc-name %completion-help-scan-state-))
  (subcommands nil :type list)
  (flags nil :type list)
  (option-values nil :type list)
  (collecting-subcommands-p nil :type boolean))

(defstruct (%completion-help-line-facts
            (:constructor %make-completion-help-line-facts
                (kind options values subcommand-name))
            (:conc-name %completion-help-line-facts-))
  (kind :other :type (member :heading :blank :subcommand :other :stop-subcommands)
   :read-only t)
  (options nil :type list :read-only t)
  (values nil :type list :read-only t)
  (subcommand-name nil :type (or null string) :read-only t))

(defparameter *completion-help-section-headings*
  '("commands:" "command:" "subcommands:" "subcommand:"))

(defparameter *completion-help-option-delimiters*
  '(#\Space #\Tab #\, #\; #\) #\( #\[ #\] #\{ #\}))

(defparameter *completion-help-option-trim-chars*
  '(#\Space #\Tab #\, #\; #\. #\: #\) #\( #\[ #\] #\{ #\}))

(defparameter *completion-help-enum-delimiters*
  '(#\Space #\Tab #\Newline #\Return))

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
  (find char *completion-help-option-delimiters*))

(defun %completion-help-option-end (line start)
  (or (position-if #'%completion-help-token-delimiter-p line :start start)
      (length line)))

(defun %completion-help-clean-option-token (token)
  (let* ((trimmed (string-trim *completion-help-option-trim-chars* token))
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
    (%unique-string-values (nreverse options))))

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
                           (find char *completion-help-enum-delimiters*))
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

(defun %completion-help-blank-line-p (line)
  (string= "" (string-trim '(#\Space #\Tab) line)))

(defun %completion-help-section-heading-p (line)
  (let ((trimmed (string-downcase (string-trim '(#\Space #\Tab) line))))
    (some (lambda (heading)
            (search heading trimmed :test #'char=))
          *completion-help-section-headings*)))

(defun %completion-help-subcommand-line-p (line)
  (let ((trimmed (string-trim '(#\Space #\Tab) line)))
    (and (plusp (length trimmed))
         (not (char= (char trimmed 0) #\-))
         (position-if (lambda (char)
                        (find char '(#\Space #\Tab)))
                      trimmed))))

(defun %completion-help-subcommand-name (line)
  (let* ((trimmed (string-trim '(#\Space #\Tab) line))
         (delimiter (or (position #\Space trimmed)
                        (position #\Tab trimmed)
                        (length trimmed))))
    (subseq trimmed 0 delimiter)))

(defun %completion-help-line-kind (state line)
  (cond
    ((%completion-help-section-heading-p line) :heading)
    ((%completion-help-blank-line-p line) :blank)
    ((%completion-help-scan-state-collecting-subcommands-p state)
     (if (%completion-help-subcommand-line-p line)
         :subcommand
         :stop-subcommands))
    (t :other)))

(defun %completion-help-line-facts (state line)
  (let* ((options (%completion-help-options-in-line line))
         (values (%completion-help-enum-values line))
         (kind (%completion-help-line-kind state line)))
    (%make-completion-help-line-facts
     kind
     options
     values
     (and (eq kind :subcommand)
          (%completion-help-subcommand-name line)))))

(defun %completion-help-note-line-kind (state kind facts)
  (ecase kind
    (:heading
     (setf (%completion-help-scan-state-collecting-subcommands-p state) t))
    (:blank
     (setf (%completion-help-scan-state-collecting-subcommands-p state) nil))
    (:subcommand
     (push (%completion-help-line-facts-subcommand-name facts)
           (%completion-help-scan-state-subcommands state)))
    (:stop-subcommands
     (setf (%completion-help-scan-state-collecting-subcommands-p state) nil))
    (:other
     nil))
  state)

(defun %completion-help-note-options (state options)
  (dolist (option options state)
    (push option (%completion-help-scan-state-flags state))))

(defun %completion-help-note-option-values (state options values)
  (when values
    (dolist (option options state)
      (when (%starts-with-p "--" option)
        (push (%make-kb-option-value-spec option values)
              (%completion-help-scan-state-option-values state))))))

(defun %completion-help-update-scan-state (state line)
  (let* ((facts (%completion-help-line-facts state line))
         (kind (%completion-help-line-facts-kind facts)))
    (%completion-help-note-line-kind state kind facts)
    (%completion-help-note-options state (%completion-help-line-facts-options facts))
    (%completion-help-note-option-values state
                                         (%completion-help-line-facts-options facts)
                                         (%completion-help-line-facts-values facts))
    state))

(defun %completion-help-command-facts (help-text)
  (let ((state (%make-completion-help-scan-state)))
    (dolist (line (%completion-help-lines help-text))
      (%completion-help-update-scan-state state line))
    (%make-completion-help-command-facts
     (%unique-string-values
      (nreverse (%completion-help-scan-state-subcommands state)))
     (%unique-string-values
      (nreverse (%completion-help-scan-state-flags state)))
     (nreverse (%completion-help-scan-state-option-values state)))))

(defun kb-add-command-from-help (kb cmd-name help-text &key description)
  "Add command completion metadata by parsing already-fetched help text."
  (let ((facts (%completion-help-command-facts help-text)))
    (kb-add-command kb cmd-name
                    :subcommands (%completion-help-command-facts-subcommands facts)
                    :flags (%completion-help-command-facts-flags facts)
                    :option-values
                    (%completion-help-command-facts-option-values facts)
                    :description description)))
