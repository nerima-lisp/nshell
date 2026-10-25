(in-package #:nshell/test)

(progn
  (defvar *sexp-evaluator-test-calls* nil)
  (defvar *sexp-evaluator-test-failure-policy-calls* 0)
  (defvar *sexp-evaluator-test-path-names* nil)
  (defvar *sexp-evaluator-test-peek-calls* 0)
  (defvar *sexp-evaluator-test-lookup-calls* 0)
  (defvar *sexp-evaluator-test-use-real-command-form->ast-p* nil)
  (defvar *sexp-evaluator-test-real-command-form->ast*
    (symbol-function 'nshell.domain.parsing:command-form->ast))

  (defun %make-sexp-evaluator-test-reader-result (source &optional supplied-form)
    (let* ((*package* (find-package "NSHELL.USER"))
           (form (or supplied-form (read-from-string source)))
           (span-map (make-hash-table :test #'eq))
           (span (list 0 (length source))))
      (when (consp form)
        (setf (gethash form span-map) span))
      (nshell.domain.parsing:make-reader-result
       :form form :source source :source-span span
       :form-span-map span-map :source-path nil :source-map nil
       :symbol-origins (make-hash-table :test #'eq))))

  (defun %sexp-evaluator-test-argument (form)
    (typecase form
      (string form)
      (symbol (symbol-name form))
      (number (princ-to-string form))
      (t (princ-to-string form))))

  (defun %sexp-evaluator-test-command-form->ast
    (source form form-span-map head-classifier &key symbol-origins)
  (declare (ignorable symbol-origins))
  (if *sexp-evaluator-test-use-real-command-form->ast-p*
      (funcall *sexp-evaluator-test-real-command-form->ast*
               source form form-span-map head-classifier
               :symbol-origins symbol-origins)
      (let* ((name (symbol-name (first form)))
             (classification (funcall head-classifier name))
             (arguments
               (mapcar (lambda (argument)
                         (nshell.domain.parsing:make-command-arg
                          (%sexp-evaluator-test-argument argument)))
                       (rest form))))
        (unless (eq classification :command-island)
          (error "Test command adapter received host form ~S" name))
        (nshell.domain.parsing:make-command-node
         name arguments (gethash form form-span-map)))))

  (progn (defun %sexp-evaluator-test-key (name escaped-p) (if escaped-p (list :escaped name) (string-upcase name))) (defun %evaluate-sexp-evaluator-test-source (context source) (nshell.application:evaluate-reader-result-in-context context (%make-sexp-evaluator-test-reader-result source)))))
(progn
  (defvar *sexp-evaluator-test-calls* nil)
  (defvar *sexp-evaluator-test-failure-policy-calls* 0)
  (defvar *sexp-evaluator-test-path-names* nil)
  (defvar *sexp-evaluator-test-peek-calls* 0)
  (defvar *sexp-evaluator-test-lookup-calls* 0)
  (defun %call-with-sexp-evaluator-test-boundaries (context thunk)
    (let* ((registry (make-hash-table :test #'equal))
           (builtins (make-hash-table :test #'equal))
           (*sexp-evaluator-test-calls* nil)
           (*sexp-evaluator-test-failure-policy-calls* 0)
           (*sexp-evaluator-test-path-names* nil)
           (*sexp-evaluator-test-peek-calls* 0)
           (*sexp-evaluator-test-lookup-calls* 0))
      (dolist (entry '(("echo" :argv) ("test" :argv) ("fail" :argv)
                       ("set" :argv) ("value" :value)))
        (setf (gethash (first entry) builtins)
              (nshell.application:make-builtin-binding
               (lambda (&rest arguments)
                 (declare (ignore arguments))
                 0)
               (second entry))))
      (with-temporary-functions
          (('nshell.application:context-shell-function-registry
            (lambda (ignored-context)
              (declare (ignore ignored-context))
              registry))
           ('nshell.application:active-shell-function-scope
            (lambda () nil))
           ('nshell.application:peek-shell-function
            (lambda (ignored-registry name &key scope escaped-p)
              (declare (ignore ignored-registry scope))
              (incf *sexp-evaluator-test-peek-calls*)
              (gethash (%sexp-evaluator-test-key name escaped-p) registry)))
           ('nshell.application:lookup-shell-function
            (lambda (ignored-registry name &key scope escaped-p)
              (declare (ignore ignored-registry scope))
              (incf *sexp-evaluator-test-lookup-calls*)
              (gethash (%sexp-evaluator-test-key name escaped-p) registry)))
           ('nshell.application:register-shell-function
            (lambda (ignored-registry name binding &key escaped-p)
              (declare (ignore ignored-registry))
              (setf (gethash (%sexp-evaluator-test-key name escaped-p) registry)
                    binding)))
           ('nshell.application:lookup-builtin-binding
            (lambda (name)
              (gethash (string-downcase name) builtins)))
           ('nshell.application::%resolve-command-path-candidates
            (lambda (ignored-context name)
              (declare (ignore ignored-context))
              (when (member name *sexp-evaluator-test-path-names*
                            :test #'string-equal)
                (list :candidate))))
           ('nshell.domain.parsing:command-form->ast
            #'%sexp-evaluator-test-command-form->ast)
           ('nshell.application:execute-reader-ast-in-context
            (lambda (execution-context ast stage-evaluator)
              (let* ((stage (funcall stage-evaluator execution-context ast))
                     (node
                       (nshell.application:evaluated-command-stage-command-node
                        stage))
                     (name
                       (nshell.domain.parsing:command-node-command node))
                     (position nshell.application::*command-stage-call-position*)
                     (test-position nshell.application:*command-test-position-p*)
                     (arguments
                       (nshell.application:evaluated-command-stage-arguments
                        stage))
                     (status (cond ((string-equal name "test") 1)
                                   ((string-equal name "fail") 7)
                                   (t 0)))
                     (result
                       (if (eq
                            (nshell.application:evaluated-command-stage-dispatch-kind
                             stage)
                            :shell-function)
                           (funcall
                            (nshell.application:shell-function-binding-callable
                             (nshell.application:evaluated-command-stage-binding
                              stage))
                            execution-context arguments position)
                           (format nil "~(~a~) output~%" name)))
                     (pipeline
                       (nshell.application:make-pipeline-execution-result
                        status (list status) (list nil))))
                (setf *sexp-evaluator-test-calls*
                      (append *sexp-evaluator-test-calls*
                              (list (list stage position test-position))))
                (values result status pipeline))))
           ('nshell.application:call-with-command-failure-policy
            (lambda (ast evaluator-thunk)
              (incf *sexp-evaluator-test-failure-policy-calls*)
              (multiple-value-bind (value status pipeline)
                  (funcall evaluator-thunk)
                (if (and (not (zerop status))
                         (not nshell.application:*command-test-position-p*)
                         (not nshell.application:*interactive-top-level-p*))
                    (error 'nshell.application:command-failed
                           :command
                           (if (nshell.domain.parsing:command-node-p ast)
                               (nshell.domain.parsing:command-node-command ast)
                               "test-command")
                           :status status
                           :stage-statuses (list status)
                           :signal nil)
                    (values value status pipeline))))))
        (funcall thunk)))))
(describe "sexp-evaluator-classification"
  (it "classifies-heads-without-autoloading-and-keeps-command-precedence"
    (let ((context (make-test-shell-context)))
      (%call-with-sexp-evaluator-test-boundaries
       context
       (lambda ()
         (setf *sexp-evaluator-test-path-names* '("find"))
         (expect :host-form :to-equal
                 (nshell.application:classify-sexp-head context "if"))
         (expect :host-form :to-equal
                 (nshell.application:classify-sexp-head context "CL:IF"))
         (expect :command-island :to-equal
                 (nshell.application:classify-sexp-head context "echo"))
         (expect :command-island :to-equal
                 (nshell.application:classify-sexp-head context "^echo"))
         (expect :command-island :to-equal
                 (nshell.application:classify-sexp-head context "find"))
         (expect 0 :to-equal *sexp-evaluator-test-lookup-calls*)
         (expect 2 :to-equal *sexp-evaluator-test-peek-calls*))))))
(describe "sexp-evaluator-special-forms"
  (it "applies-value-and-body-position-rules"
    (let ((context (make-test-shell-context)))
      (%call-with-sexp-evaluator-test-boundaries
       context
       (lambda ()
         (dolist
             (case
              '(("(let ((value 3)) (let ((value 10) (parallel value)) (+ value parallel)))"
                 13)
                ("(let ((value 3)) (let* ((value 10) (sequential value)) (+ value sequential)))"
                 20)
                ("(let ((value 1)) (setq value (+ value 4)) value)" 5)
                ("(let ((value 3)) (list (let ((value 10)) (setq value 12) value) value))" (12 3))
                ("(if (> 3 2) 6 7)" 6)
                ("(when t 8)" 8)
                ("(unless nil 9)" 9)
                ("(and t 10)" 10)
                ("(or nil 11)" 11)
                ("(not nil)" t)
                ("(cond ((= 1 2) 12) (t 13))" 13)
                ("(case 2 ((1) 14) ((2) 15) (otherwise 16))" 15)
                ("(handler-case (error \"expected\") (simple-error () 17))"
                 17)
                ("(handler-case (values 2 3) (:no-error (left right) (+ left right)))"
                 5)
                ("(handler-case (fail) (nshell.application:command-failed () 18))" 18 7)))
           (multiple-value-bind (value status)
               (%evaluate-sexp-evaluator-test-source context (first case))
             (expect (second case) :to-equal value)
             (expect (or (third case) 0) :to-equal status)))))))
  (it "resolves-unqualified-command-failed-in-user-package"
    (let ((context (make-test-shell-context)))
      (%call-with-sexp-evaluator-test-boundaries
       context
       (lambda ()
         (multiple-value-bind (value status)
             (%evaluate-sexp-evaluator-test-source
              context "(handler-case (fail) (command-failed () 18))")
           (expect 18 :to-equal value)
           (expect 7 :to-equal status)))))))
(describe "sexp-evaluator-positions"
  (it "propagates-test-and-value-positions"
    (let ((context (make-test-shell-context)))
      (%call-with-sexp-evaluator-test-boundaries
       context
       (lambda ()
         (multiple-value-bind (value status)
             (%evaluate-sexp-evaluator-test-source
              context "(if (test operand) (echo failed) (echo passed))")
           (expect (format nil "echo output~%") :to-equal value)
           (expect 0 :to-equal status)
           (expect 2 :to-equal *sexp-evaluator-test-failure-policy-calls*)
           (expect t :to-equal
                   (third (first *sexp-evaluator-test-calls*)))
           (expect :stream :to-equal
                   (second (first *sexp-evaluator-test-calls*)))
           (expect nil :to-equal
                   (third (second *sexp-evaluator-test-calls*))))
         (setf *sexp-evaluator-test-calls* nil)
         (multiple-value-bind (value status)
             (%evaluate-sexp-evaluator-test-source
              context "(if (> 3 2) \"host\" \"other\")")
           (expect "host" :to-equal value)
           (expect 0 :to-equal status)
           (expect *sexp-evaluator-test-calls* :to-be-null)))))))
(describe "sexp-evaluator-repetition"
  (it "runs-each-body-command-in-stream-position"
    (let ((context (make-test-shell-context)))
      (%call-with-sexp-evaluator-test-boundaries
       context
       (lambda ()
         (multiple-value-bind (value status)
             (%evaluate-sexp-evaluator-test-source
              context "(dotimes (index 2) (echo marker))")
           (expect nil :to-equal value)
           (expect 0 :to-equal status)
           (expect 2 :to-equal (length *sexp-evaluator-test-calls*))
           (expect :stream :to-equal
                   (second (first *sexp-evaluator-test-calls*)))
           (expect :stream :to-equal
                   (second (second *sexp-evaluator-test-calls*))))))))
  (it "runs-each-list-body-command-in-stream-position"
    (let* ((context (make-test-shell-context))
           (source
             "(dolist (item '(\"first\" \"second\") (list item)) (echo ,item))")
           (reader-result
             (first
              (nshell.domain.parsing:read-submission
               source :reader-context :sexp))))
      (let ((*sexp-evaluator-test-use-real-command-form->ast-p* t))
        (%call-with-sexp-evaluator-test-boundaries
         context
         (lambda ()
           (multiple-value-bind (value status)
               (nshell.application:evaluate-reader-result-in-context
                context reader-result)
             (expect '(nil) :to-equal value)
             (expect 0 :to-equal status)
             (expect 2 :to-equal (length *sexp-evaluator-test-calls*))
             (expect '(:stream :stream)
                     :to-equal
                     (mapcar #'second *sexp-evaluator-test-calls*))
             (expect '(("first") ("second"))
                     :to-equal
                     (mapcar
                      (lambda (call)
                        (mapcar
                         #'nshell.domain.parsing:evaluated-command-arg-value
                         (nshell.application:evaluated-command-stage-arguments
                          (first call))))
                      *sexp-evaluator-test-calls*)))))))))
(describe "sexp-evaluator-command-values"
  (it "evaluates-value-and-splice-operands-once"
    (let* ((context (make-test-shell-context))
           (counter (intern "L02-EVALUATOR-COUNTER" (find-package "NSHELL.USER")))
           (literal
             (nshell.domain.parsing:make-command-arg
              "literal" nil nil nil '(1 2) t t))
           (value-form
             (nshell.domain.parsing:make-command-value-form
              :value `(cl:setq ,counter (cl:+ ,counter 1)) '(3 8)))
           (splice-form
             (nshell.domain.parsing:make-command-value-form
              :splice '(cl:list "one" "two") '(9 14)))
           (quoted-form
             (nshell.domain.parsing:make-command-value-form
              :quoted '(cl:list "raw") '(15 20)))
           (redirect-arg
             (nshell.domain.parsing:make-command-arg
              "output.txt" nil nil nil '(21 31) t t))
           (redirect
             (nshell.domain.parsing:make-ast-redirect-entry
              :output-file 1 redirect-arg '(21 31) 2))
           (node
             (nshell.domain.parsing:make-command-node
              "echo" (list literal) '(0 32) nil nil (list redirect) nil
              (list literal value-form splice-form quoted-form)))
           (source-form `(cl:let ((,counter 0)) ,node ,counter))
           (reader-result
             (%make-sexp-evaluator-test-reader-result
              "(let ((counter 0)) (echo))" source-form)))
      (%call-with-sexp-evaluator-test-boundaries
       context
       (lambda ()
         (multiple-value-bind (value status)
             (nshell.application:evaluate-reader-result-in-context
              context reader-result)
           (let* ((stage (first (first *sexp-evaluator-test-calls*)))
                  (arguments
                    (nshell.application:evaluated-command-stage-arguments
                     stage))
                  (redirect-values
                    (nshell.application:evaluated-command-stage-redirect-target-values
                     stage)))
             (expect 1 :to-equal value)
             (expect 0 :to-equal status)
             (expect 5 :to-equal (length arguments))
             (expect '("literal" 1 "one" "two" (cl:list "raw"))
                     :to-equal
                     (mapcar
                      #'nshell.domain.parsing:evaluated-command-arg-value
                      arguments))
             (expect
              (nshell.domain.parsing:evaluated-command-arg-glob-p
               (first arguments))
              :to-be-truthy)
             (expect
              (nshell.domain.parsing:evaluated-command-arg-expand-p
               (first arguments))
              :to-be-truthy)
             (expect nil :to-equal
                     (nshell.domain.parsing:evaluated-command-arg-expand-p
                      (second arguments)))
             (expect 1 :to-equal (length redirect-values))
             (expect 2 :to-equal (caar redirect-values))
             (expect "output.txt" :to-equal
                     (nshell.domain.parsing:evaluated-command-arg-value
                      (cdar redirect-values)))))))))
  (it "rejects-dotted-command-splice-values"
    (let* ((context (make-test-shell-context))
           (splice-form
             (nshell.domain.parsing:make-command-value-form
              :splice
              (quote
               (cl:cons (cl:car (cl:quote (one)))
                        (cl:car (cl:quote (tail)))))
              (quote (1 2))))
           (reader-result
             (%make-sexp-evaluator-test-reader-result "()")))
      (%call-with-sexp-evaluator-test-boundaries
       context
       (lambda ()
         (expect
          (lambda ()
            (nshell.application::%evaluate-command-value-form
             context splice-form reader-result nil))
          :to-throw (quote nshell.application:sexp-evaluation-syntax-error))
         (expect nil :to-equal *sexp-evaluator-test-calls*))))))
(describe "sexp-evaluator-set"
  (it "routes-set-through-the-builtin-boundary"
    (let ((context (make-test-shell-context)))
      (%call-with-sexp-evaluator-test-boundaries
       context
       (lambda ()
         (%evaluate-sexp-evaluator-test-source context "(set \"name\" \"value\")")
         (let* ((stage (first (first *sexp-evaluator-test-calls*)))
                (node
                  (nshell.application:evaluated-command-stage-command-node
                   stage)))
           (expect :builtin :to-equal
                   (nshell.application:evaluated-command-stage-dispatch-kind
                    stage))
           (expect "set" :to-equal
                   (string-downcase
                    (nshell.domain.parsing:command-node-command node)))))))))
(describe "sexp-evaluator-value-position"
  (it "passes-value-position-and-rejects-value-builtins-in-stream-position"
    (let ((context (make-test-shell-context)))
      (%call-with-sexp-evaluator-test-boundaries
       context
       (lambda ()
         (multiple-value-bind (value status)
             (%evaluate-sexp-evaluator-test-source context "(identity (echo))")
           (expect (format nil "echo output~%") :to-equal value)
           (expect 0 :to-equal status)
           (expect :value :to-equal
                   (second (first *sexp-evaluator-test-calls*))))
         (expect
          (lambda ()
            (let ((nshell.application::*command-stage-call-position* :stream))
              (nshell.application:evaluate-command-stage-in-context
               context
               (nshell.domain.parsing:make-command-node "value" nil '(0 7)))))
          :to-throw 'nshell.application:command-execution-plan-error))))))
(describe "sexp-evaluator-defun"
  (it "calls-a-defined-function-with-a-lexical-command-argument"
    (let* ((context (make-test-shell-context))
           (function-name
             (intern "L02-EVALUATOR-GREET" (find-package "NSHELL.USER")))
           (variable (intern "NAME" (find-package "NSHELL.USER")))
           (argument
             (nshell.domain.parsing:make-command-value-form
              :value variable '(25 30)))
           (body-command
             (nshell.domain.parsing:make-command-node
              "echo" nil '(20 31) nil nil nil nil (list argument)))
           (defun-form
             (list 'cl:defun function-name (list variable) body-command))
           (def-reader
             (%make-sexp-evaluator-test-reader-result
              "(DEFUN L02-EVALUATOR-GREET (NAME) (ECHO $NAME))" defun-form))
           (call-reader
             (%make-sexp-evaluator-test-reader-result
              "(L02-EVALUATOR-GREET \"hello\")"
              (list function-name "hello"))))
      (unwind-protect
           (%call-with-sexp-evaluator-test-boundaries
            context
            (lambda ()
              (nshell.application:evaluate-reader-result-in-context
               context def-reader)
              (multiple-value-bind (value status)
                  (nshell.application:evaluate-reader-result-in-context
                   context call-reader)
                (let* ((stage (first (first *sexp-evaluator-test-calls*)))
                       (arguments
                         (nshell.application:evaluated-command-stage-arguments
                          stage)))
                  (expect (format nil "echo output~%") :to-equal value)
                  (expect 0 :to-equal status)
                  (expect "hello" :to-equal
                          (nshell.domain.parsing:evaluated-command-arg-value
                           (first arguments)))))))
        (when (fboundp function-name) (fmakunbound function-name)))))
  (it "allows-nested-definitions-and-rejects-invalid-lambda-lists"
    (let* ((context (make-test-shell-context))
           (nested-name
             (intern "L02-EVALUATOR-NESTED" (find-package "NSHELL.USER")))
           (invalid-name
             (intern "L02-EVALUATOR-INVALID" (find-package "NSHELL.USER"))))
      (unwind-protect
           (multiple-value-bind (value status)
               (%evaluate-sexp-evaluator-test-source
                context
                "(progn (when t (defun L02-EVALUATOR-NESTED (value) (+ value 1))) (L02-EVALUATOR-NESTED 41))")
             (expect 42 :to-equal value)
             (expect 0 :to-equal status)
             (expect
              (lambda ()
                (%evaluate-sexp-evaluator-test-source
                 context
                 "(defun L02-EVALUATOR-INVALID (required &optional optional &optional repeated) required)"))
              :to-throw 'error)
             (expect
              (lambda ()
                (%evaluate-sexp-evaluator-test-source
                 context "(L02-EVALUATOR-NESTED)"))
              :to-throw 'program-error))
        (when (fboundp nested-name) (fmakunbound nested-name))
        (when (fboundp invalid-name) (fmakunbound invalid-name))))))
(describe "sexp-evaluator-shell-function"
  (it "registers-and-calls-a-shell-function-through-l07"
    (let* ((context (make-test-shell-context))
           (function-name
             (intern "L02-SHELL-GREET" (find-package "NSHELL.USER")))
           (variable (intern "NAME" (find-package "NSHELL.USER")))
           (argument
             (nshell.domain.parsing:make-command-value-form
              :value variable '(25 30)))
           (body-command
             (nshell.domain.parsing:make-command-node
              "echo" nil '(20 31) nil nil nil nil (list argument)))
           (definition
             (list 'nshell.user::define-shell-function function-name
                   (list variable) body-command))
           (reader-result
             (%make-sexp-evaluator-test-reader-result
              "(DEFINE-SHELL-FUNCTION L02-SHELL-GREET (NAME) (ECHO $NAME))"
              definition))
           (call-reader
             (%make-sexp-evaluator-test-reader-result
              "(L02-SHELL-GREET \"hello\")"
              (list function-name "hello"))))
      (%call-with-sexp-evaluator-test-boundaries
       context
       (lambda ()
         (nshell.application:evaluate-reader-result-in-context
          context reader-result)
         (multiple-value-bind (value status)
             (nshell.application:evaluate-reader-result-in-context
              context call-reader)
           (let* ((calls *sexp-evaluator-test-calls*)
                  (body-stage (first (first calls)))
                  (function-stage (first (second calls))))
             (expect (format nil "echo output~%") :to-equal value)
             (expect 0 :to-equal status)
             (expect "hello" :to-equal
                     (nshell.domain.parsing:evaluated-command-arg-value
                      (first
                       (nshell.application:evaluated-command-stage-arguments
                        body-stage))))
             (expect :shell-function :to-equal
                     (nshell.application:evaluated-command-stage-dispatch-kind
                      function-stage)))))))))
(describe "sexp-evaluator-macros"
  (it "expands-a-user-macro-into-two-command-stages"
    (let* ((context (make-test-shell-context))
           (macro-name
             (intern "L02-EVALUATOR-TWICE" (find-package "NSHELL.USER")))
           (definition
             (let ((*package* (find-package "NSHELL.USER")))
               (read-from-string
                "(DEFMACRO L02-EVALUATOR-TWICE (FORM) `(PROGN ,FORM ,FORM))")))
           (definition-result
             (%make-sexp-evaluator-test-reader-result
              "(DEFMACRO L02-EVALUATOR-TWICE (FORM) `(PROGN ,FORM ,FORM))"
              definition)))
      (unwind-protect
           (%call-with-sexp-evaluator-test-boundaries
            context
            (lambda ()
              (nshell.application:evaluate-reader-result-in-context
               context definition-result)
              (multiple-value-bind (value status)
                  (%evaluate-sexp-evaluator-test-source
                   context "(L02-EVALUATOR-TWICE (ECHO MARKER))")
                (expect (format nil "echo output~%") :to-equal value)
                (expect 0 :to-equal status)
                (expect 2 :to-equal (length *sexp-evaluator-test-calls*))
                (expect 2 :to-equal
                        *sexp-evaluator-test-failure-policy-calls*))))
        (when (macro-function macro-name) (fmakunbound macro-name)))))
  (it "expands a macro read by the S-expression reader"
  (let* ((context (make-test-shell-context))
         (macro-name
           (intern "L07-READER-MACRO-TWICE" (find-package "NSHELL.USER")))
         (definition-result
           (first
            (nshell.domain.parsing:read-submission
             "(defmacro L07-READER-MACRO-TWICE (form &rest forms) `(progn ,form ,@forms))"
             :reader-context :sexp)))
         (call-result
           (first
            (nshell.domain.parsing:read-submission
             "(L07-READER-MACRO-TWICE (echo first) (echo second))"
             :reader-context :sexp))))
    (unwind-protect
         (%call-with-sexp-evaluator-test-boundaries
          context
          (lambda ()
            (nshell.application:evaluate-reader-result-in-context
             context definition-result)
            (multiple-value-bind (value status)
                (nshell.application:evaluate-reader-result-in-context
                 context call-result)
              (expect (format nil "echo output~%") :to-equal value)
              (expect 0 :to-equal status)
              (expect 2 :to-equal (length *sexp-evaluator-test-calls*)))))
      (when (macro-function macro-name) (fmakunbound macro-name)))))
  (it "limits-nested-expansion-without-limiting-independent-calls"
    (let* ((context (make-test-shell-context))
           (recursive-name
             (intern "L02-EVALUATOR-RECURSIVE" (find-package "NSHELL.USER")))
           (constant-name
             (intern "L02-EVALUATOR-CONSTANT" (find-package "NSHELL.USER")))
           (recursive-expansion-count 0)
           (expanded-source
             (format nil "(progn~{ (~a)~})"
                     (make-list 129 :initial-element
                                "L02-EVALUATOR-CONSTANT"))))
      (unwind-protect
           (progn
             (setf (macro-function recursive-name)
                   (lambda (form environment)
                     (declare (ignore environment))
                     (incf recursive-expansion-count)
                     form))
             (setf (macro-function constant-name)
                   (lambda (form environment)
                     (declare (ignore form environment))
                     1))
             (%call-with-sexp-evaluator-test-boundaries
              context
              (lambda ()
                (expect
                 (lambda ()
                   (%evaluate-sexp-evaluator-test-source
                    context "(L02-EVALUATOR-RECURSIVE)"))
                 :to-throw 'nshell.application:command-macro-syntax-error)
                (expect 128 :to-equal recursive-expansion-count)
                (multiple-value-bind (value status)
                    (%evaluate-sexp-evaluator-test-source
                     context expanded-source)
                  (expect 1 :to-equal value)
                  (expect 0 :to-equal status)))))
        (when (macro-function recursive-name) (fmakunbound recursive-name))
        (when (macro-function constant-name) (fmakunbound constant-name)))))
  (it "reports-macro-expansion-errors-at-call-site-and-keeps-runtime-errors-distinct"
  (let* ((context (make-test-shell-context))
         (source-path "k08-macro-expansion-error.nsh")
         (source
           (format nil
                   "(defmacro l02-k08-bad-form () (error ~S))~%(l02-k08-bad-form)"
                   "K08_EXPANSION_ERROR"))
         (runtime-source-path "k08-macro-runtime-error.nsh")
         (runtime-source
           (format nil
                   "(defmacro l02-k08-runtime-bad-form () '(error ~S))~%(l02-k08-runtime-bad-form)"
                   "K08_RUNTIME_EVAL_ERROR"))
         (reader-results
           (nshell.domain.parsing:read-submission
            source :reader-context :sexp :source-path source-path))
         (runtime-reader-results
           (nshell.domain.parsing:read-submission
            runtime-source :reader-context :sexp
            :source-path runtime-source-path))
         (macro-name
           (intern "L02-K08-BAD-FORM" (find-package "NSHELL.USER")))
         (runtime-macro-name
           (intern "L02-K08-RUNTIME-BAD-FORM" (find-package "NSHELL.USER")))
         (call-span
           (let* ((call "(l02-k08-bad-form)")
                  (start (search call source)))
             (list start (+ start (length call)))))
         (expansion-condition nil)
         (runtime-condition nil))
    (unwind-protect
         (%call-with-sexp-evaluator-test-boundaries
          context
          (lambda ()
            (nshell.application:evaluate-reader-result-in-context
             context (first reader-results))
            (setf expansion-condition
                  (handler-case
                      (progn
                        (nshell.application:evaluate-reader-result-in-context
                         context (second reader-results))
                        nil)
                    (error (condition) condition)))
            (nshell.application:evaluate-reader-result-in-context
             context (first runtime-reader-results))
            (setf runtime-condition
                  (handler-case
                      (progn
                        (nshell.application:evaluate-reader-result-in-context
                         context (second runtime-reader-results))
                        nil)
                    (error (condition) condition)))
            (expect t :to-equal
                    (typep expansion-condition
                           'nshell.application:command-macro-syntax-error))
            (expect call-span :to-equal
                    (and (typep expansion-condition
                                'nshell.application:command-macro-syntax-error)
                         (nshell.application:command-macro-syntax-error-source-span
                          expansion-condition)))
            (expect source-path :to-equal
                    (and (typep expansion-condition
                                'nshell.application:command-macro-syntax-error)
                         (nshell.application:command-macro-syntax-error-source-path
                          expansion-condition)))
            (expect t :to-equal
                    (and (typep expansion-condition
                                'nshell.application:command-macro-syntax-error)
                         (typep
                          (nshell.application:command-macro-syntax-error-cause
                           expansion-condition)
                          'simple-error)))
            (expect "K08_EXPANSION_ERROR" :to-equal
                    (and (typep expansion-condition
                                'nshell.application:command-macro-syntax-error)
                         (let ((cause
                                 (nshell.application:command-macro-syntax-error-cause
                                  expansion-condition)))
                           (and (typep cause 'simple-error)
                                (simple-condition-format-control cause)))))
            (expect t :to-equal (typep runtime-condition 'simple-error))
            (expect nil :to-equal
                    (typep runtime-condition
                           'nshell.application:command-macro-syntax-error))
            (expect "K08_RUNTIME_EVAL_ERROR" :to-equal
                    (and (typep runtime-condition 'simple-error)
                         (simple-condition-format-control runtime-condition)))))
      (when (macro-function macro-name) (fmakunbound macro-name))
      (when (macro-function runtime-macro-name)
        (fmakunbound runtime-macro-name))))))

(describe "sexp-evaluator-reader-integration"
  (it "reads-host-and-command-forms-through-the-real-ast-adapter"
    (let ((context (make-test-shell-context)))
      (let ((*sexp-evaluator-test-use-real-command-form->ast-p* t))
        (%call-with-sexp-evaluator-test-boundaries
         context
         (lambda ()
           (let* ((host-source "(progn (echo first) (echo last))")
                  (host-reader-result
                    (first
                     (nshell.domain.parsing:read-submission
                      host-source :reader-context :sexp))))
             (multiple-value-bind (value status)
                 (nshell.application:evaluate-reader-result-in-context
                  context host-reader-result)
               (let* ((first-call (first *sexp-evaluator-test-calls*))
                      (first-stage (first first-call))
                      (first-node
                        (nshell.application:evaluated-command-stage-command-node
                         first-stage))
                      (first-arguments
                        (nshell.application:evaluated-command-stage-arguments
                         first-stage)))
                 (expect (format nil "echo output~%") :to-equal value)
                 (expect 0 :to-equal status)
                 (expect 2 :to-equal
                         (length *sexp-evaluator-test-calls*))
                 (expect '(:stream :value)
                         :to-equal
                         (mapcar #'second *sexp-evaluator-test-calls*))
                 (expect "echo" :to-equal
                         (nshell.domain.parsing:command-node-command
                          first-node))
                 (expect '("first")
                         :to-equal
                         (mapcar
                          #'nshell.domain.parsing:evaluated-command-arg-value
                          first-arguments))))
             (setf *sexp-evaluator-test-calls* nil)
             (let* ((command-source "(echo direct)")
                    (command-reader-result
                      (first
                       (nshell.domain.parsing:read-submission
                        command-source :reader-context :sexp))))
               (multiple-value-bind (value status)
                   (nshell.application:evaluate-reader-result-in-context
                    context command-reader-result)
                 (expect (format nil "echo output~%") :to-equal value)
                 (expect 0 :to-equal status)
                 (expect :stream :to-equal
                         (second (first *sexp-evaluator-test-calls*)))
                 (expect '("direct")
                         :to-equal
                         (mapcar
                          #'nshell.domain.parsing:evaluated-command-arg-value
                          (nshell.application:evaluated-command-stage-arguments
                           (first
                            (first *sexp-evaluator-test-calls*)))))))))))))
  (it "rejects-opaque-reader-markers-before-host-evaluation"
    (let* ((context (make-test-shell-context))
           (host-source
             "(progn (echo before) (if t (echo reached) (echo #S(vendor :value 1))))")
           (marker-start (search "#S" host-source))
           (marker-span
             (list marker-start
                   (+ marker-start (length "#S(vendor :value 1)"))))
           (host-reader-result
             (first
              (nshell.domain.parsing:read-submission
               host-source :reader-context :sexp))))
      (let ((*sexp-evaluator-test-use-real-command-form->ast-p* t))
        (%call-with-sexp-evaluator-test-boundaries
         context
         (lambda ()
           (let ((condition
                   (handler-case
                       (progn
                         (nshell.application:evaluate-reader-result-in-context
                          context host-reader-result)
                         nil)
                     (nshell.application:sexp-evaluation-syntax-error
                       (condition)
                       condition))))
             (expect condition :to-be-truthy)
             (expect marker-span
                     :to-equal
                     (nshell.application:sexp-evaluation-syntax-error-source-span
                      condition))
             (expect nil
                     :to-equal
                     (nshell.application:sexp-evaluation-syntax-error-source-path
                      condition))
             (expect nil :to-equal *sexp-evaluator-test-calls*)
             (expect 0 :to-equal
                     *sexp-evaluator-test-failure-policy-calls*))
           (let* ((quoted-source "(quote #S(vendor :value 1))")
                  (quoted-reader-result
                    (first
                     (nshell.domain.parsing:read-submission
                      quoted-source :reader-context :sexp))))
             (expect
              (lambda ()
                (nshell.application:evaluate-reader-result-in-context
                 context quoted-reader-result))
              :to-throw 'nshell.application:sexp-evaluation-syntax-error)
             (expect nil :to-equal *sexp-evaluator-test-calls*))
           (let* ((command-source "(echo #S(vendor :value 1))")
                  (command-reader-result
                    (first
                     (nshell.domain.parsing:read-submission
                      command-source :reader-context :sexp))))
             (multiple-value-bind (value status)
                 (nshell.application:evaluate-reader-result-in-context
                  context command-reader-result)
               (let* ((call (first *sexp-evaluator-test-calls*))
                      (stage (first call))
                      (arguments
                        (nshell.application:evaluated-command-stage-arguments
                         stage)))
                 (expect (format nil "echo output~%") :to-equal value)
                 (expect 0 :to-equal status)
                 (expect :stream :to-equal (second call))
                 (expect '("#S(vendor :value 1)")
                         :to-equal
                         (mapcar
                          #'nshell.domain.parsing:evaluated-command-arg-value
                          arguments)))))))))))

(describe "sexp-evaluator-opaque-command-values"
  (it "rejects-opaque-markers-entering-a-command-value-expression"
    (let* ((context (make-test-shell-context))
           (source "(echo ,#S(vendor :value 1))")
           (reader-result
             (first
              (nshell.domain.parsing:read-submission
               source :reader-context :sexp))))
      (let ((*sexp-evaluator-test-use-real-command-form->ast-p* t))
        (%call-with-sexp-evaluator-test-boundaries
         context
         (lambda ()
           (expect
            (lambda ()
              (nshell.application:evaluate-reader-result-in-context
               context reader-result))
            :to-throw 'nshell.application:sexp-evaluation-syntax-error)
           (expect nil :to-equal *sexp-evaluator-test-calls*)
           (expect 1 :to-equal
                   *sexp-evaluator-test-failure-policy-calls*))))))
  (it "rejects-opaque-markers-in-quoted-command-values"
    (let* ((context (make-test-shell-context))
           (source "(echo '#S(vendor :value 1))")
           (reader-result
             (first
              (nshell.domain.parsing:read-submission
               source :reader-context :sexp))))
      (let ((*sexp-evaluator-test-use-real-command-form->ast-p* t))
        (%call-with-sexp-evaluator-test-boundaries
         context
         (lambda ()
           (expect
            (lambda ()
              (nshell.application:evaluate-reader-result-in-context
               context reader-result))
            :to-throw 'nshell.application:sexp-evaluation-syntax-error)
           (expect nil :to-equal *sexp-evaluator-test-calls*)
           (expect 1 :to-equal
                   *sexp-evaluator-test-failure-policy-calls*)))))))
