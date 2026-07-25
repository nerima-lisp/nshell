(in-package #:nshell.domain.expansion)

(defvar *positional-args* nil
  "List of function arguments used to expand the fish-style $argv and $argv[N].
Bound dynamically by the function-call machinery for the duration of a function
body; NIL at top level.")

(define-condition parameter-expansion-error (error)
  ((name :initarg :name :reader parameter-expansion-error-name)
   (message :initarg :message :reader parameter-expansion-error-message))
  (:report
   (lambda (condition stream)
     (format stream "~a: ~a"
             (parameter-expansion-error-name condition)
             (parameter-expansion-error-message condition)))))

(define-value-struct list-selection-spec
    ((kind :index :type keyword)
     (start-index nil)
     (end-index nil)))

(define-value-struct variable-reference-syntax
    ((name "" :type string)
     (name-end 0 :type fixnum)
     (bracket-spec nil)
     (bracket-next nil)
     (bracket-status nil)))

(define-value-struct parameter-binding
    ((name "" :type string)
     (raw nil)
     (set-p nil)
     (value "" :type string)))

(define-value-struct parameter-operator
    ((op nil)
     (word-text "" :type string)
     (colon-p nil)))
