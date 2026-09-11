(in-package #:nshell.application)

;;; `math` (fish's calculator): + - * / % ^, parentheses, unary minus, decimals.
;;;
;;; Deliberately not built on nshell.domain.expansion:evaluate-arithmetic (the
;;; $((...)) evaluator): that evaluator truncates `/` to an integer quotient,
;;; maps `^` to bitwise XOR rather than exponentiation (see
;;; +arith-infix-operator-specifications+ in arithmetic-operator-data.lisp,
;;; where "**" is :pow and "^" is :bxor), and tokenizes numbers with a
;;; digit-only predicate that never reads a decimal point. All three conflict
;;; with fish math semantics, so this file parses and evaluates independently,
;;; over exact rationals so integral results stay exact and the "trim to 6
;;; fraction digits" formatting has nothing to round twice.

(define-condition %math-parse-error (error)
  ((message :initarg :message :reader %math-parse-error-message)))

(define-condition %math-division-by-zero (error) ())

(defun %math-scan-number (input start)
  "Scan a decimal literal in INPUT starting at START. Returns (values RATIONAL
NEXT-INDEX)."
  (let* ((len (length input))
         (i start)
         (int-start i))
    (loop while (and (< i len) (digit-char-p (char input i))) do (incf i))
    (let ((int-string (subseq input int-start i))
          (fraction-value 0)
          (fraction-length 0))
      (when (and (< i len) (char= (char input i) #\.))
        (incf i)
        (let ((fraction-start i))
          (loop while (and (< i len) (digit-char-p (char input i))) do (incf i))
          (setf fraction-length (- i fraction-start))
          (when (plusp fraction-length)
            (setf fraction-value (parse-integer input :start fraction-start :end i)))))
      (when (and (zerop (length int-string)) (zerop fraction-length))
        (error '%math-parse-error :message "invalid number"))
      (values (+ (if (plusp (length int-string)) (parse-integer int-string) 0)
                 (if (plusp fraction-length)
                     (/ fraction-value (expt 10 fraction-length))
                     0))
              i))))

(defun %math-tokenize (expression)
  "Tokenize EXPRESSION into a list of (:number . RATIONAL) or (:op . CHAR)."
  (let ((tokens nil)
        (len (length expression))
        (i 0))
    (loop while (< i len)
          for ch = (char expression i)
          do (cond
               ((member ch '(#\Space #\Tab)) (incf i))
               ((or (digit-char-p ch) (char= ch #\.))
                (multiple-value-bind (number next) (%math-scan-number expression i)
                  (push (cons :number number) tokens)
                  (setf i next)))
               ((find ch "+-*/%^()")
                (push (cons :op ch) tokens)
                (incf i))
               (t (error '%math-parse-error
                         :message (format nil "unexpected character '~a'" ch)))))
    (nreverse tokens)))

(defun %math-token-op-p (tokens char)
  (and tokens (eq (caar tokens) :op) (char= (cdar tokens) char)))

(defun %math-token-any-op-p (tokens chars)
  (and tokens (eq (caar tokens) :op) (find (cdar tokens) chars)))

(defun %math-apply-term-op (op left right)
  (case op
    (#\* (* left right))
    (#\/ (if (zerop right) (error '%math-division-by-zero) (/ left right)))
    (#\% (if (zerop right) (error '%math-division-by-zero) (rem left right)))))

(defun %math-expt (base exponent)
  (unless (integerp exponent)
    (error '%math-parse-error :message "exponent must be an integer"))
  (when (and (zerop base) (minusp exponent))
    (error '%math-division-by-zero))
  (expt base exponent))

(defun %math-parse-atom (tokens)
  (cond
    ((null tokens)
     (error '%math-parse-error :message "unexpected end of expression"))
    ((eq (caar tokens) :number) (values (cdar tokens) (cdr tokens)))
    ((%math-token-op-p tokens #\()
     (multiple-value-bind (value rest) (%math-parse-expr (cdr tokens))
       (if (%math-token-op-p rest #\))
           (values value (cdr rest))
           (error '%math-parse-error :message "expected ')'"))))
    (t (error '%math-parse-error
              :message (format nil "unexpected token '~a'" (cdar tokens))))))

(defun %math-parse-power (tokens)
  (multiple-value-bind (base rest) (%math-parse-atom tokens)
    (if (%math-token-op-p rest #\^)
        (multiple-value-bind (exponent rest2) (%math-parse-unary (cdr rest))
          (values (%math-expt base exponent) rest2))
        (values base rest))))

(defun %math-parse-unary (tokens)
  (if (%math-token-any-op-p tokens "+-")
      (let ((op (cdar tokens)))
        (multiple-value-bind (value rest) (%math-parse-unary (cdr tokens))
          (values (if (char= op #\-) (- value) value) rest)))
      (%math-parse-power tokens)))

(defun %math-parse-term (tokens)
  (multiple-value-bind (left rest) (%math-parse-unary tokens)
    (loop
      (if (%math-token-any-op-p rest "*/%")
          (let ((op (cdar rest)))
            (multiple-value-bind (right rest2) (%math-parse-unary (cdr rest))
              (setf left (%math-apply-term-op op left right)
                    rest rest2)))
          (return (values left rest))))))

(defun %math-parse-expr (tokens)
  (multiple-value-bind (left rest) (%math-parse-term tokens)
    (loop
      (if (%math-token-any-op-p rest "+-")
          (let ((op (cdar rest)))
            (multiple-value-bind (right rest2) (%math-parse-term (cdr rest))
              (setf left (if (char= op #\+) (+ left right) (- left right))
                    rest rest2)))
          (return (values left rest))))))

(defun %math-evaluate (expression)
  (let ((tokens (%math-tokenize expression)))
    (when (null tokens)
      (error '%math-parse-error :message "empty expression"))
    (multiple-value-bind (value rest) (%math-parse-expr tokens)
      (when rest
        (error '%math-parse-error
               :message (format nil "unexpected token '~a'" (cdar rest))))
      value)))

(defun %math-format-fraction (fraction-part)
  (string-right-trim "0" (format nil "~6,'0d" fraction-part)))

(defun %math-format-number (value)
  "Render VALUE (an exact rational) as an integer when it is integral,
otherwise as a decimal with up to 6 fraction digits, trailing zeros trimmed."
  (if (integerp value)
      (princ-to-string value)
      (let* ((negative-p (minusp value))
             (scaled (round (* (abs value) 1000000)))
             (whole-part (truncate scaled 1000000))
             (fraction-part (- scaled (* whole-part 1000000))))
        (cond
          ((and (zerop whole-part) (zerop fraction-part)) "0")
          ((zerop fraction-part) (format nil "~:[~;-~]~d" negative-p whole-part))
          (t (format nil "~:[~;-~]~d.~a" negative-p whole-part
                     (%math-format-fraction fraction-part)))))))

(define-builtin %builtin-math (context args) (context)
  (if (null args)
      (%builtin-usage "math" "math EXPRESSION" 2)
      (handler-case
          (values (format nil "~a~%" (%math-format-number
                                       (%math-evaluate (%string-join args " "))))
                  0)
        (%math-division-by-zero ()
          (values (format nil "math: division by zero~%") 1))
        (%math-parse-error (condition)
          (values (format nil "math: error: ~a~%" (%math-parse-error-message condition))
                  2)))))
