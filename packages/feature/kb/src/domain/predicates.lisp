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
terminal presentation, so assigning them cannot change what a command runs."
  (or (member name '("LANG" "TZ" "NO_COLOR" "TERM" "COLUMNS") :test #'equal)
      (string-prefix-p "LC_" name)))

(defun contains-p (needle word)
  (and (stringp word) (search needle word) t))

(defun force-push-option-p (word)
  (or (equal word "-f") (string-prefix-p "--force" word)))

(defun find-exec-action-p (word)
  (and (member word '("-exec" "-ok" "-execdir" "-okdir") :test #'equal) t))

(defun find-write-action-p (word)
  (or (equal word "-delete")
      (some (lambda (prefix) (string-prefix-p prefix word))
            '("-fprint" "-fprintf" "-fls"))))

(defun ripgrep-preprocessor-option-p (word)
  (or (string-prefix-p "--pre" word) (equal word "--search-zip")))

(defparameter +read-only-git-options+
  '(("log" "--oneline" "--decorate" "--stat" "--name-only" "--name-status"
     "--graph" "--all" "--follow" "--no-merges" "-p" "-n" "--")
    ("show" "--stat" "--patch" "-p" "--name-only" "--name-status" "--pretty"
     "--format" "--no-patch" "--")
    ("status" "-s" "--short" "-b" "--branch" "--porcelain" "--long" "-v"
     "--verbose" "--")
    ("diff" "--stat" "--shortstat" "--numstat" "--cached" "--staged"
     "--name-only" "--name-status" "-p" "--patch" "--no-ext-diff"
     "--no-textconv" "--"))
  "Options each read-only git subcommand accepts.  An option outside these
lists (--output, --ext-diff, -c ...) leaves the command to confirm.")

(defparameter +read-only-git-option-prefixes+
  '(("log" "--pretty=" "--format=")
    ("show" "--pretty=" "--format=")
    ("status" "--porcelain=")
    ("diff")))

(defun %read-only-git-branch-arguments-p (options)
  ;; A bare name creates a branch; -l creates its reflog, not a listing.
  (or (null options)
      (and (equal (first options) "--list")
           (loop with patterns-only = nil
                 for word in (rest options)
                 always (cond
                          (patterns-only t)
                          ((string= word "--") (setf patterns-only t))
                          (t (not (string-prefix-p "-" word))))))))

(defun read-only-git-arguments-p (arguments)
  "True when ARGUMENTS (after `git') stay inside the read-only grammar."
  (let ((subcommand (first arguments))
        (options (rest arguments)))
    (cond
      ((not (stringp subcommand)) nil)
      ((string= subcommand "branch")
       (%read-only-git-branch-arguments-p options))
      ((string= subcommand "remote")
       ;; Only the no-subcommand listing grammar is read-only.
       (every (lambda (word) (member word '("-v" "--verbose") :test #'equal))
              options))
      (t
       (let ((allowed (rest (assoc subcommand +read-only-git-options+
                                   :test #'string=)))
             (prefixes (rest (assoc subcommand +read-only-git-option-prefixes+
                                    :test #'string=))))
         (and (assoc subcommand +read-only-git-options+ :test #'string=)
              (every (lambda (word)
                       (or (not (string-prefix-p "-" word))
                           (member word allowed :test #'string=)
                           (some (lambda (prefix) (string-prefix-p prefix word))
                                 prefixes)))
                     options)))))))

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
