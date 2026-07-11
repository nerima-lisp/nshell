(in-package #:nshell.application)

;;; Control flow execution and AST dispatch.
;;; This file defines:
;;;   - %execute-command-substitution-fields: the bridge from argument expansion
;;;     back into the AST executor (required by %command-sub-fields-at in expansion)
;;;   - %with-output-code-accumulator / %collect-execution-result: output helpers
;;;   - Control flow node handlers (if, for, while, case, sequence, begin-end)
;;;   - define-ast-dispatcher: Prolog-style data-driven dispatch macro
;;;   - execute-ast-in-context: the top-level AST dispatch function

;; -- Command substitution (back-edge from expansion into execution) ----------

(defun %execute-command-substitution-fields (context command-string)
  "Execute COMMAND-STRING as a command substitution within CONTEXT.
Returns a list of output fields (split on newlines), or NIL on error or timeout."
  (handler-case
      (nshell.domain.parsing:with-parsed-command-line-case (result ast command-string)
        (:complete
         (sb-ext:with-timeout *command-substitution-timeout*
           (multiple-value-bind (output exit-code)
               (execute-ast-in-context context ast)
             (declare (ignore exit-code))
             (%command-substitution-fields output))))
        (:error nil)
        (:incomplete nil))
    (sb-ext:timeout ()
      (format *error-output* "nshell: command substitution timed out: ~a~%"
              command-string)
      nil)))

;; -- Output accumulation helpers ---------------------------------------------

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro %with-output-code-accumulator ((output code) &body body)
    "Accumulate string chunks in OUTPUT and track final exit CODE.
Builds the final output string by joining all pushed chunks in order."
    `(let ((,output nil)
           (,code 0))
       ,@body
       (values (apply #'concatenate 'string (nreverse ,output)) ,code)))

  (defmacro %collect-execution-result ((output code) form &optional (code-value 'exit-code))
    "Execute FORM, push its output chunk onto OUTPUT, and set CODE."
    `(multiple-value-bind (chunk exit-code)
         ,form
       (when chunk
         (push chunk ,output))
       (setf ,code ,code-value))))

;; -- Control flow node helpers -----------------------------------------------

(defun %execute-condition-in-context (context condition)
  "Execute CONDITION AST and return (output code); code=1 when condition is NIL."
  (if condition
      (execute-ast-in-context context condition)
      (values nil 1)))

(defun %execute-ast-list-in-context (context nodes)
  "Execute each node in NODES sequentially, accumulating output and final code."
  (%with-output-code-accumulator (output code)
    (dolist (node nodes)
      (%collect-execution-result
       (output code)
       (execute-ast-in-context context node)
       (or exit-code 0)))))

;; -- Control flow node handlers ----------------------------------------------

(defun %execute-if-node-in-context (context ast)
  (multiple-value-bind (_out condition-code)
      (%execute-condition-in-context context (nshell.domain.parsing:if-node-condition ast))
    (declare (ignore _out))
    (cond
      ((= 0 condition-code)
       (%execute-ast-list-in-context context (nshell.domain.parsing:if-node-then-branch ast)))
      ((nshell.domain.parsing:if-node-else-branch ast)
       (%execute-ast-list-in-context context (nshell.domain.parsing:if-node-else-branch ast)))
      (t (values nil 0)))))

(defun %execute-for-node-in-context (context ast)
  (%with-output-code-accumulator (output code)
    (dolist (value (loop for value-arg in (nshell.domain.parsing:for-node-in-values ast)
                         append (%expand-source-arg-in-context context value-arg)))
      (%update-shell-environment context
                                 #'nshell.domain.environment:env-set
                                 (nshell.domain.parsing:for-node-var-name ast)
                                 value
                                 nil)
      (%collect-execution-result
       (output code)
       (%execute-ast-list-in-context context (nshell.domain.parsing:for-node-body ast))))))

(defun %execute-while-node-in-context (context ast)
  (%with-output-code-accumulator (output code)
    (loop
      (multiple-value-bind (_out condition-code)
          (%execute-condition-in-context context (nshell.domain.parsing:while-node-condition ast))
        (declare (ignore _out))
        (unless (= 0 condition-code) (return)))
      (%collect-execution-result
       (output code)
       (%execute-ast-list-in-context context (nshell.domain.parsing:while-node-body ast))))))

(defun %execute-case-node-in-context (context ast)
  (let* ((raw-value (nshell.domain.parsing:case-node-value ast))
         (expanded (nshell.domain.expansion:expand-all
                    raw-value (shell-context-environment context)))
         (value (or (first expanded) raw-value)))
    (loop for clause in (nshell.domain.parsing:case-node-clauses ast)
          for pattern = (nshell.domain.parsing:case-clause-pattern clause)
          when (nshell.domain.expansion:glob-match-p pattern value)
            do (return (%execute-ast-list-in-context
                        context
                        (nshell.domain.parsing:case-clause-body clause)))
          finally (return (values nil 0)))))

(defun %execute-begin-end-node-in-context (context ast)
  (%execute-ast-list-in-context context (nshell.domain.parsing:begin-end-node-body ast)))

(defun %execute-sequence-node-in-context (context ast)
  (%with-output-code-accumulator (output code)
    (dolist (entry (nshell.domain.parsing:sequence-node-command-separators ast))
      (let ((command
              (nshell.domain.parsing:sequence-node-command-separator-command entry))
            (separator
              (nshell.domain.parsing:sequence-node-command-separator-separator entry)))
        ;; :amp (&) spawns asynchronously and continues without blocking.
        ;; :and (&&) stops on failure; :or (||) stops on success.
        (if (eq :amp separator)
            (%collect-execution-result
             (output code)
             (%spawn-background-node-in-context context command))
            (progn
              (%collect-execution-result
               (output code)
               (execute-ast-in-context context command))
              (when (or (and (eq :and separator) (/= code 0))
                        (and (eq :or separator)  (= code 0)))
                (return))))))))

;; -- Data: AST dispatch table (Prolog-style rules) ----------------------------
;;
;; Each entry is (predicate-fn . handler-fn). define-ast-dispatcher generates
;; the dispatch function by iterating this table in order, matching on the first
;; true predicate — identical to Prolog clause selection.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro define-ast-dispatcher (name (context ast) &body clauses)
    "Generate a dispatch function NAME that selects a handler by AST node type.
CLAUSES is a list of (predicate handler) pairs; the first matching predicate wins.
This encodes the dispatch table as data (separate from the dispatch mechanism),
following the data/logic separation principle."
    `(defun ,name (,context ,ast)
       (cond
         ,@(mapcar (lambda (clause)
                     `((,(first clause) ,ast)
                       (,(second clause) ,context ,ast)))
                   clauses)
         (t (values (format nil "source: unsupported syntax~%") 2))))))

(define-ast-dispatcher execute-ast-in-context (context ast)
  (nshell.domain.parsing:command-node-p    execute-command-node-in-context)
  (nshell.domain.parsing:pipeline-node-p   execute-pipeline-node-in-context)
  (nshell.domain.parsing:if-node-p         %execute-if-node-in-context)
  (nshell.domain.parsing:for-node-p        %execute-for-node-in-context)
  (nshell.domain.parsing:while-node-p      %execute-while-node-in-context)
  (nshell.domain.parsing:case-node-p       %execute-case-node-in-context)
  (nshell.domain.parsing:begin-end-node-p  %execute-begin-end-node-in-context)
  (nshell.domain.parsing:sequence-node-p   %execute-sequence-node-in-context))
