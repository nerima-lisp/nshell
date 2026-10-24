(in-package #:nshell.application)

(defvar *builtin-binding-registry* (make-hash-table :test #'equal))

(define-value-struct builtin-binding
    ((handler nil :type function)
     (argument-mode :argv :type (member :argv :value)))
  :keyword-constructor t)

(defun make-builtin-binding (handler argument-mode)
  (%make-builtin-binding :handler handler :argument-mode argument-mode))

(defun register-builtin (name binding)
  (unless (stringp name)
    (error "Builtin name must be a string: ~S" name))
  (unless (builtin-binding-p binding)
    (error "Builtin binding must be a builtin-binding: ~S" binding))
  (setf (gethash name *builtin-binding-registry*) binding))

(defun lookup-builtin-binding (name)
  (if (stringp name)
      (gethash name *builtin-binding-registry*)
      (values nil nil)))

(defun dispatch-builtin (context binding evaluated-command-args
                          &key (argv-strings nil argv-strings-p))
  (case (builtin-binding-argument-mode binding)
    (:argv
     (multiple-value-bind (output status)
         (funcall (builtin-binding-handler binding)
                  context
                  (if argv-strings-p
                      argv-strings
                      (command-argv-strings
                       context evaluated-command-args)))
       (values (or output "") status)))
    (:value
     (funcall (builtin-binding-handler binding)
              context evaluated-command-args))))

(defun command-argv-strings (context evaluated-command-args)
  "Expand eligible source arguments in brace, tilde, then glob order.
EXPAND-P is source eligibility; GLOB-P gates globbing. L03 owns C14."
  (let ((environment (shell-context-environment context))
        (filesystem (shell-context-filesystem context)))
    (loop for argument in evaluated-command-args
          for source-span =
            (nshell.domain.parsing:evaluated-command-arg-source-span
             argument)
          for value =
            (argv-scalar-string
             (nshell.domain.parsing:evaluated-command-arg-value argument)
             :source-span source-span)
          for expand-p =
            (nshell.domain.parsing:evaluated-command-arg-expand-p argument)
          for glob-p =
            (nshell.domain.parsing:evaluated-command-arg-glob-p argument)
          append
          (if expand-p
              (loop for braced in
                    (nshell.domain.expansion:expand-braces value)
                    for tiled =
                      (nshell.domain.expansion:expand-tilde braced environment)
                    append
                    (if glob-p
                        (nshell.domain.expansion:expand-glob tiled filesystem)
                        (list tiled)))
              (list value)))))
