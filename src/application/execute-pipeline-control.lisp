(in-package #:nshell.application)

(defvar *loop-control-signal* nil
  "Pending BREAK or CONTINUE signal, represented as (KIND . COUNT).")

(defvar *loop-control-depth* 0
  "Number of active shell loops in the current dynamic execution context.")

(defvar *execution-origin* :typed)
(defvar *execution-approval* nil
  "Level the user approved for the line being executed: NIL, :SAFE or :CONFIRM.")
(defvar *execution-gate-stopped-p* nil
  "Set to true when the AI execution gate refuses a command; the caller binds it.")
(defvar *execution-gate-parent-kind* nil)
(defvar *execution-gate-refusal* nil
  "NIL, or a cons whose car the AI execution gate sets to the error code of
each refusal: E_NEEDS_APPROVAL or E_BLOCKED_BY_POLICY. The caller binds a fresh
cons; pipeline stage threads share it, so a refusal in a stage reaches it.")

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
    "Collect string chunks in OUTPUT, an output collector, and track final exit
CODE. Returns the chunks joined in order and CODE."
    `(let ((,code 0))
       (with-output-collector (,output)
         ,@body
         (values (get-output-stream-string ,output) ,code))))

  (defmacro %collect-execution-result ((output code) form &optional (code-value 'exit-code))
    "Execute FORM, add its output chunk to OUTPUT, and set CODE."
    `(multiple-value-bind (chunk exit-code)
         ,form
       (when chunk
         (write-string chunk ,output))
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

(defun seed-shell-status-environment (environment)
  "Return ENVIRONMENT with \"?\" and \"status\" seeded to \"0\".

A freshly built environment (session start, before any command has run) has
neither binding, so unlike every later point in the session -- where
%RECORD-LAST-EXIT-CODE keeps both current -- $status expands to the empty
string rather than fish's guaranteed \"0\". Call this once, on the initial
environment, to close that gap; every command afterward keeps it current on
its own."
  (when environment
    (setf environment (nshell.domain.environment:env-set environment "?" "0" nil))
    (setf environment (nshell.domain.environment:env-set environment "status" "0" nil)))
  environment)

(defun %assistant-command-stage-node (node)
  "Return NODE as the gate sees a stage the executor runs as a command.  A
NAME=value command word left by expansion or an alias names a command there,
so it is marked quoted and never read as an assignment or a prefix of one."
  (cond
    ((nshell.domain.parsing:pipeline-node-p node)
     (nshell.domain.parsing:make-pipeline-node
      (mapcar #'%assistant-command-stage-node
              (nshell.domain.parsing:pipeline-node-commands node))))
    ((or (nshell.domain.parsing:command-node-assignment-words node)
         (nshell.domain.parsing:split-command-node-assignments node))
     (nshell.domain.parsing:make-command-node
      (nshell.domain.parsing:command-node-command node)
      (nshell.domain.parsing:command-node-args node)
      (nshell.domain.parsing:ast-node-span node)
      :single
      nil
      (nshell.domain.parsing:command-node-redirects node)
      (nshell.domain.parsing:command-node-force-external-p node)
      (nshell.domain.parsing:command-node-argument-forms node)
      (nshell.domain.parsing:command-node-environment-assignments node)))
    (t node)))

(defun assistant-command-resolver (context &key stage-kinds)
  "Return the function the AI safety classifier calls to learn how the
executor resolves a command node in CONTEXT: it takes the node and the path
the node runs on and returns the executor's dispatch kind and the node it
runs.  Each path asks the executor's own resolution, told not to load a
function file: classifying must not run code before the line is approved.
:BARE-LINE expands an alias with expand-command-alias-node, as
%expand-command-node-in-context does, and resolves the name of the result;
:STAGE resolves the name with %resolve-command-by-name, as
%execute-command-by-name-in-context does; :READER uses
%resolve-command-stage-binding, as evaluate-command-stage-in-context does.
:QUERY resolves a query target by name and returns a third value when its
function file would be loaded by a lookup.  No file is evaluated.
:QUERY-TILDE returns whether the target changes under the context's tilde expansion.
STAGE-KINDS maps nodes whose resolution the executor already made (an
evaluated reader stage, the program exec runs) to their dispatch kind."
  (lambda (node path)
    (let ((known (assoc node stage-kinds :test #'eq)))
      (cond
        (known (values (cdr known) node))
        ((eq path :query-tilde)
         (let ((value (nshell.domain.parsing:command-node-command node)))
           (not (string= value
                         (nshell.domain.expansion:expand-tilde
                          value (shell-context-environment context))))))
        ((eq path :query)
         (multiple-value-bind (kind binding)
             (%resolve-command-by-name
              context (nshell.domain.parsing:command-node-command node)
              :autoload nil)
           (values kind node (and (eq kind :shell-function) (null binding)))))
        ((eq path :reader)
         (handler-case
             (multiple-value-bind (kind binding run-node)
                 (%resolve-command-stage-binding context node :autoload nil)
               (declare (ignore binding))
               (values kind run-node))
           (error () (values :unresolved node))))
        (t
         (let ((expanded (if (eq path :bare-line)
                             (ignore-errors
                              (expand-command-alias-node
                               node (shell-context-alias-table context)))
                             node)))
           (cond
             ;; An alias that does not expand to a command runs nothing the
             ;; classifier can see.
             ((not (nshell.domain.parsing:command-node-p expanded))
              (values :unresolved node))
             ((eq expanded node)
              (values (%resolve-command-by-name
                       context (nshell.domain.parsing:command-node-command node)
                       :autoload nil)
                      node))
             (t
              (let ((run-node (%assistant-command-stage-node expanded)))
                (values (%resolve-command-by-name
                         context (nshell.domain.parsing:command-node-command run-node)
                         :autoload nil)
                        run-node))))))))))

(defun %gate-refusal (code message-control &rest arguments)
  "Return the gate's (MESSAGE STATUS) refusal for error CODE, whose status is
the code's exit status in the error-code table, and record CODE."
  (when *execution-gate-refusal*
    (setf (car *execution-gate-refusal*) code))
  (list (apply #'format nil message-control arguments)
        (nshell.domain.error-codes:error-code-exit-code
         (nshell.domain.error-codes:find-error-code code))))

(defun %assistant-gate-active-p ()
  "True while executing a line that came from an AI proposal or agent step."
  (member *execution-origin* '(:proposal :agent) :test #'eq))

(defun %assistant-execution-gate (context ast &key (path :bare-line) resolve)
  "PATH names the executor that runs AST, as for classify-ast.  RESOLVE is
the classifier's resolver, by default assistant-command-resolver of
CONTEXT."
  (when (%assistant-gate-active-p)
    (labels ((rank (value)
               (case (nshell.feature.assistant:assistant-safety-result-classification value)
                 (:safe 0)
                 (:confirm 1)
                 (:block 2)
                 (otherwise 2)))
             (classify-effective (value)
               (if (or (nshell.domain.parsing:pipeline-node-p value)
                       (nshell.domain.parsing:sequence-node-p value))
                   (reduce (lambda (left right)
                             (if (> (rank right) (rank left)) right left))
                           (mapcar #'classify-effective
                                   (if (nshell.domain.parsing:pipeline-node-p value)
                                       (nshell.domain.parsing:pipeline-node-commands value)
                                       (nshell.domain.parsing:sequence-node-commands value))))
                   (nshell.feature.assistant:classify-ast
                    value
                    :path path
                    :resolve (or resolve (assistant-command-resolver context))))))
      (let* ((classification (classify-effective ast))
             (agent-p (eq *execution-origin* :agent))
             (approval (and (or (null *execution-gate-parent-kind*)
                                (member *execution-gate-parent-kind*
                                        '(:sequence :pipeline)
                                        :test #'eq))
                            *execution-approval*))
             (stop
               (case (nshell.feature.assistant:assistant-safety-result-classification
                      classification)
                 (:safe
                  (when (and agent-p (null approval))
                    (%gate-refusal
                     "E_NEEDS_APPROVAL"
                     "nshell: AI proposal requires approval before execution~%")))
                 (:confirm
                  (unless (eq approval :confirm)
                    (%gate-refusal
                     "E_NEEDS_APPROVAL"
                     "nshell: AI proposal requires confirmation: ~a~%"
                     (nshell.feature.assistant:assistant-safety-result-reason
                      classification))))
                 (otherwise
                  (%gate-refusal
                   "E_BLOCKED_BY_POLICY"
                   "nshell: AI proposal blocked: ~a~%"
                   (nshell.feature.assistant:assistant-safety-result-reason
                    classification))))))
        (when stop
          (setf *execution-gate-stopped-p* t))
        stop))))

(defun %assistant-gated-command-dispatch (context command args thunk)
  ;; and, or, not, command, and builtin run COMMAND by name.
  (let ((gate (%assistant-execution-gate
               context
               (%assistant-command-stage-node
                (nshell.domain.parsing:make-command-node command args))
               :path :stage)))
    (if gate
        (values (first gate) (second gate))
        (funcall thunk))))

(defun %consume-loop-control-signal ()
  "Consume one loop level from the pending BREAK or CONTINUE signal.
Returns :BREAK or :CONTINUE when this loop owns the signal, and :PROPAGATE
when an enclosing loop must handle the remaining count."
  (when *loop-control-signal*
    (destructuring-bind (kind . count) *loop-control-signal*
      (cond
        ((= count 1)
         (setf *loop-control-signal* nil)
         kind)
        (t
         (decf (cdr *loop-control-signal*))
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
    (when (or *loop-control-signal*
              (not (shell-context-running context)))
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
            (unless (shell-context-running context)
              (setf code condition-code)
              (return))
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
       (let ((result
          (or (%assistant-execution-gate ,context ,ast)
                   (multiple-value-list
                    (cond
                      ,@(mapcar (lambda (clause)
                                    `((,(first clause) ,ast)
                                    (let ((*execution-gate-parent-kind*
                                            (cond
                                              ((nshell.domain.parsing:sequence-node-p ,ast) :sequence)
                                              ((nshell.domain.parsing:pipeline-node-p ,ast) :pipeline)
                                              ((nshell.domain.parsing:command-node-p ,ast) :command)
                                              (t :other))))
                                      (,(second clause) ,context ,ast))))
                                clauses)
                      ;; Unknown control nodes are blocked by default.
                      (t (values (format nil "source: unsupported syntax (blocked by default)~%") 2)))))))
         (%record-last-exit-code ,context (second result))
         (values-list result)))))

(define-ast-dispatcher execute-ast-in-context (context ast)
  (nshell.domain.parsing:command-node-p    execute-command-node-in-context)
  (nshell.domain.parsing:pipeline-node-p   execute-pipeline-node-in-context)
  (nshell.domain.parsing:if-node-p         %execute-if-node-in-context)
  (nshell.domain.parsing:for-node-p        %execute-for-node-in-context)
  (nshell.domain.parsing:while-node-p      %execute-while-node-in-context)
  (nshell.domain.parsing:case-node-p       %execute-case-node-in-context)
  (nshell.domain.parsing:begin-end-node-p  %execute-begin-end-node-in-context)
  (nshell.domain.parsing:sequence-node-p   %execute-sequence-node-in-context))

(defun %execute-reader-sequence-node-in-context
    (context ast stage-evaluator &optional command-failure-policy)
  (let ((previous-separator nil)
        (last-status (shell-context-last-exit-code context))
        (last-result nil))
    (with-output-collector (output)
      (dolist (entry (nshell.domain.parsing:sequence-node-command-separators ast))
        (let* ((command
                 (nshell.domain.parsing:sequence-node-command-separator-command entry))
               (separator
                 (nshell.domain.parsing:sequence-node-command-separator-separator entry))
               (skip-p
                 (or (and (eq previous-separator :and) (/= last-status 0))
                     (and (eq previous-separator :or) (= last-status 0)))))
          (unless skip-p
            (let ((*command-test-position-p*
                    (and separator (or (eq separator :and) (eq separator :or)))))
              (multiple-value-bind (value status pipeline-result)
                  (cond
                    ((eq separator :amp)
                     (%reader-spawn-background-node-in-context
                      context command stage-evaluator))
                    (command-failure-policy
                     (let ((item-pipeline-result nil))
                       (multiple-value-bind (value status)
                           (funcall
                            command-failure-policy
                            command
                            (lambda ()
                              (multiple-value-bind (value status pipeline-result)
                                  (execute-reader-ast-in-context
                                   context command stage-evaluator)
                                (setf item-pipeline-result pipeline-result)
                                (values value status pipeline-result))))
                         (values value status item-pipeline-result))))
                    (t
                     (execute-reader-ast-in-context
                      context command stage-evaluator)))
                (when value
                  (write-string value output))
                (setf last-status status
                      last-result pipeline-result)
                (%record-last-exit-code context status))))
          (setf previous-separator separator)
          (when (or *loop-control-signal*
                    (not (shell-context-running context)))
            (return))))
      (values (get-output-stream-string output)
              last-status
              (or last-result
                  (make-pipeline-execution-result last-status nil nil))))))
