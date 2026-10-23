(in-package #:nshell.domain.parsing)

(defstruct sexp-reader-prototype-command-metadata
  command-node
  force-external-p)

(defstruct %sexp-reader-prototype-unquote
  kind
  form)

(defun %sexp-reader-prototype-unquote-reader (kind)
  (lambda (stream character)
    (declare (ignore character))
    (make-%sexp-reader-prototype-unquote :kind kind :form (read stream t nil t))))

(defun %sexp-reader-prototype-reject-dispatch (stream character)
  (declare (ignore stream))
  (error "Reader dispatch character ~C is disabled in the prototype." character))

(defun %sexp-reader-prototype-readtable (case)
  (let ((readtable (copy-readtable nil)))
    (setf (readtable-case readtable) case)
    (set-macro-character #\$
                         (%sexp-reader-prototype-unquote-reader :dollar)
                         nil
                         readtable)
    (set-macro-character #\,
                         (%sexp-reader-prototype-unquote-reader :comma)
                         nil
                         readtable)
    (set-macro-character #\#
                         (function %sexp-reader-prototype-reject-dispatch)
                         nil
                         readtable)
    (set-macro-character
     #\|
     (lambda (stream character)
       (declare (ignore character))
       (let ((next (peek-char nil stream nil nil)))
         (if (or (null next)
                 (find next
                       '(#\Space #\Tab #\Newline #\Return #\( #\) #\;)))
             :pipeline
             (intern
              (with-output-to-string (name)
                (loop for current = (read-char stream nil nil)
                      do (cond
                           ((null current)
                            (error "Unterminated escaped symbol."))
                           ((char= current #\|)
                            (return))
                           ((char= current #\\)
                            (let ((escaped (read-char stream nil nil)))
                              (unless escaped
                                (error "Unterminated escaped symbol escape."))
                              (write-char escaped name)))
                           (t (write-char current name)))))
              *package*))))
     nil
     readtable)
    readtable))

(defun %sexp-reader-prototype-first-non-whitespace (input)
  (or
   (position-if-not
    (lambda (character)
      (find character '(#\Space #\Tab #\Newline #\Return)))
    input)
   (length input)))

(defun %sexp-reader-prototype-read-one (input readtable package start)
  (let ((*readtable* readtable)
        (*package* package)
        (*read-eval* nil)
        (eof (gensym "EOF-")))
    (multiple-value-bind (form end)
        (read-from-string input nil eof :start start)
      (when (eq form eof)
        (error "Expected an S-expression command island."))
      (values form end))))

(defun %sexp-reader-prototype-proper-list-p (form)
  (and (listp form)
       (handler-case (progn
                       (list-length form)
                       t)
         (type-error ()
           nil))))

(defun %sexp-reader-prototype-atom-string (value)
  (typecase value
    (string value)
    (symbol (symbol-name value))
    (number (princ-to-string value))
    (t (error "Unsupported command island atom: ~S" value))))

(defun %sexp-reader-prototype-host-form-p (form)
  (let ((head (and (consp form) (first form))))
    (and (symbolp head)
         (eq (symbol-package head) (find-package "COMMON-LISP"))
         (or (special-operator-p head) (macro-function head) (fboundp head)))))

(defun %sexp-reader-prototype-value-string (value unquote-evaluator)
  (if (%sexp-reader-prototype-unquote-p value)
      (progn
        (unless (functionp unquote-evaluator)
          (error
           "An unquote requires the explicit :UNQUOTE-EVALUATOR callback."))
        (%sexp-reader-prototype-atom-string
         (funcall unquote-evaluator
                  (%sexp-reader-prototype-unquote-kind value)
                  (%sexp-reader-prototype-unquote-form value))))
      (%sexp-reader-prototype-atom-string value)))

(defun %sexp-reader-prototype-read-pair (input)
  (let* ((package
          (make-package (symbol-name (gensym "NSHELL-SEXPR-PROTOTYPE-"))
                        :use
                        (list (find-package "COMMON-LISP"))))
         (preserve-readtable (%sexp-reader-prototype-readtable :preserve))
         (upcase-readtable (%sexp-reader-prototype-readtable :upcase))
         (start (%sexp-reader-prototype-first-non-whitespace input)))
    (unwind-protect
         (labels ((trim-read-end (end)
                    (loop while (and (> end start)
                                     (find (char input (1- end))
                                           '(#\Space #\Tab #\Newline #\Return)))
                          do (decf end))
                    end)
                  (skip-reader-trivia (position)
                    (loop
                      (cond
                        ((>= position (length input))
                         (return position))
                        ((find (char input position)
                               '(#\Space #\Tab #\Newline #\Return))
                         (incf position))
                        ((char= (char input position) #\;)
                         (loop while (and (< position (length input))
                                          (char/= (char input position)
                                                  #\Newline))
                               do (incf position)))
                        (t (return position)))))
                  (host-head (position preserved-head)
                    (if (and (symbolp preserved-head)
                             (eq (symbol-package preserved-head) package))
                        (multiple-value-bind (head end)
                            (%sexp-reader-prototype-read-one input
                                                             upcase-readtable
                                                             package
                                                             position)
                          (declare (ignore end))
                          head)
                        preserved-head))
                  (pipeline-stage-spans (form)
                    (when (and (%sexp-reader-prototype-proper-list-p form)
                               (eq (first form) :pipeline))
                      (let ((operator-position (skip-reader-trivia (1+ start)))
                            (position nil)
                            (spans nil))
                        (unless (and (< operator-position (length input))
                                     (char= (char input operator-position) #\|))
                          (error "A pipeline form must begin with a standalone |."))
                        (setf position (1+ operator-position))
                        (loop repeat (length (rest form))
                              do (setf position (skip-reader-trivia position))
                                 (let ((stage-start position))
                                   (multiple-value-bind (stage raw-end)
                                       (%sexp-reader-prototype-read-one
                                        input
                                        preserve-readtable
                                        package
                                        position)
                                     (declare (ignore stage))
                                     (let ((stage-end
                                             (trim-read-end raw-end)))
                                       (push (list stage-start stage-end) spans)
                                       (setf position stage-end)))))
                        (nreverse spans))))
                  (host-stage-forms (form stage-spans)
                    (loop for stage in (rest form)
                          for span in stage-spans
                          collect
                          (list
                           (host-head
                            (skip-reader-trivia (1+ (first span)))
                            (first stage))))))
           (let ((*package* package))
             (multiple-value-bind (preserved raw-preserved-end)
                 (%sexp-reader-prototype-read-one input
                                                  preserve-readtable
                                                  package
                                                  start)
               (let* ((preserved-end (trim-read-end raw-preserved-end))
                      (stage-spans (pipeline-stage-spans preserved))
                      (host-form
                        (if (eq (first preserved) :pipeline)
                            (cons (first preserved)
                                  (host-stage-forms preserved stage-spans))
                            (list (host-head
                                   (skip-reader-trivia (1+ start))
                                   (first preserved)))))
                      (trailing-position (skip-reader-trivia preserved-end)))
                 (when (< trailing-position (length input))
                   (error "A command island must contain exactly one form."))
                 (values preserved
                         host-form
                         start
                         preserved-end
                         stage-spans)))))
      (delete-package package))))

(defun %sexp-reader-prototype-command-name
    (head unquote-evaluator &optional force-marker-p)
  (let* ((name (%sexp-reader-prototype-value-string head unquote-evaluator))
         (force-external-p
          (and force-marker-p
               (plusp (length name))
               (char= (char name 0) #\^))))
    (when (and force-external-p (= (length name) 1))
      (error "The ^ marker requires a command name."))
    (values
     (if force-external-p
         (subseq name 1)
         name)
     force-external-p)))

(defun %sexp-reader-prototype-command-metadata (node force-external-p)
  (make-sexp-reader-prototype-command-metadata :command-node
                                               node
                                               :force-external-p
                                               force-external-p))

(defun %sexp-reader-prototype-command-island (input unquote-evaluator)
  (multiple-value-bind (form host-form start end stage-spans)
      (%sexp-reader-prototype-read-pair input)
    (unless (%sexp-reader-prototype-proper-list-p form)
      (error "An S-expression command island must be a proper list."))
    (unless form
      (error "An S-expression command island cannot be empty."))
    (labels ((argument-for-value (value)
               (make-command-arg
                (%sexp-reader-prototype-value-string value unquote-evaluator)
                (if (or (%sexp-reader-prototype-unquote-p value)
                        (stringp value)
                        (numberp value))
                    :single
                    nil)))
             (command-quote-style (value)
               (if (or (%sexp-reader-prototype-unquote-p value)
                       (stringp value)
                       (numberp value))
                   :single
                   nil))
             (make-command (command-form command-host-form span)
               (unless (%sexp-reader-prototype-proper-list-p command-form)
                 (error "Each pipeline stage must be a proper command list."))
               (unless command-form
                 (error "A command list cannot be empty."))
               (let ((head (first command-form)))
                 (multiple-value-bind (command force-external-p)
                     (%sexp-reader-prototype-command-name
                      head
                      unquote-evaluator
                      (symbolp head))
                   (when
                       (and (not force-external-p)
                            (%sexp-reader-prototype-host-form-p
                             command-host-form))
                     (error
                      "Host Common Lisp forms are outside the command prototype."))
                   (let* ((args (mapcar #'argument-for-value
                                        (rest command-form)))
                          (node (make-command-node
                                 command
                                 args
                                 span
                                 (command-quote-style head))))
                     (values node
                             (%sexp-reader-prototype-command-metadata
                              node
                              force-external-p)))))))
      (if (eq (first form) :pipeline)
          (let ((stage-nodes nil)
                (metadata nil))
            (unless (and (>= (length (rest form)) 2)
                         (= (length stage-spans) (length (rest form))))
              (error "A pipeline form requires at least two command stages."))
            (loop for stage in (rest form)
                  for host-stage in (rest host-form)
                  for stage-span in stage-spans
                  do (multiple-value-bind (node stage-metadata)
                         (make-command stage host-stage stage-span)
                       (push node stage-nodes)
                       (push stage-metadata metadata)))
            (values (make-pipeline-node (nreverse stage-nodes) (list start end))
                    (nreverse metadata)))
          (multiple-value-bind (node metadata)
              (make-command form host-form (list start end))
            (values node (list metadata)))))))

(defun %sexp-reader-prototype-separator-p (token)
  (member (token-type token)
          '(:semicolon :newline :and :or :ampersand)
          :test
          #'eq))

(defun %sexp-reader-prototype-separator (token)
  (case (token-type token)
    ((:semicolon :newline) :semi)
    (:and :and)
    (:or :or)
    (:ampersand :amp)))

(defun %sexp-reader-prototype-span-from-nodes (nodes)
  (list (first (ast-node-span (first nodes)))
        (second (ast-node-span (car (last nodes))))))

(defun %sexp-reader-prototype-bare-command (tokens &optional stderr-merge-p)
  (unless (and tokens (eq (token-type (first tokens)) :word))
    (error "Bare-line redirects must follow a command word in the prototype."))
  (let* ((command-token (first tokens))
         (first-fragment (first (token-fragments command-token)))
         (force-marker-p
          (and first-fragment
               (null (command-fragment-quote-style first-fragment))
               (plusp (length (command-fragment-value first-fragment)))
               (char= (char (command-fragment-value first-fragment) 0) #\^))))
    (multiple-value-bind (command force-external-p)
        (%sexp-reader-prototype-command-name
         (token-value command-token)
         nil
         force-marker-p)
      (let* ((arguments
               (append
                (mapcar
                 (lambda (token)
                   (make-command-arg
                    (token-value token)
                    (when (eq (token-type token) :word)
                      (token-quote-style token))
                    (eq (token-type token) :redirect)
                    (token-fragments token)))
                 (rest tokens))
                (when stderr-merge-p
                  (list (make-command-arg "2>&1")))))
             (span
               (list (token-start command-token)
                     (token-end (car (last tokens)))))
             (node
               (if force-external-p
                   (make-command-node
                    command
                    arguments
                    span
                    (token-quote-style command-token))
                   (make-command-node
                    command
                    arguments
                    span
                    (token-quote-style command-token)
                    (token-fragments command-token)))))
        (values node
                (%sexp-reader-prototype-command-metadata
                 node
                 force-external-p))))))

(defun %sexp-reader-prototype-bare-line (input)
  (let* ((tokenization (tokenize input))
         (tokens (tokenization-result-tokens tokenization))
         (segment nil)
         (pipeline-stages nil)
         (sequence-commands nil)
         (sequence-separators nil)
         (metadata nil)
         (pending-pipe-p nil))
    (when (tokenization-result-incomplete-p tokenization)
      (error "Incomplete bare-line input is outside the prototype."))
    (loop while (and tokens (eq (token-type (car (last tokens))) :newline))
          do (setf tokens (butlast tokens)))
    (labels ((validate-redirect-targets (stage-tokens)
               (loop for remaining on stage-tokens
                     for token = (first remaining)
                     when (and (eq (token-type token) :redirect)
                               (not (%redirect-targetless-p
                                     (token-value token))))
                       do (unless (and (rest remaining)
                                       (eq (token-type (second remaining)) :word))
                            (error "Redirect ~S requires a target."
                                   (token-value token)))))
             (finish-stage (&optional pipe-token)
               (unless segment
                 (error "Expected a command before the separator."))
               (let ((stage-tokens (nreverse segment)))
                 (validate-redirect-targets stage-tokens)
                 (multiple-value-bind (node command-metadata)
                     (%sexp-reader-prototype-bare-command
                      stage-tokens
                      (and pipe-token
                           (string= (token-value pipe-token) "|&")))
                   (push node pipeline-stages)
                   (push command-metadata metadata)))
               (setf segment nil
                     pending-pipe-p nil))
             (finish-pipeline ()
               (when segment
                 (finish-stage))
               (unless pipeline-stages
                 (error "Expected a command before the separator."))
               (let* ((stages (nreverse pipeline-stages))
                      (span (%sexp-reader-prototype-span-from-nodes stages))
                      (node
                       (if (rest stages)
                           (make-pipeline-node stages span)
                           (first stages))))
                 (push node sequence-commands)
                 (setf pipeline-stages nil)))
             (record-separator (token)
               (when pending-pipe-p
                 (error "A pipeline separator requires a right-hand command."))
               (finish-pipeline)
               (push (%sexp-reader-prototype-separator token)
                     sequence-separators)))
      (dolist (token tokens)
        (cond
          ((eq (token-type token) :pipe)
            (finish-stage token)
            (setf pending-pipe-p t))
          ((%sexp-reader-prototype-separator-p token)
           (record-separator token))
          ((member (token-type token) '(:word :redirect) :test #'eq)
           (push token segment)
           (setf pending-pipe-p nil))
          (t (error "Unsupported bare-line token: ~S" (token-type token)))))
      (when pending-pipe-p
        (error "A pipeline separator requires a right-hand command."))
      (when (or segment pipeline-stages)
        (finish-pipeline)))
    (let ((commands (nreverse sequence-commands))
          (separators (nreverse sequence-separators)))
      (when (and (= (length separators) (length commands))
                 (eq (car (last separators)) :semi))
        (setf separators (butlast separators)))
      (when (> (length separators) (length commands))
        (error "A bare-line sequence cannot end with this separator."))
      (when
          (and (= (length separators) (length commands))
               (not (eq (car (last separators)) :amp)))
        (error "A bare-line sequence cannot end with this separator."))
      (cond
        ((null commands) (values nil nil))
        ((null separators) (values (first commands) (nreverse metadata)))
        (t
         (values
          (make-sequence-node commands
                              separators
                              (%sexp-reader-prototype-span-from-nodes commands))
          (nreverse metadata)))))))

(defun parse-sexp-reader-prototype (input &key unquote-evaluator)
  (unless (stringp input)
    (error "Prototype input must be a string."))
  (let ((start (%sexp-reader-prototype-first-non-whitespace input)))
    (if (and (< start (length input)) (char= (char input start) #\())
        (%sexp-reader-prototype-command-island input unquote-evaluator)
        (%sexp-reader-prototype-bare-line input))))
