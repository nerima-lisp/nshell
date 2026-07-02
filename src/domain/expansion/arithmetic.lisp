;;; Shell arithmetic expansion: $((expression))
;;;
;;; A small recursive-descent evaluator over integers supporting the common
;;; POSIX arithmetic operators. Variables inside the expression are resolved
;;; from the shell environment (an unset or non-numeric name evaluates to 0,
;;; matching POSIX shells). The evaluator is pure domain logic with no I/O.
(in-package #:nshell.domain.expansion)

(defstruct (arith-lexer (:constructor %make-arith-lexer (input)))
  (input "" :type string :read-only t)
  (pos 0 :type fixnum))

(defun %arith-peek (lx &optional (offset 0))
  (let ((p (+ (arith-lexer-pos lx) offset)))
    (when (< p (length (arith-lexer-input lx)))
      (char (arith-lexer-input lx) p))))

(defun %arith-skip-space (lx)
  (loop for ch = (%arith-peek lx)
        while (and ch (member ch '(#\Space #\Tab #\Newline)))
        do (incf (arith-lexer-pos lx))))

(defparameter +arith-operators+
  ;; Longest-match-first so that two-character operators win over one-character.
  '("<<" ">>" "<=" ">=" "==" "!=" "&&" "||"
    "+" "-" "*" "/" "%" "(" ")" "<" ">" "!" "&" "|" "^" "~")
  "Operator lexemes recognized by the arithmetic evaluator.")

(defun %arith-next-token (lx)
  "Return the next token as (:num . integer), (:var . name), (:op . string),
or NIL at end of input."
  (%arith-skip-space lx)
  (let ((ch (%arith-peek lx)))
    (cond
      ((null ch) nil)
      ((digit-char-p ch)
       (let ((start (arith-lexer-pos lx)))
         (loop for c = (%arith-peek lx)
               while (and c (digit-char-p c))
               do (incf (arith-lexer-pos lx)))
         (cons :num (parse-integer (arith-lexer-input lx)
                                   :start start :end (arith-lexer-pos lx)))))
      ((or (alpha-char-p ch) (char= ch #\_))
       (let ((start (arith-lexer-pos lx)))
         (loop for c = (%arith-peek lx)
               while (and c (or (alphanumericp c) (char= c #\_)))
               do (incf (arith-lexer-pos lx)))
         (cons :var (subseq (arith-lexer-input lx) start (arith-lexer-pos lx)))))
      (t
       (let ((op (find-if (lambda (candidate)
                            (let ((end (+ (arith-lexer-pos lx) (length candidate))))
                              (and (<= end (length (arith-lexer-input lx)))
                                   (string= candidate (arith-lexer-input lx)
                                            :start2 (arith-lexer-pos lx) :end2 end))))
                          +arith-operators+)))
         (if op
             (progn (incf (arith-lexer-pos lx) (length op)) (cons :op op))
             (error "nshell: invalid arithmetic character ~s" ch)))))))

(defstruct (arith-parser (:constructor %make-arith-parser (lexer env)))
  lexer env (lookahead nil) (primed nil))

(defun %arith-advance (p)
  (setf (arith-parser-lookahead p) (%arith-next-token (arith-parser-lexer p))
        (arith-parser-primed p) t))

(defun %arith-current (p)
  (unless (arith-parser-primed p) (%arith-advance p))
  (arith-parser-lookahead p))

(defun %arith-op-p (p text)
  (let ((tok (%arith-current p)))
    (and tok (eq (car tok) :op) (string= (cdr tok) text))))

(defun %arith-eat-op (p text)
  (if (%arith-op-p p text)
      (prog1 t (%arith-advance p))
      nil))

(defun %arith-var-value (p name)
  (let ((raw (env-get (arith-parser-env p) name)))
    (or (and raw (ignore-errors (parse-integer raw :junk-allowed t))) 0)))

;; Grammar (lowest to highest precedence):
;;   or    -> and ( '||' and )*
;;   and   -> cmp ( '&&' cmp )*
;;   cmp   -> add ( ('=='|'!='|'<'|'>'|'<='|'>=') add )*
;;   add   -> mul ( ('+'|'-') mul )*
;;   mul   -> unary ( ('*'|'/'|'%') unary )*
;;   unary -> ('-'|'+'|'!') unary | primary
;;   primary -> NUM | VAR | '(' or ')'

(defun %arith-primary (p)
  (let ((tok (%arith-current p)))
    (cond
      ((%arith-eat-op p "(")
       (prog1 (%arith-or p)
         (unless (%arith-eat-op p ")")
           (error "nshell: unbalanced parenthesis in arithmetic expression"))))
      ((and tok (eq (car tok) :num)) (%arith-advance p) (cdr tok))
      ((and tok (eq (car tok) :var)) (%arith-advance p) (%arith-var-value p (cdr tok)))
      (t (error "nshell: unexpected token in arithmetic expression: ~s" tok)))))

(defun %arith-unary (p)
  (cond
    ((%arith-eat-op p "-") (- (%arith-unary p)))
    ((%arith-eat-op p "+") (%arith-unary p))
    ((%arith-eat-op p "!") (if (zerop (%arith-unary p)) 1 0))
    ((%arith-eat-op p "~") (lognot (%arith-unary p)))
    (t (%arith-primary p))))

(defun %arith-nonzero (n)
  (if (zerop n) (error "nshell: division by zero in arithmetic expression") n))

(defun %arith-bool (n) (if n 1 0))

;; Each binary tier is a Prolog-style rule table: (operator . semantic-action).
;; define-arith-binary generates the left-associative loop from the table.
(defmacro define-arith-binary (name higher-prec &rest op-rules)
  "Generate a left-associative binary-operator parsing function from OP-RULES.
Each rule is (op-string expr) where LEFT is the accumulated left-side value."
  (let ((left (gensym "LEFT-")))
    `(defun ,name (p)
       (let ((,left (,higher-prec p)))
         (loop (cond ,@(mapcar (lambda (rule)
                                 (destructuring-bind (op expr) rule
                                   `((%arith-eat-op p ,op)
                                     (setf ,left ,(subst left 'left expr)))))
                               op-rules)
                     (t (return ,left))))))))

(define-arith-binary %arith-mul %arith-unary
  ("*" (* left (%arith-unary p)))
  ("/" (truncate left (%arith-nonzero (%arith-unary p))))
  ("%" (rem left (%arith-nonzero (%arith-unary p)))))

(define-arith-binary %arith-add %arith-mul
  ("+" (+ left (%arith-mul p)))
  ("-" (- left (%arith-mul p))))

(define-arith-binary %arith-cmp %arith-add
  ("<=" (%arith-bool (<= left (%arith-add p))))
  (">=" (%arith-bool (>= left (%arith-add p))))
  ("==" (%arith-bool (= left (%arith-add p))))
  ("!=" (%arith-bool (/= left (%arith-add p))))
  ("<"  (%arith-bool (< left (%arith-add p))))
  (">"  (%arith-bool (> left (%arith-add p)))))

(define-arith-binary %arith-and %arith-cmp
  ("&&" (%arith-bool (and (not (zerop left)) (not (zerop (%arith-cmp p)))))))

(define-arith-binary %arith-or %arith-and
  ("||" (%arith-bool (or (not (zerop left)) (not (zerop (%arith-and p)))))))

(defun evaluate-arithmetic (expression env)
  "Evaluate EXPRESSION (a string) as shell integer arithmetic, returning an
integer. Variables are resolved from ENV."
  (let* ((parser (%make-arith-parser (%make-arith-lexer expression) env))
         (result (%arith-or parser)))
    (when (%arith-current parser)
      (error "nshell: trailing tokens in arithmetic expression: ~s"
             (%arith-current parser)))
    result))

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

(defun expand-arithmetic (input env)
  "Replace every $((expression)) in INPUT with its evaluated integer value."
  (with-output-to-string (out)
    (loop with len = (length input)
          with i = 0
          while (< i len)
          do (if (and (char= (char input i) #\$)
                      (< (+ i 2) len)
                      (char= (char input (1+ i)) #\()
                      (char= (char input (+ i 2)) #\())
                 (let ((end (%arithmetic-substitution-end input (1+ i))))
                   (if end
                       (let ((expr (subseq input (+ i 3) (- end 2))))
                         (write-string
                          (princ-to-string
                           (evaluate-arithmetic (expand-variables expr env) env))
                          out)
                         (setf i end))
                       (progn (write-char (char input i) out) (incf i))))
                 (progn (write-char (char input i) out) (incf i))))))
