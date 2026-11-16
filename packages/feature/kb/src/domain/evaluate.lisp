(in-package #:nshell.feature.kb)

;;; Bounded evaluation of the classify and diagnose rulebases.

(defparameter *classify-max-inferences* 200000
  "Inference budget of one knowledge-base query (D-65).")

(defparameter *classify-deadline-seconds* 1
  "Wall-clock budget of one knowledge-base query, in seconds (D-65).")

(defvar *user-classify-rulebase* nil
  "A rulebase of user classify/4 rules, or NIL.  It is evaluated apart from
the built-in rules and its results are capped at :CONFIRM (D-80).  P5-7 loads
rules.pl into it; until then only tests set it.")

(defparameter +level-ranks+ '((:safe . 0) (:confirm . 1) (:block . 2)))

(defparameter +subject-fact-schema+
  '((command :none "") (invoked-as :none "") (arguments :none ())
    (argument :none "") (subcommand :none "") (option :none "")
    (operand :none "") (redirect :none "") (wraps :none)
    (nested :none :safe "" "") (embedded :none :safe "" "")
    (unparsable :none "") (form-redirect :none) (sexp-unforced :none)
    (unclassifiable :none "") (assignment :none "") (wrapper-option :none "")
    (spec-command :none) (spec-match :none) (argument-not-allowed :none "")
    (opaque-wrapper :none) (redirect-not-allowed :none "") (word :none "")
    (shell-function :none))
  "One clause per input predicate about the atom :NONE, which never names a
subject.  A rule that asks about an input the evaluator did not supply then
fails instead of raising existence_error, while a misspelled predicate in
the rule data still raises.")

(defun make-user-classify-rulebase (clauses)
  "Build a user rulebase from CLAUSES, each (HEAD . BODY) as data."
  (cl-prolog-kit:make-rulebase
   :clauses (mapcar (lambda (clause)
                      (cl-prolog-kit:make-clause (first clause) (rest clause)))
                    clauses)))

(defun %level-rank (level)
  (cdr (assoc level +level-ranks+)))

(defun %query-findall (rulebase facts template goal)
  "Return every TEMPLATE instance proving GOAL in RULEBASE extended by FACTS,
collected with findall under the inference and deadline budgets."
  (let ((extended (cl-prolog-kit:rulebase-extend
                   rulebase
                   (mapcar #'cl-prolog-kit:make-clause facts))))
    (cl-prolog-kit:solution-binding
     '?all
     (cl-prolog-kit:query-prolog-first
      extended
      (list 'cl-prolog-kit:findall template goal '?all)
      :max-inferences *classify-max-inferences*
      :deadline (cl-prolog-kit:prolog-deadline-after
                 *classify-deadline-seconds*)))))

(defun %row-resolution-p (row resolution)
  (eq (getf (rest row) :resolution :external) (or resolution :external)))

(defun find-command-spec (word &optional resolution)
  "Return the +safe-command-specs+ row named exactly WORD for a command the
executor resolves as RESOLUTION (:BUILTIN or :EXTERNAL, the default), or
NIL.  Wrapper rows describe how a command runs another one, not a safe
command."
  (find-if (lambda (row)
             (and (equal (first row) word)
                  (not (getf (rest row) :wrapper))
                  (%row-resolution-p row resolution)))
           +safe-command-specs+))

(defun %find-wrapper-row (name resolution)
  (find-if (lambda (row)
             (and (equal (first row) name)
                  (getf (rest row) :wrapper)
                  (%row-resolution-p row resolution)))
           +safe-command-specs+))

(defun %word-basename (word)
  (let ((separator (position #\/ word :from-end t)))
    (if separator (subseq word (1+ separator)) word)))

(defun %assignment-word-p (word)
  (and (find #\= word) t))

(defun assignment-name (word)
  "Return the name a NAME=value word assigns: the text before the first `='.
The name is not checked against any grammar (D-P1-5 2.4)."
  (subseq word 0 (position #\= word)))

(defun %wrapper-command (spec words)
  "Skip the wrapper options, assignments, and operands at the start of WORDS.
Return the command words (a tail of WORDS), the assigned names, and the
option words."
  (let ((value-letters (format nil "~{~a~}~a"
                               (mapcar #'first (getf spec :value-flags))
                               (getf spec :skip-values "")))
        (assignments-p (getf spec :assignments))
        (names nil)
        (options nil))
    (loop while words
          do (let ((word (first words)))
               (cond
                 ((string= word "--")
                  (push (pop words) options)
                  (return))
                 ((option-word-p word)
                  (push (pop words) options)
                  (unless (string-prefix-p "--" word)
                    (loop for index from 1 below (length word)
                          when (find (char word index) value-letters)
                            do (when (= index (1- (length word))) (pop words))
                               (return))))
                 ((and assignments-p (%assignment-word-p word))
                  (push (assignment-name (pop words)) names))
                 (t (return)))))
    (loop while (and assignments-p words (%assignment-word-p (first words)))
          do (push (assignment-name (pop words)) names))
    (values (nthcdr (getf spec :operands 0) words)
            (nreverse names)
            (nreverse options))))

(defun %dash-c-script (arguments)
  "Return SCRIPT of `sh -c SCRIPT', or NIL when -c is not given."
  (let ((dash-c nil)
        (words arguments))
    (loop while (and words
                     (option-word-p (first words))
                     (string/= (first words) "--"))
          do (let ((word (pop words)))
               (unless (string-prefix-p "--" word)
                 (when (find #\c word :start 1) (setf dash-c t))
                 (when (find (char word (1- (length word))) "oO") (pop words)))))
    (when (equal (first words) "--") (pop words))
    (and dash-c (first words))))

(defun command-wrapper (word arguments &optional resolution)
  "Describe how the command WORD with ARGUMENTS runs another command
(D-P1-5 2.4), or return NIL when it does not.  The values are KIND
(:TRANSPARENT or :OPAQUE), the argv of the command it runs, the wrapper
words its spec row does not allow, the environment names it assigns, the
options given to env, and source text that runs as a command line (sh -c
SCRIPT, eval with one argument).  A transparent wrapper must be written as
a bare name; with a path it is opaque.  RESOLUTION is how the executor
resolves WORD (:BUILTIN or :EXTERNAL, the default); a row written for a
builtin applies only to the builtin.  A seventh value says how the wrapped
command is resolved: :BY-NAME like a typed command, else :EXTERNAL."
  (let* ((name (%word-basename word))
         (row (%find-wrapper-row name resolution))
         (spec (rest row))
         (runs (getf spec :runs :external)))
    (when (and row
               (not (and (rest arguments)
                         (member (first arguments) (getf spec :query-options)
                                 :test #'equal))))
      (case (getf spec :source)
        (:eval
         (if (= (length arguments) 1)
             (values :opaque nil nil nil nil (first arguments))
             (values :opaque arguments nil nil nil nil :by-name)))
        (:dash-c
         (let ((script (%dash-c-script arguments)))
           (when script
             (values :opaque nil nil nil nil script))))
        (t
         (multiple-value-bind (command names options)
             (%wrapper-command spec arguments)
           (let ((env-options (and (getf spec :opaque-on-options) options)))
             (cond
               ((or (string/= word name)
                    (eq (getf spec :wrapper) :opaque)
                    env-options)
                (values :opaque command nil names env-options nil runs))
               (command
                (let ((own-words (remove-if (if (getf spec :assignments)
                                                #'%assignment-word-p
                                                (constantly nil))
                                            (ldiff arguments command))))
                  (values :transparent
                          command
                          (%option-spec-mismatches
                           (list* :positionals (getf spec :operands 0) spec)
                           own-words)
                          names
                          nil
                          nil
                          runs)))))))))))

(defun %mismatch-text (words)
  (format nil "arguments outside the command's allowed form: ~{~a~^, ~}" words))

(defun %subject-facts (&key command invoked-as resolution arguments nested
                         embedded wraps
                         opaque wrapper-mismatches unparsable unclassifiable
                         form-redirect sexp-unforced assignments wrapper-options
                         writes redirect-problems words)
  (let ((facts (copy-list +subject-fact-schema+)))
    (flet ((add (&rest fact) (push fact facts)))
      (when command
        (add 'command 'subject command)
        (add 'invoked-as 'subject (or invoked-as command))
        (add 'arguments 'subject (copy-list arguments))
        (when arguments
          (add 'subcommand 'subject (first arguments)))
        (loop with operands-only = nil
              for word in arguments
              do (add 'argument 'subject word)
                 (cond
                   (operands-only (add 'operand 'subject word))
                   ((string= word "--") (setf operands-only t))
                   ((option-word-p word) (add 'option 'subject word))
                   (t (add 'operand 'subject word))))
        (let ((spec (and (not wraps)
                         (find-command-spec (or invoked-as command) resolution))))
          (when spec
            (add 'spec-command 'subject)
            (let ((mismatches (spec-argument-mismatches spec arguments)))
              (if mismatches
                  (add 'argument-not-allowed 'subject (%mismatch-text mismatches))
                  (add 'spec-match 'subject))))))
      ;; Redirects come from the AST, not from the argument words (2.5).
      (dolist (target writes) (add 'redirect 'subject target))
      (dolist (text redirect-problems) (add 'redirect-not-allowed 'subject text))
      (dolist (word words) (add 'word 'subject word))
      (when wraps (add 'wraps 'subject))
      (when (eq resolution :function) (add 'shell-function 'subject))
      (when opaque (add 'opaque-wrapper 'subject))
      (when wrapper-mismatches
        (add 'argument-not-allowed 'subject (%mismatch-text wrapper-mismatches)))
      (dolist (name assignments) (add 'assignment 'subject name))
      (dolist (option wrapper-options) (add 'wrapper-option 'subject option))
      (dolist (reason nested)
        (add 'nested 'subject (first reason) (second reason) (third reason)))
      (dolist (reason embedded)
        (add 'embedded 'subject (first reason) (second reason) (third reason)))
      (dolist (text unparsable) (add 'unparsable 'subject text))
      (dolist (text unclassifiable) (add 'unclassifiable 'subject text))
      (when form-redirect (add 'form-redirect 'subject))
      (when sexp-unforced (add 'sexp-unforced 'subject)))
    (nreverse facts)))

(defun %classify-solutions (rulebase facts)
  (mapcar (lambda (solution) (copy-tree solution))
          (%query-findall rulebase facts
                          '(?level ?rule ?text)
                          '(classify subject ?level ?rule ?text))))

(defun %builtin-solutions (facts)
  (handler-case (%classify-solutions *builtin-classify-rulebase* facts)
    (cl-prolog-kit:prolog-resource-error ()
      (list (list :block "kb/evaluation-limit"
                  "the safety rules exceeded their evaluation budget")))
    (error ()
      (list (list :block "kb/evaluation-error"
                  "the safety rules could not be evaluated")))))

(defun %user-solutions (facts)
  (when *user-classify-rulebase*
    (handler-case
        (mapcar (lambda (solution)
                  (destructuring-bind (level rule text) solution
                    (list (if (eq level :safe) :safe :confirm) rule text)))
                (%classify-solutions *user-classify-rulebase* facts))
      (error ()
        (list (list :confirm "kb/user-rules-error"
                    "user safety rules could not be evaluated"))))))

(defun %top-level-reasons (solutions)
  "Return the highest level among SOLUTIONS and its (RULE . TEXT) reasons."
  (let ((level nil)
        (reasons nil))
    (dolist (solution solutions)
      (destructuring-bind (candidate rule text) solution
        ;; An unknown level is a rule-data defect; it counts as :BLOCK.
        (let ((candidate (if (%level-rank candidate) candidate :block))
              (reason (cons rule text)))
          (cond
            ((or (null level) (> (%level-rank candidate) (%level-rank level)))
             (setf level candidate
                   reasons (list reason)))
            ((and (eq candidate level)
                  (not (member reason reasons :test #'equal)))
             (push reason reasons))))))
    (if level
        (values level (nreverse reasons))
        (values :block
                (list (cons "kb/no-rule"
                            "no safety rule applied to the command"))))))

(defun classify-subject (&rest subject &key command invoked-as resolution
                                         arguments nested
                                         embedded wraps opaque wrapper-mismatches
                                         unparsable unclassifiable form-redirect
                                         sexp-unforced assignments wrapper-options
                                         writes redirect-problems words)
  "Classify one subject with the built-in and user rules.

COMMAND is the basename and INVOKED-AS the command word as written;
RESOLUTION is how the executor resolves it: :BUILTIN (the nshell builtin),
:EXTERNAL (the default), or :FUNCTION (a shell function or alias whose body
the line does not show); it selects the spec row;
ARGUMENTS are the argument words; a command that is not a wrapper is matched
against its spec row.  NESTED and EMBEDDED are (LEVEL RULE TEXT) results of
classifying embedded command text.  WRAPS says the command runs another one,
OPAQUE that the wrapper is opaque (D-P1-5 2.4), and WRAPPER-MISMATCHES lists
the wrapper's own words its spec row does not allow.  UNPARSABLE and UNCLASSIFIABLE are lists of reason texts.
ASSIGNMENTS are the environment names the command is run with and
WRAPPER-OPTIONS the options given to env.  WRITES are the output redirect
targets and REDIRECT-PROBLEMS a text per redirect outside the safe forms,
both taken from the AST; WORDS are the words as written.
Returns the level and the (RULE . TEXT) reasons at that level."
  (declare (ignore command invoked-as resolution arguments nested embedded
                   wraps opaque
                   wrapper-mismatches unparsable unclassifiable form-redirect
                   sexp-unforced assignments wrapper-options writes
                   redirect-problems words))
  (let ((facts (apply #'%subject-facts subject)))
    (%top-level-reasons
     (append (%builtin-solutions facts) (%user-solutions facts)))))

(defun subject-effects (&key command invoked-as arguments writes)
  "Return the effects of one command: (DELETES PATH), (WRITES PATH), :NETWORK.
WRITES are the output redirect targets the caller read from the AST."
  (remove-duplicates
   (copy-tree
    (%query-findall *builtin-classify-rulebase*
                    (%subject-facts :command command
                                    :invoked-as invoked-as
                                    :arguments arguments
                                    :writes writes)
                    '?effect
                    '(effect subject ?effect)))
   :test #'equal :from-end t))

(defun diagnose-typo (&key input status command-start command-end known-commands)
  "Return fixes for a command-not-found failure (diagnose/typo).

INPUT is the submitted text, STATUS its exit status, and the command word
spans [COMMAND-START, COMMAND-END).  KNOWN-COMMANDS are the names the caller
can run; the rule reads no PATH itself.  Each fix is a plist with :INPUT,
:WHY, and :RULE, nearest first."
  (let ((facts
          (append
           (list (list 'status 'failure status)
                 (list 'input 'failure input)
                 (list 'command-span 'failure command-start command-end)
                 (list 'command-name 'failure
                       (subseq input command-start command-end))
                 ;; Keeps candidate-command/1 defined when the list is empty.
                 (list 'candidate-command :none))
           (mapcar (lambda (name) (list 'candidate-command name))
                   (remove-duplicates known-commands :test #'string=)))))
    (let ((fixes
            (remove-duplicates
             (copy-tree
              (%query-findall *builtin-diagnose-rulebase* facts
                              '(?new ?distance ?rule)
                              '(diagnose failure (fix ?new)
                                ?rule (distance ?distance))))
             :test #'equal :from-end t)))
      (mapcar (lambda (fix)
                (destructuring-bind (new distance rule) fix
                  (list :input new
                        :why (format nil "edit distance ~D" distance)
                        :rule rule)))
              (stable-sort (sort fixes #'string< :key #'first)
                           #'< :key #'second)))))

(defun classify-rule-catalog (&optional (rulebase *builtin-classify-rulebase*))
  "Return (RULE LEVEL TEXT) for each classify/4 rule RULEBASE states, in
clause order and once per RULE and LEVEL.  TEXT is NIL when the rule takes its
text from the input it judges.  Clauses that pass on a nested rule name are
not rules of their own and are left out."
  (let ((catalog '()))
    (when rulebase
      (dolist (clause (cl-prolog-kit:rulebase-visible-clauses rulebase))
        (let ((head (cl-prolog-kit:clause-head clause)))
          (when (and (consp head)
                     (eq (first head) 'classify)
                     (= (length head) 5)
                     (keywordp (third head))
                     (stringp (fourth head)))
            (destructuring-bind (level rule text) (cddr head)
              (unless (find-if (lambda (entry)
                                 (and (string= rule (first entry))
                                      (eq level (second entry))))
                               catalog)
                (push (list rule level (and (stringp text) text)) catalog)))))))
    (nreverse catalog)))
