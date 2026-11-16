(in-package #:nshell.feature.kb)

;;; Lisp predicates the rule data calls through (:when ...) guards, and the
;;; foreign predicates that bind outputs.  They read only their arguments:
;;; no file I/O and no process start (D-65).

(defun string-prefix-p (prefix string)
  (and (stringp string)
       (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun option-word-p (word)
  (and (stringp word)
       (> (length word) 1)
       (char= (char word 0) #\-)))

(defun recursive-option-p (word)
  "True for --recursive or a short-option cluster that holds r or R."
  (and (option-word-p word)
       (or (string= word "--recursive")
           (and (char/= (char word 1) #\-)
                (find-if (lambda (character) (find character "rR"))
                         (subseq word 1))))))

(defun %split-path (word)
  (loop for start = 0 then (1+ end)
        for end = (position #\/ word :start start)
        collect (subseq word start end)
        while end))

(defun %normalize-path-components (components)
  "Fold empty, `.', and `..' components.  Return the remaining components and
whether a `..' tried to climb above the first one."
  (let ((stack nil)
        (escaped nil))
    (dolist (component components)
      (cond
        ((member component '("" ".") :test #'string=))
        ((string= component "..")
         (if stack (pop stack) (setf escaped t)))
        (t (push component stack))))
    (values (nreverse stack) escaped)))

(defun root-path-p (word)
  "True when WORD names the filesystem root, the home directory, or the
current directory after lexical normalization.  `//', `/./', `/..', and
`/x/..' are the root; a `..' above the root stays at the root.  The
filesystem is not consulted."
  (and (stringp word)
       (plusp (length word))
       (let ((parts (%split-path word)))
         (if (char= (char word 0) #\/)
             (let ((rest (%normalize-path-components (rest parts))))
               (or (null rest) (equal rest '("*"))))
             (and (member (first parts) '("~" "$HOME" ".") :test #'string=)
                  (multiple-value-bind (rest escaped)
                      (%normalize-path-components (rest parts))
                    (and (null rest) (not escaped))))))))

(defun harmless-environment-name-p (name)
  "True for environment names that only change locale, time zone, or
terminal presentation, so assigning them cannot change what a command runs.
The name must equal a listed one; LC_ needs a tail of A-Z and `_'."
  (and (stringp name)
       (or (member name '("LANG" "TZ" "NO_COLOR" "TERM" "COLUMNS") :test #'string=)
           (and (> (length name) 3)
                (string-prefix-p "LC_" name)
                (every (lambda (character)
                         (or (char<= #\A character #\Z) (char= character #\_)))
                       (subseq name 3))))))

(defun contains-p (needle word)
  (and (stringp word) (search needle word) t))

(defun force-push-option-p (word)
  (or (equal word "-f") (string-prefix-p "--force" word)))

;;; Closed-world argument specs (D-P1-5 2.2, 2.3).  A spec is the plist of
;;; one +safe-command-specs+ row.  The matchers return the words the spec
;;; does not allow, so NIL means every word matched.

(defun control-character-p (character)
  "True for C0 and C1 control characters, which a terminal may act on."
  (let ((code (char-code character)))
    (or (< code 32) (<= 127 code 159))))

(defun git-format-value-p (value)
  "True for a --format or --pretty value that cannot verify signatures.
%G placeholders run gpg, gpgsm, or ssh-keygen on the commit data."
  (not (search "%G" value)))

(defun %spec-value-p (type value)
  (and (stringp value)
       (ecase type
         (:any t)
         (:count (and (plusp (length value)) (every #'digit-char-p value)))
         (:git-format (git-format-value-p value)))))

(defun read-spec-options (spec words &key (permute t))
  "Read WORDS with SPEC's :FLAGS, :VALUE-FLAGS, :LONG, :VALUE-LONG, and
:EXACT.  :PLUS-OPTIONS rejects words beginning with + before `--'.
Return the operands, the words SPEC does not allow, and the words
left unread.  With PERMUTE, options may follow operands and only `--' ends
them; without it, the first operand or `--' ends the options and it and the
rest are left unread.  Long names match exactly, never by prefix."
  (let ((flags (getf spec :flags ""))
        (value-flags (getf spec :value-flags))
        (long (getf spec :long))
        (value-long (getf spec :value-long))
        (exact (getf spec :exact))
        (operands nil)
        (mismatches nil))
    (flet ((check-value (word type value)
             (unless (%spec-value-p type value)
               (push (if value (format nil "~a ~a" word value) word) mismatches))))
      (loop while words
            do (let ((word (pop words)))
                 (cond
                   ((string= word "--")
                    (if permute
                        (setf operands (revappend words operands)
                              words nil)
                        (return-from read-spec-options
                          (values (nreverse operands) (nreverse mismatches)
                                  (cons word words)))))
                   ((member word exact :test #'string=))
                   ((string-prefix-p "--" word)
                    (let* ((equals (position #\= word))
                           (name (subseq word 0 equals))
                           (type (second (assoc name value-long :test #'string=))))
                      (cond
                        ((and (null equals) (member name long :test #'string=)))
                        ((and type equals)
                         (check-value word type (subseq word (1+ equals))))
                        (type (check-value word type (pop words)))
                        (t (push word mismatches)))))
                   ((and (getf spec :plus-options)
                         (string-prefix-p "+" word))
                    (push word mismatches))
                   ((option-word-p word)
                    (loop for index from 1 below (length word)
                          for character = (char word index)
                          for type = (second (assoc (string character) value-flags
                                                    :test #'string=))
                          do (cond
                               ((find character flags))
                               (type
                                (check-value word type
                                             (if (< (1+ index) (length word))
                                                 (subseq word (1+ index))
                                                 (pop words)))
                                (return))
                               (t (push word mismatches) (return)))))
                   (permute (push word operands))
                   (t
                    (return-from read-spec-options
                      (values (nreverse operands) (nreverse mismatches)
                              (cons word words))))))))
    (values (nreverse operands) (nreverse mismatches) nil)))

(defun %option-spec-mismatches (spec arguments)
  (multiple-value-bind (operands mismatches) (read-spec-options spec arguments)
    (let* ((options (ldiff arguments (member "--" arguments :test #'string=)))
           (limit (if (some (lambda (word)
                              (member word (getf spec :listing-options)
                                      :test #'string=))
                            options)
                      :any
                      (getf spec :positionals :any))))
      (append mismatches
              (and (integerp limit) (nthcdr limit operands))))))

(defun %subcommand-spec-mismatches (spec arguments)
  ;; Words before the subcommand are global options (git -c, -C, ...).
  (let ((entry (assoc (first arguments) (getf spec :subcommands) :test #'equal)))
    (cond
      ((null arguments) (list "(no subcommand)"))
      ((null entry) (list (first arguments)))
      (t (%option-spec-mismatches (rest entry) (rest arguments))))))

(defun %find-spec-mismatches (spec arguments)
  ;; `--' is skipped only as the first word.  BSD and GNU find still read an
  ;; expression after it, so the primaries are checked as before.
  (let ((words (if (equal (first arguments) "--") (rest arguments) arguments))
        (mismatches nil))
    (loop while (member (first words) (getf spec :leading-options) :test #'equal)
          do (pop words))
    (loop while (and words
                     (not (option-word-p (first words)))
                     (not (member (first words) '("!" "(" ")") :test #'string=)))
          do (pop words))
    (loop while words
          do (let ((word (pop words)))
               (cond
                 ((member word (getf spec :primaries) :test #'string=))
                 ((member word (getf spec :value-primaries) :test #'string=)
                  (unless words (push word mismatches))
                  (pop words))
                 (t (push word mismatches)))))
    (nreverse mismatches)))

(defun %echo-spec-mismatches (name arguments)
  ;; The builtins print a control character or turn `\e' and `\0NNN' into
  ;; one, which can drive the terminal (OSC 52, OSC 133).
  (let ((mismatches
          (remove-if-not (lambda (word)
                           (or (find #\\ word) (some #'control-character-p word)))
                         arguments)))
    (if (string= name "echo")
        (append (remove-if (lambda (word)
                             (or (not (option-word-p word)) (string= word "-n")))
                           arguments)
                mismatches)
        (let ((format (if (equal (first arguments) "--")
                          (second arguments)
                          (first arguments))))
          (if (and format (option-word-p format))
              (cons format mismatches)
              mismatches)))))

(defun spec-argument-mismatches (spec-row arguments)
  "Return the words of ARGUMENTS that SPEC-ROW, a (NAME . SPEC) row of the
spec table, does not allow.  NIL means the arguments match the spec."
  (destructuring-bind (name &rest spec) spec-row
    (remove-duplicates
     (case (getf spec :grammar)
       (:find (%find-spec-mismatches spec arguments))
       (:echo (%echo-spec-mismatches name arguments))
       (t (if (getf spec :subcommands)
              (%subcommand-spec-mismatches spec arguments)
              (%option-spec-mismatches spec arguments))))
     :test #'string= :from-end t)))

(defun edit-distance (left right)
  "Optimal string alignment distance: insertions, deletions, substitutions,
and transpositions of adjacent characters each cost 1."
  (let* ((rows (1+ (length left)))
         (columns (1+ (length right)))
         (table (make-array (list rows columns) :element-type 'fixnum)))
    (dotimes (row rows) (setf (aref table row 0) row))
    (dotimes (column columns) (setf (aref table 0 column) column))
    (loop for row from 1 below rows
          do (loop for column from 1 below columns
                   for cost = (if (char= (char left (1- row))
                                         (char right (1- column)))
                                  0
                                  1)
                   do (setf (aref table row column)
                            (min (1+ (aref table (1- row) column))
                                 (1+ (aref table row (1- column)))
                                 (+ (aref table (1- row) (1- column)) cost)))
                      (when (and (> row 1) (> column 1)
                                 (char= (char left (1- row))
                                        (char right (- column 2)))
                                 (char= (char left (- row 2))
                                        (char right (1- column))))
                        (setf (aref table row column)
                              (min (aref table row column)
                                   (+ (aref table (- row 2) (- column 2))
                                      cost))))))
    (aref table (1- rows) (1- columns))))

(cl-prolog-kit:define-foreign-predicate (string-edit-distance left right distance)
    (rulebase environment depth emit)
  (declare (ignore rulebase depth))
  (let ((left (cl-prolog-kit:logic-substitute left environment))
        (right (cl-prolog-kit:logic-substitute right environment)))
    (when (and (stringp left) (stringp right))
      (multiple-value-bind (extended ok)
          (cl-prolog-kit:unify distance (edit-distance left right) environment)
        (when ok (funcall emit extended))))))

(cl-prolog-kit:define-foreign-predicate (splice-text text start end insert result)
    (rulebase environment depth emit)
  (declare (ignore rulebase depth))
  (let ((text (cl-prolog-kit:logic-substitute text environment))
        (start (cl-prolog-kit:logic-substitute start environment))
        (end (cl-prolog-kit:logic-substitute end environment))
        (insert (cl-prolog-kit:logic-substitute insert environment)))
    (when (and (stringp text) (stringp insert)
               (typep start 'fixnum) (typep end 'fixnum)
               (<= 0 start end (length text)))
      (multiple-value-bind (extended ok)
          (cl-prolog-kit:unify result
                               (concatenate 'string
                                            (subseq text 0 start)
                                            insert
                                            (subseq text end))
                               environment)
        (when ok (funcall emit extended))))))
