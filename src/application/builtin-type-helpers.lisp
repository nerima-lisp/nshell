; Helpers for the 'type' builtin command.
(in-package #:nshell.application)

(define-value-struct %type-options
    ((all-p nil)
     (short-p nil)
     (no-functions-p nil)
     (color-p nil)
     (query-p nil)
     (path-p nil)
     (force-path-p nil)
     (type-p nil)
     (help-p nil))
  :constructor %make-type-options
  :keyword-constructor t
  :public-accessors nil)

(defun %type-options-with (options kind)
  (%make-type-options
   :all-p (or (%type-options-all-p options) (eq kind :all))
   :short-p (or (%type-options-short-p options) (eq kind :short))
   :no-functions-p (or (%type-options-no-functions-p options) (eq kind :no-functions))
   :color-p (or (%type-options-color-p options) (eq kind :color))
   :query-p (or (%type-options-query-p options) (eq kind :query))
   :path-p (or (%type-options-path-p options) (eq kind :path))
   :force-path-p (or (%type-options-force-path-p options) (eq kind :force-path))
   :type-p (or (%type-options-type-p options) (eq kind :type))
   :help-p (or (%type-options-help-p options) (eq kind :help))))

(defun %type-usage (&optional (code 1))
  (%builtin-usage "type" "type [OPTIONS] NAME [...]" code))

(defun %type-option-p (option)
  (%builtin-option-like-p option))

(defun %type-option-kind (option)
  (cond
    ((%builtin-option-p option '("-a" "--all")) :all)
    ((%builtin-option-p option '("-s" "--short")) :short)
    ((%builtin-option-p option '("-f" "--no-functions")) :no-functions)
    ((or (string= option "--color")
         (and (>= (length option) 8)
              (string= option "--color=" :end1 8 :end2 8)))
     :color)
    ((%builtin-option-p option '("-q" "--query" "--quiet")) :query)
    ((%builtin-option-p option '("-p" "--path")) :path)
    ((%builtin-option-p option '("-P" "--force-path")) :force-path)
    ((%builtin-option-p option '("-t" "--type")) :type)
    ((%builtin-option-p option '("-h" "--help")) :help)
    (t nil)))

(defmacro %enable-type-option (options kind)
  `(setf ,options (%type-options-with ,options ,kind)))

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
  (let ((options (%make-type-options))
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
                  (:all (%enable-type-option options :all))
                  (:short (%enable-type-option options :short))
                  (:no-functions (%enable-type-option options :no-functions))
                  (:color
                   (unless (%type-color-enabled-p option)
                     (return-from %parse-type-options
                       (values nil nil
                               (format nil "type: unknown option ~a~%" option)
                               2)))
                   (%enable-type-option options :color))
                  (:query (%enable-type-option options :query))
                  (:path (%enable-type-option options :path))
                  (:force-path (%enable-type-option options :force-path))
                  (:type (%enable-type-option options :type))
                  (:help (%enable-type-option options :help))
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
