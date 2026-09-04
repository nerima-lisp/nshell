(in-package #:nshell.domain.completion)

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

(defun %completion-help-value-kind-token (token)
  (let ((clean
          (string-downcase
           (string-trim
            '(#\Space #\Tab #\< #\> #\[ #\] #\{ #\} #\( #\)
              #\, #\; #\: #\= #\' #\")
            token))))
    (cdr (assoc clean *completion-help-value-kind-tokens*
                :test #'string=))))

(defun %completion-help-line-words (line)
  (let ((words nil)
        (start nil)
        (length (length line)))
    (labels ((flush (end)
               (when start
                 (push (subseq line start end) words)
                 (setf start nil))))
      (loop for index from 0 below length
            for character = (char line index)
            do (if (find character '(#\Space #\Tab))
                   (flush index)
                   (unless start
                     (setf start index))))
      (flush length))
    (nreverse words)))

(defun %completion-help-option-value-kinds (line options)
  (loop with pending-options = nil
        for word in (%completion-help-line-words line)
        for clean = (%completion-help-clean-option-token word)
        for equals-position = (position #\= word)
        for attached-kind =
          (and equals-position
               (%completion-help-value-kind-token
                (subseq word (1+ equals-position))))
        do (cond
             ((member clean options :test #'string=)
              (push clean pending-options)
              (when attached-kind
                (return
                 (mapcar (lambda (option)
                           (list option attached-kind))
                         (nreverse pending-options)))))
             ((and pending-options
                   (%completion-help-option-token-p clean))
              (setf pending-options nil))
             (pending-options
              (let ((kind (%completion-help-value-kind-token clean)))
                (when kind
                  (return
                   (mapcar (lambda (option)
                             (list option kind))
                           (nreverse pending-options))))
                (setf pending-options nil))))
        finally (return nil)))

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
  "Return the trimmed enum values in a `(a|b|c)' fragment of LINE, or NIL when
LINE carries no parenthesized pipe-separated group."
  (let* ((open (position #\( line))
         (close (and open (position #\) line :start (1+ open))))
         (content (and close (subseq line (1+ open) close))))
    (when (and content (position #\| content))
      (remove-if-not #'%completion-help-enum-value-p
                     (mapcar (lambda (value)
                               (string-trim '(#\Space #\Tab #\' #\") value))
                             (%completion-split-on-char content #\|))))))

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
         (option-value-kinds (%completion-help-option-value-kinds line options))
         (kind (%completion-help-line-kind state line)))
    (%make-completion-help-line-facts
     kind options values option-value-kinds
     (and (eq kind :subcommand)
          (%completion-help-subcommand-name line)))))
