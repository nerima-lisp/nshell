(in-package #:nshell.application)

(defvar *builtin-binding-registry* (make-hash-table :test #'equal))

(define-value-struct builtin-binding
    ((handler nil :type function)
     (argument-mode :argv :type (member :argv :value)))
  :keyword-constructor t)

(defun make-builtin-binding (handler argument-mode)
  (%make-builtin-binding :handler handler :argument-mode argument-mode))

(defun register-builtin (name binding)
  (declare (ignore name binding))
  (%signal-unimplemented-wp-interface "L03" 'register-builtin))

(defun lookup-builtin-binding (name)
  (declare (ignore name))
  (%signal-unimplemented-wp-interface "L03" 'lookup-builtin-binding))

(defun dispatch-builtin (context binding evaluated-command-args &key argv-strings)
  (declare (ignore context binding evaluated-command-args argv-strings))
  (%signal-unimplemented-wp-interface "L03" 'dispatch-builtin))

(defun command-argv-strings (context evaluated-command-args)
  "Expand eligible source arguments in brace, tilde, then glob order.
EXPAND-P is source eligibility; GLOB-P gates globbing. L03 owns C14."
  (declare (ignore context evaluated-command-args))
  (%signal-unimplemented-wp-interface
   "L03"
   (quote command-argv-strings)))
