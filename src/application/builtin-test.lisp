(in-package #:nshell.application)

(defmacro define-test-predicate-table (name &body specs)
  `(defparameter ,name
     (list ,@(mapcar (lambda (spec)
                       (destructuring-bind (operator lambda-list &body body) spec
                         `(cons ,operator (lambda ,lambda-list ,@body))))
                     specs))))

(define-test-predicate-table +test-unary-predicates+
  ("-f" (context operand) (%path-file-p context operand))
  ("-d" (context operand) (%path-directory-p context operand))
  ("-e" (context operand) (or (%path-file-p context operand)
                               (%path-directory-p context operand)))
  ("-n" (context operand) (declare (ignore context)) (not (string= operand "")))
  ("-z" (context operand) (declare (ignore context)) (string= operand "")))

(define-test-predicate-table +test-binary-predicates+
  ("=" (context left right) (declare (ignore context)) (string= left right))
  ("!=" (context left right) (declare (ignore context)) (not (string= left right))))

(define-test-predicate-table +test-binary-numeric-predicates+
  ("-eq" (context left right) (declare (ignore context)) (= left right))
  ("-ne" (context left right) (declare (ignore context)) (/= left right))
  ("-lt" (context left right) (declare (ignore context)) (< left right))
  ("-le" (context left right) (declare (ignore context)) (<= left right))
  ("-gt" (context left right) (declare (ignore context)) (> left right))
  ("-ge" (context left right) (declare (ignore context)) (>= left right)))

(defun %lookup-test-predicate (operator predicates)
  (cdr (assoc operator predicates :test #'string=)))

(defun %test-unary-predicate-p (context op operand)
  (let ((predicate (%lookup-test-predicate op +test-unary-predicates+)))
    (and predicate (funcall predicate context operand))))

(defun %test-binary-predicate-p (context left op right)
  (let ((predicate (%lookup-test-predicate op +test-binary-predicates+)))
    (and predicate (funcall predicate context left right))))

(defun %test-binary-numeric-result (left op right)
  (let ((predicate (%lookup-test-predicate op +test-binary-numeric-predicates+))
        (left-value (%parse-integer-designator left))
        (right-value (%parse-integer-designator right)))
    (cond
      ((null left-value)
       (values (format nil "test: integer expression expected: ~a~%" left) 2))
      ((null right-value)
       (values (format nil "test: integer expression expected: ~a~%" right) 2))
      ((funcall predicate nil left-value right-value)
       (values nil 0))
      (t
       (values nil 1)))))

(defun %test-two-argument-result (context op operand)
  (if (%lookup-test-predicate op +test-unary-predicates+)
      (values nil (if (%test-unary-predicate-p context op operand) 0 1))
      (values (format nil "test: unknown operator: ~a~%" op) 2)))

(defun %test-three-argument-result (context left op right)
  (cond
    ((%lookup-test-predicate op +test-binary-predicates+)
     (values nil (if (%test-binary-predicate-p context left op right) 0 1)))
    ((%lookup-test-predicate op +test-binary-numeric-predicates+)
     (%test-binary-numeric-result left op right))
    (t
     (values (format nil "test: unknown operator: ~a~%" op) 2))))

(defun %builtin-test (context args)
  (case (length args)
    (0 (values nil 1))
    (1 (values nil (if (string= (first args) "") 1 0)))
    (2 (%test-two-argument-result context (first args) (second args)))
    (3 (%test-three-argument-result context (first args) (second args) (third args)))
    (otherwise (values nil 1))))

(defun %builtin-bracket (context args)
  (if (and args (string= (car (last args)) "]"))
      (%builtin-test context (butlast args))
      (values (format nil "[: missing ]~%") 2)))
