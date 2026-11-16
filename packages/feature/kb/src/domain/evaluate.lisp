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
    (unclassifiable :none ""))
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

(defun %subject-facts (&key command invoked-as arguments nested embedded wraps
                         unparsable unclassifiable form-redirect sexp-unforced)
  (let ((facts (copy-list +subject-fact-schema+)))
    (flet ((add (&rest fact) (push fact facts)))
      (when command
        (add 'command 'subject command)
        (add 'invoked-as 'subject (or invoked-as command))
        (add 'arguments 'subject (copy-list arguments))
        (when arguments
          (add 'subcommand 'subject (first arguments)))
        (loop with operands-only = nil
              for (word next) on arguments
              do (add 'argument 'subject word)
                 (cond
                   (operands-only (add 'operand 'subject word))
                   ((string= word "--") (setf operands-only t))
                   ((option-word-p word) (add 'option 'subject word))
                   (t (add 'operand 'subject word)))
                 ;; A bare-line redirect stays in the argument list: `> out',
                 ;; `>> out', or `>out'.  `>(' starts a process substitution.
                 (let ((target (and (string-prefix-p ">" word)
                                    (not (string-prefix-p ">(" word))
                                    (string-left-trim ">" word))))
                   (cond
                     ((null target))
                     ((plusp (length target)) (add 'redirect 'subject target))
                     (next (add 'redirect 'subject next))))))
      (when wraps (add 'wraps 'subject))
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

(defun classify-subject (&rest subject &key command invoked-as arguments nested
                                         embedded wraps unparsable unclassifiable
                                         form-redirect sexp-unforced)
  "Classify one subject with the built-in and user rules.

COMMAND is the basename and INVOKED-AS the command word as written;
ARGUMENTS are the argument words.  NESTED and EMBEDDED are (LEVEL RULE TEXT)
results of classifying embedded command text; WRAPS says a wrapper target
was read.  UNPARSABLE and UNCLASSIFIABLE are lists of reason texts.
Returns the level and the (RULE . TEXT) reasons at that level."
  (declare (ignore command invoked-as arguments nested embedded wraps
                   unparsable unclassifiable form-redirect sexp-unforced))
  (let ((facts (apply #'%subject-facts subject)))
    (%top-level-reasons
     (append (%builtin-solutions facts) (%user-solutions facts)))))

(defun subject-effects (&key command invoked-as arguments)
  "Return the effects of one command: (DELETES PATH), (WRITES PATH), :NETWORK."
  (remove-duplicates
   (copy-tree
    (%query-findall *builtin-classify-rulebase*
                    (%subject-facts :command command
                                    :invoked-as invoked-as
                                    :arguments arguments)
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
