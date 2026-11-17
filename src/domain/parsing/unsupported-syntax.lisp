(in-package #:nshell.domain.parsing)

;;; Rejection of the bare-line syntax listed in +UNSUPPORTED-BARE-LINE-SYNTAX+
;;; (language/L5-bare-line.md 5.3). READ-SUBMISSION walks every bare-line AST
;;; it reads, command substitutions included, and signals one
;;; UNSUPPORTED-SYNTAX-ERROR for the first rejected head, so no part of the
;;; input runs.

(define-condition unsupported-syntax-error (sexp-reader-error)
  ((head :initarg :head :initform nil :reader unsupported-syntax-error-head)
   (rewrite :initarg :rewrite :initform nil
            :reader unsupported-syntax-error-rewrite))
  (:default-initargs :error-code "E_UNSUPPORTED_SYNTAX"))

(defun %unsupported-syntax-row (head)
  (find head +unsupported-bare-line-syntax+
        :key (lambda (row) (getf row :head))
        :test #'string=))

(defun %unsupported-syntax-message (row rewrite)
  (format nil "E_UNSUPPORTED_SYNTAX: bare-line `~a` is not supported; ~:[~a~;use ~:*~a~]"
          (getf row :head) rewrite (getf row :advice)))

(defun signal-unsupported-syntax (head span &key source-path source-map rewrite)
  "Signal UNSUPPORTED-SYNTAX-ERROR for HEAD, a :HEAD of
+UNSUPPORTED-BARE-LINE-SYNTAX+, at SPAN, a [start,end) list of offsets that
SOURCE-MAP maps to the file SOURCE-PATH names. REWRITE replaces the row's
generic S-expression."
  (let* ((row (or (%unsupported-syntax-row head)
                  (error "~s is not rejected bare-line syntax" head)))
         (rewrite (or rewrite (getf row :rewrite))))
    (error 'unsupported-syntax-error
           :source-span span
           :source-path source-path
           :source-map source-map
           :cause (%unsupported-syntax-message row rewrite)
           :head head
           :rewrite rewrite)))

(defun %rejected-head-row (node)
  "The row rejecting NODE's head when NODE is a command node whose head is
written unquoted and without ^."
  (and (command-node-p node)
       (null (command-node-command-quote-style node))
       (not (command-node-force-external-p node))
       (command-node-name-span node)
       (%unsupported-syntax-row (command-node-command node))))

(defun %rejected-head-p (node name)
  (let ((row (%rejected-head-row node)))
    (and row (string= (getf row :head) name))))

(defun %without-line-continuations (text)
  "TEXT with each line continuation, a backslash-newline and the blanks around
it, read as one space."
  (let ((out (make-array (length text) :element-type 'character
                                        :fill-pointer 0)))
    (flet ((blank-p (character) (member character '(#\Space #\Tab))))
      (loop with index = 0
            while (< index (length text))
            do (let* ((character (char text index))
                      (continuation-end
                        (and (char= character #\\)
                             (< (1+ index) (length text))
                             (char= (char text (1+ index)) #\Newline)
                             (+ index 2))))
                 (if continuation-end
                     (progn
                       (loop while (and (plusp (fill-pointer out))
                                        (blank-p (aref out (1- (fill-pointer out)))))
                             do (decf (fill-pointer out)))
                       (vector-push #\Space out)
                       (setf index continuation-end)
                       (loop while (and (< index (length text))
                                        (blank-p (char text index)))
                             do (incf index)))
                     (progn
                       (vector-push character out)
                       (incf index))))))
    (coerce out 'simple-string)))

(defun %trimmed-source-text (source start end)
  (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return)
                           (%without-line-continuations (subseq source start end)))))
    (and (plusp (length text)) text)))

(defun %node-source-text (source node)
  (let ((span (ast-node-span node)))
    (and span (%trimmed-source-text source (first span) (second span)))))

(defun %stage-nodes (node)
  (if (pipeline-node-p node) (pipeline-node-commands node) (list node)))

(defun %not-word-p (form)
  (and (command-arg-p form)
       (null (command-arg-quote-style form))
       (string= (command-arg-value form) "not")
       (command-arg-source-span form)))

(defun %after-head-rewrite (source node)
  "The S-expression for what NODE, a command or pipeline node, runs after the
head word of its first command: each further leading not wraps it in (not …).
NIL when no command name follows, as in `not <<< x'."
  (let* ((first-command (first (%stage-nodes node)))
         (arguments (command-node-argument-forms first-command))
         (start (text-span-end (command-node-name-span first-command)))
         (end (second (ast-node-span node)))
         (nots 0))
    (loop while (and arguments (%not-word-p (first arguments)))
          do (setf start (second (command-arg-source-span (pop arguments))))
             (incf nots))
    (let ((next (first arguments)))
      (when (and (command-arg-p next)
                 (command-arg-source-span next)
                 (null (%trimmed-source-text
                        source start (first (command-arg-source-span next)))))
        (let ((text (%trimmed-source-text source start end)))
          (when text
            (let ((expression (format nil "(~a)" text)))
              (loop repeat nots
                    do (setf expression (format nil "(not ~a)" expression)))
              expression)))))))

(defun %operand-rewrite (source node)
  "NODE, a command or pipeline node, as an S-expression operand, or NIL when
it holds a rejected head other than a leading not."
  (let ((rejected (remove-if-not #'%rejected-head-row (%stage-nodes node))))
    (cond
      ((null rejected)
       (let ((text (%node-source-text source node)))
         (and text (format nil "(~a)" text))))
      ((and (equal rejected (list (first (%stage-nodes node))))
            (%rejected-head-p (first rejected) "not"))
       (let ((operand (%after-head-rewrite source node)))
         (and operand (format nil "(not ~a)" operand)))))))

(defun %connective-p (node)
  (or (%rejected-head-p node "and") (%rejected-head-p node "or")))

(defun %and-or-lists (separators count)
  "The and-or lists (L5.1) of a sequence of COUNT commands joined by
SEPARATORS, each as (START END TERMINATOR): the commands START to END joined
by && and ||, and the :SEMI, :AMP or NIL that follows them."
  (loop with start = 0
        for index from 0 below count
        for separator = (nth index separators)
        unless (member separator '(:and :or))
          collect (list start (1+ index) separator)
          and do (setf start (1+ index))))

(defun %and-or-rewrite (source commands separators list previous)
  "The S-expression for LIST, an and-or list of COMMANDS, with && as (and …)
and || as (or …) folded from the left (L3.5, L5.1). When LIST starts with an
and or or command, PREVIOUS is the S-expression for the lists before it.
NIL when a part cannot be written. A list that starts with and may continue
only with &&, and one that starts with or only with ||: fish applies and/or
to the whole list (a; or b && c is a; or (b && c)), while v0.7.0 ran and/or
as a command inside it ((a; or b) && c), so other lists have no single
meaning."
  (destructuring-bind (start end terminator) list
    (declare (ignore terminator))
    (let* ((head (nth start commands))
           (connective (and (%connective-p head) (command-node-command head)))
           (expression
             (if connective
                 (let ((operand (%after-head-rewrite source head)))
                   (and previous operand
                        (format nil "(~a ~a ~a)" connective previous operand)))
                 (%operand-rewrite source head))))
      (loop for position from (1+ start) below end
            for operator = (if (eq (nth (1- position) separators) :and) "and" "or")
            while expression
            do (setf expression
                     (and (or (null connective) (string= operator connective))
                          (let ((operand (%operand-rewrite source (nth position commands))))
                            (and operand
                                 (format nil "(~a ~a ~a)" operator expression operand))))))
      expression)))

(defun %connective-rewrite (source commands separators index)
  "The S-expression for the and-or list holding COMMANDS[INDEX] and the lists
around it that and or or joins to it after a ; or a newline, or NIL when a
part cannot be written with the same meaning, as for a list run in the
background."
  (let* ((lists (%and-or-lists separators (length commands)))
         (first (position-if (lambda (list) (< index (second list))) lists))
         (last first))
    (flet ((joined-p (before)
             (and (eq (third (nth before lists)) :semi)
                  (%connective-p (nth (first (nth (1+ before) lists)) commands)))))
      (loop while (and (plusp first) (joined-p (1- first)))
            do (decf first))
      (loop while (and (< (1+ last) (length lists)) (joined-p last))
            do (incf last))
      (unless (eq (third (nth last lists)) :amp)
        (let ((expression (%and-or-rewrite source commands separators
                                           (nth first lists) nil)))
          (loop for list in (subseq lists (1+ first) (1+ last))
                while expression
                do (setf expression (%and-or-rewrite source commands separators
                                                     list expression)))
          expression)))))

(defun %short-value-option-p (character)
  (member (format nil "-~c" character) +fish-function-value-options+
          :test #'string=))

(defun %function-name (node)
  "The name the fish function command NODE defines: its first argument that
is neither an option nor an option's value, or NIL when it has none."
  (loop with words = (mapcar #'command-arg-value (command-node-args node))
        while words
        do (let ((word (pop words)))
             (cond
               ((string= word "--")
                (return (first words)))
               ((and (> (length word) 2) (string= word "--" :end1 2))
                (when (and (not (find #\= word))
                           (member word +fish-function-value-options+
                                   :test #'string=))
                  (pop words)))
               ((and (> (length word) 1) (char= (char word 0) #\-))
                ;; -Sd desc and -ddesc: the value is the rest of the word after
                ;; the first short option that takes one, else the next word.
                (let ((value-option (position-if #'%short-value-option-p word
                                                 :start 1)))
                  (when (eql value-option (1- (length word)))
                    (pop words))))
               (t
                (return word))))))

(defun %function-rewrite (source commands index)
  "(defcmd NAME () BODY…) for the function command at COMMANDS[INDEX], with
the commands up to the next end as the body, or NIL when it names no
function."
  (let ((name (%function-name (nth index commands))))
    (when (plusp (length name))
      (let* ((end (position-if (lambda (command)
                                 (and (command-node-p command)
                                      (null (command-node-command-quote-style command))
                                      (string= (command-node-command command) "end")))
                               commands :start (1+ index)))
             (body (and end
                        (loop for position from (1+ index) below end
                              collect (%operand-rewrite source (nth position commands))))))
        (format nil "(defcmd ~a () ~a)"
                name
                (if (and body (every #'identity body))
                    (format nil "~{~a~^ ~}" body)
                    "…"))))))

(defun %statement-rewrite (source commands separators index row)
  (let ((head (getf row :head)))
    (cond
      ((string= head "function") (%function-rewrite source commands index))
      ((member head '("and" "or" "not") :test #'string=)
       (%connective-rewrite source commands separators index)))))

(defun %finding (node row rewrite offset)
  (let ((name-span (command-node-name-span node)))
    (list :head (getf row :head)
          :span (list (+ offset (text-span-start name-span))
                      (+ offset (text-span-end name-span)))
          :rewrite rewrite)))

(defun %command-substitution-bodies (source start end)
  "The [start,end) spans of the $( ) bodies in SOURCE between START and END,
outside single quotes. $(( )) is arithmetic, not a command."
  (let ((bodies nil)
        (position start)
        (double-quoted nil))
    (loop while (< position end)
          do (let ((character (char source position)))
               (cond
                 ((char= character #\\)
                  (incf position 2))
                 ((and (char= character #\') (not double-quoted))
                  (setf position
                        (1+ (or (position #\' source :start (1+ position) :end end)
                                (1- end)))))
                 ((char= character #\")
                  (setf double-quoted (not double-quoted))
                  (incf position))
                 ((and (char= character #\$)
                       (< (1+ position) end)
                       (char= (char source (1+ position)) #\()
                       (not (and (< (+ position 2) end)
                                 (char= (char source (+ position 2)) #\())))
                  (let ((close (%balanced-substitution-end source (1+ position))))
                    (if (and close (< close end))
                        (progn
                          (push (list (+ position 2) close) bodies)
                          (setf position (1+ close)))
                        (setf position end))))
                 (t (incf position)))))
    (nreverse bodies)))

(defun %command-word-spans (node)
  (let ((words (append (command-node-environment-assignments node)
                       (command-node-argument-forms node)
                       (loop for redirect in (command-node-redirects node)
                             for target = (ast-redirect-entry-target redirect)
                             when (command-arg-p target) collect target))))
    (loop for word in words
          for span = (and (command-arg-p word) (command-arg-source-span word))
          when span collect span)))

(defun %find-in-substitution (source body-span offset)
  "The finding in the $( ) body at BODY-SPAN of SOURCE. A body the bare-line
reader cannot read is left to run time."
  (destructuring-bind (start end) body-span
    (let* ((body (subseq source start end))
           (form (handler-case
                     (let ((*sexp-reader-state* (%make-sexp-reader-state :source body)))
                       (%sexp-reader-read-bare-line body))
                   (error () nil))))
      (and form (%find-unsupported-syntax form body (+ offset start))))))

(defun %find-in-command (source node offset)
  (or (loop for span in (%command-word-spans node)
            thereis (loop for body in (%command-substitution-bodies
                                       source (first span) (second span))
                          thereis (%find-in-substitution source body offset)))
      (loop for redirect in (command-node-redirects node)
            for target = (ast-redirect-entry-target redirect)
            thereis (and (redirect-procsub-target-p target)
                         (%find-unsupported-syntax
                          (redirect-procsub-target-form target) source offset)))))

(defun %find-in-statement (source commands separators index offset)
  (let ((statement (nth index commands)))
    (loop for stage in (%stage-nodes statement)
          for row = (%rejected-head-row stage)
          thereis (if row
                      (%finding stage row
                                (and (eq stage (first (%stage-nodes statement)))
                                     (%statement-rewrite source commands separators
                                                         index row))
                                offset)
                      (and (command-node-p stage)
                           (%find-in-command source stage offset))))))

(defun %find-unsupported-syntax (form source offset)
  "The first rejected head in FORM, a bare-line AST read from SOURCE, as a
plist of :HEAD, :SPAN (offset by OFFSET) and :REWRITE, or NIL."
  (multiple-value-bind (commands separators)
      (if (sequence-node-p form)
          (values (sequence-node-commands form) (sequence-node-separators form))
          (values (list form) nil))
    (loop for index from 0 below (length commands)
          thereis (%find-in-statement source commands separators index offset))))

(defun reject-unsupported-bare-line-syntax (form source &key source-path source-map)
  "Signal UNSUPPORTED-SYNTAX-ERROR when FORM, the bare-line AST READ-SUBMISSION
read from SOURCE, uses syntax +UNSUPPORTED-BARE-LINE-SYNTAX+ rejects."
  (let ((finding (%find-unsupported-syntax form source 0)))
    (when finding
      (signal-unsupported-syntax (getf finding :head) (getf finding :span)
                                 :source-path source-path
                                 :source-map source-map
                                 :rewrite (getf finding :rewrite)))))
