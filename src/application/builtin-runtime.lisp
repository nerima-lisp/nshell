(in-package #:nshell.application)

(defvar *builtin-registry* (make-hash-table :test #'equal)
  "Registry mapping builtin command names to handler functions.")

(defun lookup-builtin (name)
  "Return the builtin handler registered for NAME, or NIL."
  (and name (gethash name *builtin-registry*)))

(defun %required-argument-error (builtin option requirement)
  (format nil "~a: ~a requires ~a~%" builtin option requirement))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro %with-option-arguments ((remaining option)
                                    on-sentinel
                                    on-unknown
                                    on-operand
                                    &body clauses)
    `(block nil
       (loop while ,remaining
             for ,option = (first ,remaining)
             do (cond
                  ((string= ,option "--")
                   (setf ,remaining (rest ,remaining))
                   ,on-sentinel)
                  ,@clauses
                  ((and (> (length ,option) 1)
                        (char= (char ,option 0) #\-))
                   ,on-unknown)
                  (t ,on-operand)))))

  (defmacro %with-required-argument ((return-target remaining builtin option requirement status) &body body)
    `(if (rest ,remaining)
         (progn ,@body)
         (return-from ,return-target
           (values (%required-argument-error ,builtin ,option ,requirement)
                    ,status)))))

(defun %builtin-usage-clauses-summary (clauses)
  (format nil "~{~A~^; ~}" clauses))

(defun %builtin-usage (command usage &optional (code 1))
  (values (format nil "~a: usage: ~a~%" command usage) code))

(defun %string-join (items separator)
  (with-output-to-string (out)
    (loop for item in items
          for first = t then nil
          do (unless first
               (write-string separator out))
             (write-string (princ-to-string item) out))))

(defun %filesystem-fn (context key)
  (or (getf (shell-context-filesystem-fns context) key)
      (error "Missing filesystem adapter ~s" key)))

(defun %optional-filesystem-fn (context key)
  (getf (shell-context-filesystem-fns context) key))

(defun %process-fn (context key)
  (or (getf (shell-context-process-fns context) key)
      (error "Missing process adapter ~s" key)))

(defun %optional-process-fn (context key)
  (getf (shell-context-process-fns context) key))

(defun %run-external-command-in-context (context command args)
  (let ((capture-runner (%optional-process-fn context :run-external-capture)))
    (if capture-runner
        (funcall capture-runner command args)
        (values nil
                (funcall (%process-fn context :run-external) command args)))))

(defun %path-separator-p (char)
  (or (char= char #\/)
      #+windows (char= char #\\)
      #-windows nil))

(defun %command-has-directory-p (command)
  (position-if #'%path-separator-p command))

(defun %split-path (path)
  (let ((start 0)
        (parts nil))
    (loop for pos = (position #\: path :start start)
          do (push (subseq path start pos) parts)
          while pos
          do (setf start (1+ pos)))
    (nreverse parts)))

(defun %join-path-name (directory command)
  (cond
    ((string= directory "") command)
    ((char= (char directory (1- (length directory))) #\/)
     (concatenate 'string directory command))
    (t (concatenate 'string directory "/" command))))

(defun %resolve-command-path-candidates (context command)
  (cond
    ((%command-has-directory-p command)
     (when (%stat-path context command)
       (list command)))
    (t
     (let ((path (or (and (shell-context-environment context)
                          (nshell.domain.environment:env-get
                           (shell-context-environment context) "PATH"))
                     "")))
       (loop for directory in (%split-path path)
             for candidate = (%join-path-name directory command)
             when (%stat-path context candidate)
               collect candidate)))))

(defun %stat-path (context path)
  (handler-case
      (funcall (%filesystem-fn context :stat) path)
    (error () nil)))

(defun %path-file-p (context path)
  (let ((fn (%optional-filesystem-fn context :file-exists-p)))
    (cond
      (fn (funcall fn path))
      ((%stat-path context path)
       (let ((pathname (probe-file path)))
         (and pathname (not (uiop:directory-pathname-p pathname)))))
      (t nil))))

(defun %path-directory-p (context path)
  (let ((fn (%optional-filesystem-fn context :directory-exists-p)))
    (cond
      (fn (funcall fn path))
      (t (not (null (uiop:directory-exists-p path)))))))

(defun resolve-command-path (context command)
  "Return COMMAND's executable path from builtins or PATH, or NIL."
  (cond
    ((lookup-builtin command) (values :builtin command))
    (t
     (let ((candidates (%resolve-command-path-candidates context command)))
       (when candidates
         (values :path (first candidates)))))))

(defun %command-path-spec (command)
  (cdr (assoc command nshell.domain.completion:+command-path-builtin-specs+
              :test #'string=)))

(defun %execute-function-command-in-context (context function-body args)
  ;; Expose the call arguments to the function body as $argv / $argv[N].
  (let ((nshell.domain.expansion:*positional-args* args))
    (%source-lines context function-body)))

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

(defun %execute-command-by-name-in-context (context command args)
  (multiple-value-bind (function-body function-present-p)
      (gethash command (shell-context-function-table context))
    (let ((handler (lookup-builtin command)))
      (cond
        (function-present-p
         (%execute-function-command-in-context context function-body args))
        (handler
         (funcall handler context args))
        (t
         (%run-external-command-in-context context command args))))))
