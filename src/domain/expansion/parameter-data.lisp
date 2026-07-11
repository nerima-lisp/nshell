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

(defstruct (list-selection-spec
            (:constructor %make-list-selection-spec (kind start-index end-index)))
  (kind :index :type keyword :read-only t)
  (start-index nil :read-only t)
  (end-index nil :read-only t))

(defstruct (variable-reference-syntax
            (:constructor %make-variable-reference-syntax
                (name name-end bracket-spec bracket-next bracket-status)))
  (name "" :type string :read-only t)
  (name-end 0 :type fixnum :read-only t)
  (bracket-spec nil :read-only t)
  (bracket-next nil :read-only t)
  (bracket-status nil :read-only t))

(defstruct (parameter-binding
            (:constructor %make-parameter-binding (name raw set-p value)))
  (name "" :type string :read-only t)
  (raw nil :read-only t)
  (set-p nil :read-only t)
  (value "" :type string :read-only t))

(defstruct (parameter-operator
            (:constructor %make-parameter-operator (op word-text colon-p)))
  (op nil :read-only t)
  (word-text "" :type string :read-only t)
  (colon-p nil :read-only t))
