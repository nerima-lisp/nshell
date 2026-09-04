(in-package #:nshell.application)

;;; Argument expansion and command substitution
;;; All functions deal with expanding shell arguments and running command substitutions.
;;; %execute-command-substitution-fields is forward-referenced here; it lives in
;;; execute-pipeline-control.lisp (after execute-ast-in-context is defined).

(defvar *command-substitution-timeout* nil
  "Maximum seconds for a command substitution to complete before signalling an
error. NIL disables the timeout; bind a finite value where bounded execution is
wanted (tests, completion helpers).")

(defparameter +here-doc-escaped-dollar+ (code-char #xe000))
(defparameter +here-doc-escaped-backtick+ (code-char #xe001))
(defparameter +here-doc-escaped-backslash+ (code-char #xe002))
(defparameter +here-doc-escaped-command-open+ (code-char #xe003))

(defun %make-pipeline-shell-context (&key filesystem)
  (make-shell-context
   :filesystem filesystem
   :environment (nshell.domain.environment:inject-os-environment
                 (nshell.domain.environment:make-default-environment)
                 (nshell.infrastructure.acl:current-environment-entries)
                 #'nshell.infrastructure.acl:current-working-directory)))

(defun execute-command-line (line history)
  (nshell.domain.parsing:with-complete-command-line (result ast line)
    (history-kit:history-add history line)
    (values ast result)))

(defun %source-arg-fragments (arg)
  (or (nshell.domain.parsing:command-arg-fragments arg)
      (list
       (nshell.domain.parsing:make-command-fragment
        (nshell.domain.parsing:arg-value arg)
        (nshell.domain.parsing:arg-quote-style arg)))))

(defun %expand-source-arg (arg &optional environment filesystem)
  (let ((value (nshell.domain.parsing:arg-value arg)))
    (if (nshell.domain.parsing:arg-here-doc-literal-p arg)
        (list value)
        (let ((fields (list "")))
          (dolist (fragment (%source-arg-fragments arg)
                    (mapcar #'%restore-command-fragment-escapes fields))
            (setf fields
                  (%append-expanded-fragment-fields
                   fields
                   (%expand-source-fragment-fields
                    fragment environment filesystem))))))))

(defun %command-node-command-fragments (command-node)
  (or (nshell.domain.parsing:command-node-command-fragments command-node)
      (list
       (nshell.domain.parsing:make-command-fragment
        (nshell.domain.parsing:command-node-command command-node)
        (nshell.domain.parsing:command-node-command-quote-style
         command-node)))))

(defun %expand-command-name-fields-from-fragments
    (command-node environment &optional filesystem)
  (let ((fields (list "")))
    (dolist (fragment (%command-node-command-fragments command-node) fields)
      (let* ((value (nshell.domain.parsing:command-fragment-value fragment))
             (protected
               (%protect-command-fragment-escapes
                value
                (nshell.domain.parsing:command-fragment-escaped-positions
                 fragment)))
             (fragment-fields
               (nshell.domain.expansion:expand-command-name-fields-by-quote-style
                protected
                (nshell.domain.parsing:command-fragment-quote-style
                 fragment)
                environment
                filesystem)))
        (setf fields
              (%append-expanded-fragment-fields fields fragment-fields))))))

(defun %expand-command-name-from-fragments
    (command-node environment &optional filesystem)
  (nshell.domain.expansion::%single-command-name-or-error
   (nshell.domain.parsing:command-node-command command-node)
   (%expand-command-name-fields-from-fragments
    command-node environment filesystem)))

(defun %expand-unquoted-source-arg-in-context (context value environment)
  (multiple-value-bind (fields argv-reference-p)
      (nshell.domain.expansion:argv-reference-fields value)
    (if argv-reference-p
        fields
        (loop for expanded in (%expand-command-substitutions context value)
              append (nshell.domain.expansion:expand-all
                      expanded
                      environment
                      (shell-context-filesystem context))))))

(defun %expand-double-quoted-source-arg-in-context (context value environment)
  (list (apply #'concatenate 'string
               (loop for expanded in
                         (%expand-command-substitutions context value nil nil)
                     collect (nshell.domain.expansion:expand-double-quoted
                              expanded environment)))))

(defun %expand-source-fragment-fields-in-context (context fragment)
  (let* ((value (nshell.domain.parsing:command-fragment-value fragment))
         (protected
           (%protect-command-fragment-escapes
            value
         (nshell.domain.parsing:command-fragment-escaped-positions
             fragment)))
         (environment (shell-context-environment context)))
    (nshell.domain.expansion:expand-by-quote-style
     (nshell.domain.parsing:command-fragment-quote-style fragment)
     (%expand-unquoted-source-arg-in-context context protected environment)
     (list protected)
     (%expand-double-quoted-source-arg-in-context context protected environment))))

(defun %expand-source-arg-in-context (context arg)
  (let ((value (nshell.domain.parsing:arg-value arg)))
    (if (nshell.domain.parsing:arg-here-doc-literal-p arg)
        (list value)
        (let ((fields (list "")))
          (dolist (fragment (%source-arg-fragments arg)
                    (mapcar #'%restore-command-fragment-escapes fields))
            (setf fields
                  (%append-expanded-fragment-fields
                   fields
                   (%expand-source-fragment-fields-in-context
                    context fragment))))))))

(defun %line-command-args (command-node &optional environment)
  (loop for arg in (nshell.domain.parsing:command-node-args command-node)
        append (%expand-source-arg arg environment)))

(defun %line-command-args-in-context (context command-node)
  (loop for arg in (nshell.domain.parsing:command-node-args command-node)
        append (%expand-source-arg-in-context context arg)))
