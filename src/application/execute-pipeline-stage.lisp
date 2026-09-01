(in-package #:nshell.application)

(declaim (notinline nshell.infrastructure.acl:process-substitution-resource-path
                    nshell.infrastructure.acl:process-substitution-resource-fd))

(declaim (special nshell.infrastructure.acl:*external-command-timeout*))

;;; Pipeline stage execution and command expansion.
;;; execute-ast-in-context (defined in execute-pipeline-control.lisp) is
;;; forward-referenced by %execute-pipeline-stage-in-context and
;;; execute-command-node-in-context for builtin/function dispatch.

(defun %process-substitution-spec-p (value)
  (and (stringp value)
       (>= (length value) 3)
       (or (char= (char value 0) #\<)
           (char= (char value 0) #\>))
       (char= (char value 1) #\()
       (char= (char value (1- (length value))) #\))))

(defun %process-substitution-direction (value)
  (if (char= (char value 0) #\<)
      :input
      :output))

(defun %process-substitution-error (message)
  (format nil "nshell: process substitution: ~a~%" message))

(defun %process-substitution-inner-commands (ast)
  (cond
    ((nshell.domain.parsing:command-node-p ast)
     (list ast))
    ((nshell.domain.parsing:pipeline-node-p ast)
     (nshell.domain.parsing:pipeline-node-commands ast))
    (t
     nil)))

(defun %release-process-substitution-resources (resources)
  (dolist (resource resources)
    (ignore-errors
      (nshell.infrastructure.acl:release-process-substitution-fd resource))))

(defun %finish-process-substitution-resources (resources)
  (dolist (resource resources)
    (ignore-errors
      (nshell.infrastructure.acl:wait-process-substitution resource))
    (ignore-errors
      (nshell.infrastructure.acl:release-process-substitution-fd resource))))

(defun %abort-process-substitution-resources (resources)
  (dolist (resource resources)
    (ignore-errors
      (nshell.infrastructure.acl:close-process-substitution resource))))

(defun %process-substitution-resource-fds (resources)
  (mapcar #'nshell.infrastructure.acl:process-substitution-resource-fd
          resources))

(defun %materialize-process-substitution-in-context (context value)
  (let* ((direction (%process-substitution-direction value))
         (body (subseq value 2 (1- (length value))))
         (parse-result (nshell.domain.parsing:parse-command-line body))
         (ast (nshell.domain.parsing:parse-result-ast parse-result)))
    (unless (nshell.domain.parsing:parse-complete-p parse-result)
      (return-from
       %materialize-process-substitution-in-context
       (values nil nil (%process-substitution-error "the command is incomplete"))))
    (let ((commands (%process-substitution-inner-commands ast)))
      (unless (and
               commands
               (every
                (lambda (command)
                  (nshell.domain.parsing:command-node-p command))
                commands))
        (return-from
         %materialize-process-substitution-in-context
         (values
          nil
          nil
          (%process-substitution-error "the command must be a command or pipeline"))))
      (multiple-value-bind (expanded-commands error nested-resources) (%expand-command-nodes-in-context
                                                                       context
                                                                       commands)
        (when nested-resources
          (%abort-process-substitution-resources nested-resources)
          (return-from
           %materialize-process-substitution-in-context
           (values
            nil
            nil
            (%process-substitution-error
             "nested process substitutions are not supported"))))
        (when error
          (return-from
           %materialize-process-substitution-in-context
           (values nil nil error)))
        (when (some
               (lambda (command)
                 (%shell-internal-command-p context command))
               expanded-commands)
          (return-from
           %materialize-process-substitution-in-context
           (values nil nil (%process-substitution-error "the command must be external"))))
        (let* ((redirect-split (%extract-pipeline-redirects expanded-commands))
               (clean-commands
                (nshell.domain.parsing:command-list-redirect-split-result-clean-commands
                 redirect-split))
               (redirects
                (nshell.domain.parsing:command-list-redirect-split-result-redirects
                 redirect-split)))
          (handler-case (let ((resource
                               (nshell.infrastructure.acl:spawn-process-substitution
                                direction
                                clean-commands
                                :redirects
                                redirects)))
                          (values
                           (nshell.infrastructure.acl:process-substitution-resource-path
                            resource)
                           resource
                           nil))
            (error (condition)
              (values nil nil (%process-substitution-error (princ-to-string condition))))))))))

(defun %expand-command-args-in-context (context command-node)
  (let ((args nil)
        (resources nil)
        (here-doc-target-p nil))
    (handler-case
        (progn
          (dolist (arg (nshell.domain.parsing:command-node-args command-node))
            (let* ((value (nshell.domain.parsing:arg-value arg))
                   (literal-p (nshell.domain.parsing:arg-here-doc-literal-p arg)))
              (cond
                ((and here-doc-target-p (not literal-p))
                 (push
                  (nshell.domain.parsing:make-command-arg
                   (%expand-here-doc-body-in-context context value))
                  args))
                ((and (not literal-p)
                      (null (nshell.domain.parsing:arg-quote-style arg))
                      (%process-substitution-spec-p value))
                 (multiple-value-bind (path resource error)
                     (%materialize-process-substitution-in-context context value)
                   (when error
                     (%abort-process-substitution-resources resources)
                     (return-from %expand-command-args-in-context
                       (values nil nil error)))
                   (push (nshell.domain.parsing:make-command-arg path) args)
                   (push resource resources)))
                (t
                 (dolist (expanded-value
                           (%expand-source-arg-in-context context arg))
                   (push (nshell.domain.parsing:make-command-arg expanded-value)
                         args))))
              (setf here-doc-target-p
                    (not (null (member value '("<<" "<<-") :test #'string=))))))
          (values (nreverse args) (nreverse resources) nil))
      (nshell.domain.expansion:parameter-expansion-error (condition)
        (%abort-process-substitution-resources resources)
        (values nil nil
                (format nil "nshell: ~a~%" condition))))))

;; -- Command name expansion (fixes unexpanded $VAR in command position) --------

(defun %expand-command-node-in-context (context command-node)
  "Expand the command name and all args in COMMAND-NODE under CONTEXT.
Returns (expanded-node nil) on success or (nil error-string) when the
command name expands to zero or multiple fields (ambiguous)."
  (handler-case
      (let* ((alias-expanded (expand-command-alias-node
                              command-node
                              (shell-context-alias-table context)))
             (environment (shell-context-environment context))
             (filesystem (shell-context-filesystem context)))
        (multiple-value-bind (command error)
            (%expand-command-name-from-fragments
             alias-expanded environment filesystem)
          (if error
              (values nil error)
              (multiple-value-bind (args resources arg-error)
                  (%expand-command-args-in-context context alias-expanded)
                (if arg-error
                    (values nil arg-error nil)
                    (values (nshell.domain.parsing:make-command-node
                             command
                             args)
                            nil
                            resources))))))
    (nshell.domain.expansion:parameter-expansion-error (condition)
      (values nil (format nil "nshell: ~a~%" condition) nil))))

(defun %expand-command-nodes-in-context (context commands)
  "Expand all COMMANDS; return (expanded-list nil) or (nil error-string) on first error."
  (let ((expanded-commands nil)
        (resources nil))
    (dolist (command commands)
      (multiple-value-bind (expanded error command-resources)
          (%expand-command-node-in-context context command)
        (if error
            (progn
              (%abort-process-substitution-resources resources)
              (return-from %expand-command-nodes-in-context
                (values nil error nil)))
            (progn
              (push expanded expanded-commands)
              (setf resources (nconc resources command-resources))))))
    (values (nreverse expanded-commands) nil resources)))
