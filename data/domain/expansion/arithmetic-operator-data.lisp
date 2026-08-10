(in-package #:nshell.domain.expansion)

;;; Arithmetic tokenization and precedence are declarative runtime data.
(setf *arith-tokenizer*
      (make-tokenizer
       :rules (list (make-whitespace-rule :skip-p t)
                    (make-predicate-rule :number #'digit-char-p
                                         :value-function (lambda (s) (parse-integer s)))
                    (make-identifier-rule :type :variable
                                          :start-predicate #'%arith-variable-start-p
                                          :continue-predicate #'%arith-variable-char-p)
                    (make-operator-rule :question '("?"))
                    (make-operator-rule :colon '(":"))
                    (make-operator-rule nil
                                        '("<<" ">>" "<=" ">=" "==" "!=" "&&" "||" "**"
                                          "+" "-" "*" "/" "%" "(" ")"
                                          "<" ">" "!" "&" "|" "^" "~")))))

(setf *arith-pratt-table*
      (let ((table (make-pratt-table)))
        (register-atom table :number (lambda (token) (token-value token)))
        (register-atom table :variable (lambda (token) (list :var (token-value token))))
        (register-grouping table "(" ")")
        (register-infix-right table "**" 130 (lambda (l r) (list :pow l r)))
        (register-prefix table "-" 120 (lambda (x) (list :neg x)))
        (register-prefix table "+" 120 (lambda (x) (list :pos x)))
        (register-prefix table "!" 120 (lambda (x) (list :lnot x)))
        (register-prefix table "~" 120 (lambda (x) (list :bnot x)))
        (register-infix-left table "*" 110 (lambda (l r) (list :mul l r)))
        (register-infix-left table "/" 110 (lambda (l r) (list :div l r)))
        (register-infix-left table "%" 110 (lambda (l r) (list :mod l r)))
        (register-infix-left table "+" 100 (lambda (l r) (list :add l r)))
        (register-infix-left table "-" 100 (lambda (l r) (list :sub l r)))
        (register-infix-left table "<<" 90 (lambda (l r) (list :shl l r)))
        (register-infix-left table ">>" 90 (lambda (l r) (list :shr l r)))
        (register-infix-left table "<" 80 (lambda (l r) (list :lt l r)))
        (register-infix-left table ">" 80 (lambda (l r) (list :gt l r)))
        (register-infix-left table "<=" 80 (lambda (l r) (list :le l r)))
        (register-infix-left table ">=" 80 (lambda (l r) (list :ge l r)))
        (register-infix-left table "==" 70 (lambda (l r) (list :eq l r)))
        (register-infix-left table "!=" 70 (lambda (l r) (list :ne l r)))
        (register-infix-left table "&" 60 (lambda (l r) (list :band l r)))
        (register-infix-left table "^" 50 (lambda (l r) (list :bxor l r)))
        (register-infix-left table "|" 40 (lambda (l r) (list :bor l r)))
        (register-infix-left table "&&" 30 (lambda (l r) (list :and l r)))
        (register-infix-left table "||" 20 (lambda (l r) (list :or l r)))
        (register-ternary table :question :colon 10 (lambda (c th el) (list :if c th el)))
        table))
