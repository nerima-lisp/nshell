(in-package #:nshell.application)

(defvar *loop-control-signal* nil
  "Pending BREAK or CONTINUE signal, represented as (KIND . COUNT).")

(defvar *loop-control-depth* 0
  "Number of active shell loops in the current dynamic execution context.")

;;; Control flow execution and AST dispatch.
;;; This file defines:
;;;   - %execute-command-substitution-fields: the bridge from argument expansion
;;;     back into the AST executor (required by %command-sub-fields-at in expansion)
;;;   - %with-output-code-accumulator / %collect-execution-result: output helpers
;;;   - Control flow node handlers (if, for, while, case, sequence, begin-end)
;;;   - define-ast-dispatcher: Prolog-style data-driven dispatch macro
;;;   - execute-ast-in-context: the top-level AST dispatch function

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
       (setf ,code ,code-value)))

  (defmacro %handle-loop-control (iteration-block)
    "Handle the pending loop signal within ITERATION-BLOCK."
    `(case (%consume-loop-control-signal)
       (:break (return))
       (:propagate (return))
       (:continue (return-from ,iteration-block nil)))))

(defun %record-last-exit-code (context code)
  "Record CODE for both the execution context and the shell-visible status.

The question-mark and status bindings are kept non-exported so they participate
in expansion without becoming part of the environment inherited by child
processes."
  (let ((code (or code 0)))
    (setf (shell-context-last-exit-code context) code)
    (let ((environment (shell-context-environment context)))
      (when environment
        (setf environment
              (nshell.domain.environment:env-set
               environment "?" (princ-to-string code) nil))
        (setf environment
              (nshell.domain.environment:env-set
               environment "status" (princ-to-string code) nil))
        (setf (shell-context-environment context) environment)))
    code))

(defun %consume-loop-control-signal ()
  "Consume one loop level from the pending BREAK or CONTINUE signal.
Returns :BREAK or :CONTINUE when this loop owns the signal, and :PROPAGATE
when an enclosing loop must handle the remaining count."
  (when *loop-control-signal*
    (let ((kind (car *loop-control-signal*))
          (count (cdr *loop-control-signal*)))
      (if (= count 1)
          (progn
            (setf *loop-control-signal* nil)
            kind)
          (progn
            (setf *loop-control-signal*
                  (cons kind (1- count)))
            :propagate)))))

;; -- Control flow node helpers -----------------------------------------------

(defun %execute-condition-in-context (context condition)
  "Execute CONDITION AST and return (output code); code=1 when condition is NIL."
  (if condition
      (multiple-value-bind (output code)
          (execute-ast-in-context context condition)
        (%record-last-exit-code context code)
        (values output code))
      (progn
        (%record-last-exit-code context 1)
        (values nil 1))))

(defun %execute-ast-list-in-context (context nodes)
  "Execute each node in NODES sequentially, accumulating output and final code."
  (%with-output-code-accumulator (output code)
    (dolist (node nodes)
      (%collect-execution-result
       (output code)
       (execute-ast-in-context context node)
       (or exit-code 0))
      (%record-last-exit-code context code)
      (when (or *loop-control-signal*
                (not (shell-context-running context)))
        (return)))))

;; -- Control flow node handlers ----------------------------------------------

(defun %execute-if-node-in-context (context ast)
  (multiple-value-bind (_out condition-code)
      (%execute-condition-in-context context (nshell.domain.parsing:if-node-condition ast))
    (declare (ignore _out))
    (when *loop-control-signal*
      (return-from %execute-if-node-in-context
        (values nil condition-code)))
    (cond
      ((= 0 condition-code)
       (%execute-ast-list-in-context context (nshell.domain.parsing:if-node-then-branch ast)))
      ((nshell.domain.parsing:if-node-else-branch ast)
       (%execute-ast-list-in-context context (nshell.domain.parsing:if-node-else-branch ast)))
      (t (values nil 0)))))

(defun %execute-for-node-in-context (context ast)
  (let ((*loop-control-depth* (1+ *loop-control-depth*)))
    (%with-output-code-accumulator (output code)
      (loop for value in (loop for value-arg in (nshell.domain.parsing:for-node-in-values ast)
                               append (%expand-source-arg-in-context context value-arg))
            do (block for-iteration
                 (%update-shell-environment context
                                            #'nshell.domain.environment:env-set
                                            (nshell.domain.parsing:for-node-var-name ast)
                                            value
                                            nil)
                 (%collect-execution-result
                  (output code)
                  (%execute-ast-list-in-context context (nshell.domain.parsing:for-node-body ast)))
                 (%record-last-exit-code context code)
                 (%handle-loop-control for-iteration)
                 (unless (shell-context-running context)
                   (return)))))))

(defun %execute-while-node-in-context (context ast)
  (let ((*loop-control-depth* (1+ *loop-control-depth*)))
    (%with-output-code-accumulator (output code)
      (loop
        (block while-iteration
          (multiple-value-bind (_out condition-code)
              (%execute-condition-in-context context
                                              (nshell.domain.parsing:while-node-condition ast))
            (declare (ignore _out))
            (%handle-loop-control while-iteration)
            (unless (= 0 condition-code) (return)))
          (%collect-execution-result
           (output code)
           (%execute-ast-list-in-context context (nshell.domain.parsing:while-node-body ast)))
          (%record-last-exit-code context code)
          (%handle-loop-control while-iteration)
          (unless (shell-context-running context)
            (return)))))))

(defun %execute-case-node-in-context (context ast)
  (let* ((raw-value (nshell.domain.parsing:case-node-value ast))
         (expanded (nshell.domain.expansion:expand-all
                    raw-value
                    (shell-context-environment context)
                    (shell-context-filesystem context)))
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

(defun %sequence-should-stop-after-command-p (separator code)
  (or (and (eq :and separator) (/= code 0))
      (and (eq :or separator) (= code 0))))

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
            (progn
              (%collect-execution-result
               (output code)
               (%spawn-background-node-in-context context command))
              (%record-last-exit-code context code))
            (progn
              (%collect-execution-result
               (output code)
               (execute-ast-in-context context command))
              (%record-last-exit-code context code)
              (when (%sequence-should-stop-after-command-p separator code)
                (return))))
        (when (or *loop-control-signal*
                  (not (shell-context-running context)))
          (return))))))

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
