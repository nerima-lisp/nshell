; Helpers for the 'type' builtin command.
(in-package #:nshell.application)

(defstruct %type-options
  (all-p nil)
  (short-p nil)
  (no-functions-p nil)
  (color-p nil)
  (query-p nil)
  (path-p nil)
  (force-path-p nil)
  (type-p nil)
  (help-p nil))

(defun %type-usage (&optional (code 1))
  (%builtin-usage "type" "type [OPTIONS] NAME [...]" code))

(defun %type-option-p (option)
  (and option
       (>= (length option) 2)
       (char= (char option 0) #\-)))

(defun %type-option-kind (option)
  (cond
    ((member option '("-a" "--all") :test #'string=) :all)
    ((member option '("-s" "--short") :test #'string=) :short)
    ((member option '("-f" "--no-functions") :test #'string=) :no-functions)
    ((or (string= option "--color")
         (and (>= (length option) 8)
              (string= option "--color=" :end1 8 :end2 8)))
     :color)
    ((member option '("-q" "--query" "--quiet") :test #'string=) :query)
    ((member option '("-p" "--path") :test #'string=) :path)
    ((member option '("-P" "--force-path") :test #'string=) :force-path)
    ((member option '("-t" "--type") :test #'string=) :type)
    ((member option '("-h" "--help") :test #'string=) :help)
    (t nil)))

(defun %type-color-enabled-p (option)
  (or (string= option "--color")
      (and (>= (length option) 8)
           (string= option "--color=" :end1 8 :end2 8)
           (let ((value (subseq option 8)))
             (or (string= value "always")
                 (string= value "auto"))))))

(defun %string-lines (text)
  (loop with start = 0
        for end = (position #\Newline text :start start)
        collect (subseq text start end)
        do (setf start (if end (1+ end) (length text)))
        while end))

(defun %colorize-function-definition-output (text)
  (with-output-to-string (out)
    (dolist (line (%string-lines text))
      (write-string
       (nshell.presentation:highlight->ansi
        (nshell.presentation:highlight-line line)
        line
        (nshell.domain.configuration:default-theme))
       out)
      (terpri out))))

(defun %parse-type-options (args)
  (let ((options (make-%type-options))
        (remaining args))
    (loop while remaining
          for option = (first remaining)
          do (cond
               ((string= option "--")
                (setf remaining (rest remaining))
                (return))
               ((not (%type-option-p option))
                (return))
               (t
                (case (%type-option-kind option)
                  (:all (setf (%type-options-all-p options) t))
                  (:short (setf (%type-options-short-p options) t))
                  (:no-functions (setf (%type-options-no-functions-p options) t))
                  (:color
                   (unless (%type-color-enabled-p option)
                     (return-from %parse-type-options
                       (values nil nil
                               (format nil "type: unknown option ~a~%" option)
                               2)))
                   (setf (%type-options-color-p options) t))
                  (:query (setf (%type-options-query-p options) t))
                  (:path (setf (%type-options-path-p options) t))
                  (:force-path (setf (%type-options-force-path-p options) t))
                  (:type (setf (%type-options-type-p options) t))
                  (:help (setf (%type-options-help-p options) t))
                  (otherwise
                   (return-from %parse-type-options
                     (values nil nil
                             (format nil "type: unknown option ~a~%" option)
                             2))))
                (setf remaining (rest remaining)))))
    (let ((mode-count (count t (list (%type-options-query-p options)
                                     (%type-options-path-p options)
                                     (%type-options-force-path-p options)
                                     (%type-options-type-p options)))))
      (when (> mode-count 1)
        (return-from %parse-type-options
          (values nil nil (%type-usage 2) 2))))
    (values options remaining nil nil)))

(defun %resolve-type-path-candidates (context command)
  (mapcar (lambda (candidate)
            (list :path candidate))
          (%resolve-command-path-candidates context command)))

(defun %type-command-shell-shadowed-p (context command)
  (or (nth-value 1 (gethash command (shell-context-alias-table context)))
      (nth-value 1 (gethash command (shell-context-function-table context)))
      (nth-value 1 (gethash command (shell-context-abbreviation-table context)))))

(defun %type-command-builtin-present-p (command)
  (not (null (lookup-builtin command))))

(defun %type-command-source-path (context command)
  (nth-value 0 (gethash command (shell-context-function-source-table context))))

(defun %type-add-candidate (candidates kind text)
  (cons (list kind text) candidates))

(defun %type-add-path-candidates (candidates options path-candidates)
  (dolist (candidate (if (%type-options-all-p options)
                         path-candidates
                         (let ((first (first path-candidates)))
                           (when first (list first)))))
    (setf candidates (%type-add-candidate candidates
                                          (first candidate)
                                          (second candidate))))
  candidates)

(defun %type-command-candidates-for-path-option (context command options)
  (let ((candidates nil)
        (source-path (%type-command-source-path context command))
        (shell-shadowed-p (%type-command-shell-shadowed-p context command))
        (builtin-present-p (%type-command-builtin-present-p command)))
    (when (and builtin-present-p (not shell-shadowed-p))
      (setf candidates (%type-add-candidate candidates :builtin command)))
    (when source-path
      (setf candidates (%type-add-candidate candidates :path source-path)))
    (unless (or source-path shell-shadowed-p builtin-present-p)
      (setf candidates (%type-add-path-candidates candidates
                                                  options
                                                  (%resolve-type-path-candidates context command))))
    (when (and (null candidates) shell-shadowed-p)
      (setf candidates (%type-add-candidate candidates :shadowed nil)))
    (nreverse candidates)))

(defun %type-command-candidates-for-default-option (context command options)
  (let ((candidates nil))
    (multiple-value-bind (alias alias-present-p)
        (gethash command (shell-context-alias-table context))
      (when alias-present-p
        (setf candidates (%type-add-candidate candidates :alias alias))))
    (unless (%type-options-no-functions-p options)
      (multiple-value-bind (function-body function-present-p)
          (gethash command (shell-context-function-table context))
        (when function-present-p
          (setf candidates (%type-add-candidate candidates :function function-body)))))
    (multiple-value-bind (abbreviation abbreviation-present-p)
        (gethash command (shell-context-abbreviation-table context))
      (when abbreviation-present-p
        (setf candidates (%type-add-candidate candidates :abbreviation
                                              (%abbreviation-expansion abbreviation)))))
    (when (%type-command-builtin-present-p command)
      (setf candidates (%type-add-candidate candidates :builtin command)))
    (setf candidates (%type-add-path-candidates candidates
                                                options
                                                (%resolve-type-path-candidates context command)))
    (nreverse candidates)))

(defun %type-command-candidates (context command options)
  (cond
    ((%type-options-force-path-p options)
     (%type-add-path-candidates nil
                                options
                                (%resolve-type-path-candidates context command)))
    ((%type-options-path-p options)
     (%type-command-candidates-for-path-option context command options))
    (t
     (%type-command-candidates-for-default-option context command options))))

(defun %write-type-candidate (out spec name candidate options)
  (destructuring-bind (kind text) candidate
    (case kind
      (:alias
       (format out (getf spec :alias-format) name text))
      (:function
       (format out (getf spec :function-format) name)
       (unless (%type-options-short-p options)
         (let ((definition (%format-function-definition name text)))
           (write-string (if (%type-options-color-p options)
                             (%colorize-function-definition-output definition)
                             definition)
                         out))))
      (:abbreviation
       (format out (getf spec :abbreviation-format) name text))
      (:builtin
       (format out (getf spec :builtin-format) name))
      (:path
       (format out (getf spec :path-format) name text)))))
