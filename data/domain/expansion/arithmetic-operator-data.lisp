(in-package #:nshell.domain.expansion)

(defparameter +arith-token-operator-texts+
  '("<<" ">>" "<=" ">=" "==" "!=" "&&" "||" "**"
    "+" "-" "*" "/" "%" "<" ">" "!" "&" "|" "^" "~"))

(defparameter +arith-prefix-operator-specifications+
  '(("-" 120 :neg)
    ("+" 120 :pos)
    ("!" 120 :lnot)
    ("~" 120 :bnot)))

(defparameter +arith-infix-operator-specifications+
  '((:right "**" 130 :pow)
    (:left "*" 110 :mul)
    (:left "/" 110 :div)
    (:left "%" 110 :mod)
    (:left "+" 100 :add)
    (:left "-" 100 :sub)
    (:left "<<" 90 :shl)
    (:left ">>" 90 :shr)
    (:left "<" 80 :lt)
    (:left ">" 80 :gt)
    (:left "<=" 80 :le)
    (:left ">=" 80 :ge)
    (:left "==" 70 :eq)
    (:left "!=" 70 :ne)
    (:left "&" 60 :band)
    (:left "^" 50 :bxor)
    (:left "|" 40 :bor)
    (:left "&&" 30 :and)
    (:left "||" 20 :or)))
