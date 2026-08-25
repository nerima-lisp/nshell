;;; Shell arithmetic expansion: $((expression))
;;;
;;; An integer expression evaluator supporting the common POSIX/bash arithmetic
;;; operators.  Parsing is delegated to cl-parser-kit: a rule-based tokenizer
;;; feeds a Pratt (operator-precedence) table that produces an AST, which a
;;; separate walker then evaluates.  Splitting parse from eval lets `&&`/`||`
;;; short-circuit and the ternary evaluate only the taken branch without the
;;; leftover-token quirk of the previous parse-while-evaluating design.
;;;
;;; Variables inside the expression are resolved from the shell environment (an
;;; unset or non-numeric name evaluates to 0, matching POSIX shells).  The
;;; evaluator is pure domain logic with no I/O.
(in-package #:nshell.domain.expansion)

;;; --- Tokenizer ---------------------------------------------------------
;;;
;;; Three deliberate choices keep integer shell semantics intact:
;;;   * numbers use a digit predicate (not cl-parser-kit's number rule, which
;;;     would accept "1.5" as a float);
;;;   * identifier predicates are pinned to the shell rule so "x-y" tokenizes
;;;     as x - y (cl-parser-kit's default identifier chars include #\-);
;;;   * operators carry no token-type (so the Pratt table dispatches on their
;;;     text), except punctuation whose Pratt registrars compare keys with EQL.

(defun %arith-variable-start-p (char)
  (or (alpha-char-p char) (char= char #\_)))

(defun %arith-variable-char-p (char)
  (or (alphanumericp char) (char= char #\_)))

(declaim (special +arith-token-operator-texts+
                  +arith-prefix-operator-specifications+
                  +arith-infix-operator-specifications+))

(defun %ascii-digit-p (char)
  (and (characterp char) (char<= #\0 char #\9)))

(defun %make-arithmetic-tokenizer ()
  (make-tokenizer
   :rules (list (make-whitespace-rule :skip-p t)
                (make-predicate-rule :number #'%ascii-digit-p
                                     :value-function (lambda (s)
                                                       (parse-integer s)))
                (make-identifier-rule :type :variable
                                      :start-predicate #'%arith-variable-start-p
                                      :continue-predicate #'%arith-variable-char-p)
                (make-operator-rule :open-paren '("("))
                (make-operator-rule :close-paren '(")"))
                (make-operator-rule :question '("?"))
                (make-operator-rule :colon '(":"))
                (make-operator-rule nil +arith-token-operator-texts+))))

(defparameter *arith-tokenizer* (%make-arithmetic-tokenizer))

;;; --- Pratt table (binding-power ladder, C/bash order low -> high) ------
;;;
;;; Registrars build an AST node per operator; the evaluator below walks it.
;;; register-infix-left/right handle the +1 right-binding-power for you, so
;;; equal-precedence chains associate correctly and "**" stays right-assoc and
;;; binds tighter than unary minus (so -2**2 = -(2**2) = -4, matching bash).

(defun %make-unary-arithmetic-node-builder (operator)
  (lambda (operand)
    (list operator operand)))

(defun %make-binary-arithmetic-node-builder (operator)
  (lambda (left right)
    (list operator left right)))

(defun %register-arithmetic-prefix-operators (table)
  (dolist (specification +arith-prefix-operator-specifications+ table)
    (destructuring-bind (text precedence operator) specification
      (register-prefix table text precedence
                       (%make-unary-arithmetic-node-builder operator)))))

(defun %register-arithmetic-infix-operators (table)
  (dolist (specification +arith-infix-operator-specifications+ table)
    (destructuring-bind (associativity text precedence operator) specification
      (ecase associativity
        (:left
         (register-infix-left
          table text precedence
          (%make-binary-arithmetic-node-builder operator)))
        (:right
         (register-infix-right
          table text precedence
          (%make-binary-arithmetic-node-builder operator)))))))

(defun %make-arithmetic-pratt-table ()
  (let ((table (make-pratt-table)))
    (register-atom table :number (lambda (token) (token-value token)))
    (register-atom table :variable
                   (lambda (token) (list :var (token-value token))))
    (register-grouping table :open-paren :close-paren)
    (%register-arithmetic-prefix-operators table)
    (%register-arithmetic-infix-operators table)
    (register-ternary table :question :colon 10
                      (lambda (condition then else)
                        (list :if condition then else)))
    table))

(defparameter *arith-pratt-table* (%make-arithmetic-pratt-table))

;;; --- Evaluator ---------------------------------------------------------

(defun %arith-nonzero (n)
  (if (zerop n) (error "nshell: division by zero in arithmetic expression") n))

(defun %arith-bool (n) (if n 1 0))

(defun %arith-var-value (env name)
  "Resolve NAME from ENV as an integer; unset or non-numeric names are 0."
  (let ((raw (env-get env name)))
    (or (and raw (ignore-errors (parse-integer raw :junk-allowed t))) 0)))

(defun %arith-eval (node env)
  "Recursively evaluate an arithmetic AST NODE against ENV, returning an integer."
  (if (integerp node)
      node
      (destructuring-bind (op &rest operands) node
        (flet ((a () (%arith-eval (first operands) env))
               (b () (%arith-eval (second operands) env)))
          (ecase op
            (:var  (%arith-var-value env (first operands)))
            (:neg  (- (a)))
            (:pos  (a))
            (:lnot (if (zerop (a)) 1 0))
            (:bnot (lognot (a)))
            (:pow  (let ((exponent (b)))
                     (when (minusp exponent)
                       (error "nshell: exponent less than 0 in arithmetic expression"))
                     (expt (a) exponent)))
            (:mul  (* (a) (b)))
            (:div  (truncate (a) (%arith-nonzero (b))))
            (:mod  (rem (a) (%arith-nonzero (b))))
            (:add  (+ (a) (b)))
            (:sub  (- (a) (b)))
            (:shl  (ash (a) (b)))
            (:shr  (ash (a) (- (b))))
            (:lt   (%arith-bool (< (a) (b))))
            (:gt   (%arith-bool (> (a) (b))))
            (:le   (%arith-bool (<= (a) (b))))
            (:ge   (%arith-bool (>= (a) (b))))
            (:eq   (%arith-bool (= (a) (b))))
            (:ne   (%arith-bool (/= (a) (b))))
            (:band (logand (a) (b)))
            (:bxor (logxor (a) (b)))
            (:bor  (logior (a) (b)))
            ;; Logical operators short-circuit on the evaluated left operand.
            (:and  (%arith-bool (and (not (zerop (a))) (not (zerop (b))))))
            (:or   (%arith-bool (or (not (zerop (a))) (not (zerop (b))))))
            ;; Ternary evaluates only the taken branch.
            (:if   (if (zerop (a)) (%arith-eval (third operands) env) (b))))))))

(defun evaluate-arithmetic (expression env)
  "Evaluate EXPRESSION (a string) as shell integer arithmetic, returning an
integer. Variables are resolved from ENV."
  (let ((tokens (tokenize expression *arith-tokenizer*)))
    (multiple-value-bind (ok ast next failure)
        (parse-pratt-all tokens *arith-pratt-table*)
      (declare (ignore next))
      (unless ok
        (error "nshell: ~A"
               (if failure
                   (parse-failure->string failure)
                   "invalid arithmetic expression")))
      (%arith-eval ast env))))

(defun %arithmetic-substitution-end (input start)
  "Given INPUT and START pointing at the first #\( of a $(( opener, return the
index just past the matching )). The opening ( ( and the closing ) ) are
balanced by paren depth, so depth returning to zero marks the end. Returns NIL
when unbalanced."
  (let ((depth 0))
    (loop for i from start below (length input)
          for ch = (char input i)
          do (cond ((char= ch #\() (incf depth))
                   ((char= ch #\))
                    (decf depth)
                    (when (zerop depth)
                      (return (1+ i))))))))

(defstruct (arithmetic-substitution
            (:constructor %make-arithmetic-substitution (start end expression)))
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t)
  (expression "" :type string :read-only t))

(defun %arithmetic-substitution-at (input start)
  "Return the arithmetic substitution at START, or NIL when START is not a $(( opener."
  (when (and (< (+ start 2) (length input))
             (char= (char input start) #\$)
             (char= (char input (1+ start)) #\()
             (char= (char input (+ start 2)) #\())
    (let ((end (%arithmetic-substitution-end input (1+ start))))
      (when end
        (%make-arithmetic-substitution start
                                       end
                                       (subseq input (+ start 3) (- end 2)))))))

(defun expand-arithmetic (input env)
  "Replace every $((expression)) in INPUT with its evaluated integer value."
  (with-output-to-string (out)
    (loop with len = (length input)
          with i = 0
          while (< i len)
          for substitution = (%arithmetic-substitution-at input i)
          do (if substitution
                 (progn
                   (write-string
                    (princ-to-string
                     (evaluate-arithmetic
                      (expand-variables
                       (arithmetic-substitution-expression substitution)
                       env)
                      env))
                    out)
                   (setf i (arithmetic-substitution-end substitution)))
                 (progn (write-char (char input i) out) (incf i))))))
