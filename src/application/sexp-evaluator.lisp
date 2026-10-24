(in-package #:nshell.application)

(defstruct (%sexp-lexical-environment
            (:constructor %make-sexp-lexical-environment (table parent)))
  table
  parent)

(defvar *command-stage-reader-result* nil)
(defvar *command-stage-lexical-environment* nil)
(defvar *command-stage-call-position* :stream)
(defvar *command-evaluation-position* :stream)
(defvar *current-user-evaluator-context* nil)
(defvar *current-user-evaluator-position* :value)
(defvar *current-evaluation-status* 0)
(defvar *macro-expansion-origin-map* nil)
(defvar *macro-expansion-symbol-origin-map* nil)
(defvar *generated-command-head-origin-map* nil)
(defvar *macro-expansion-depth* 0)
(defvar *macro-expansion-depth-limit* 128)

(defun %extend-lexical-environment (parent bindings)
  (let ((table (make-hash-table :test #'eq)))
    (dolist (binding bindings)
      (setf (gethash (car binding) table) (cdr binding)))
    (%make-sexp-lexical-environment table parent)))

(defun %lexical-value (environment symbol)
  (loop for frame = environment then (%sexp-lexical-environment-parent frame)
        while frame
        do (multiple-value-bind (value found-p)
               (gethash symbol (%sexp-lexical-environment-table frame))
             (when found-p (return-from %lexical-value (values value t))))
        finally (return (values nil nil))))

(defun %reader-symbol-origin (reader-result symbol)
  (let ((origins
          (nshell.domain.parsing:reader-result-symbol-origins reader-result)))
    (and (symbolp symbol) (hash-table-p origins) (gethash symbol origins))))

(defun %origin-field (origin primary &optional alternate)
  (or (getf origin primary)
      (and alternate (getf origin alternate))))

(defun %reader-symbol-origin-info (reader-result symbol)
  (let ((origin (%reader-symbol-origin reader-result symbol)))
    (values (%origin-field origin :source-name)
            (%origin-field origin :escaped-p)
            (%origin-field origin :package-qualifier :package)
            (%origin-field origin :source-span :span))))
(defun %reject-opaque-dispatch-markers (form reader-result)
  (let ((visited (make-hash-table :test #'eq)))
    (labels ((visit (object)
               (when (symbolp object)
                 (let ((origin (%reader-symbol-origin reader-result object)))
                   (when (getf origin :opaque-dispatch-p)
                     (error 'sexp-evaluation-syntax-error
                            :source-span (%origin-field origin :source-span)
                            :source-path
                            (nshell.domain.parsing:reader-result-source-path
                             reader-result)
                            :cause
                            (make-condition
                             'simple-error
                             :format-control
                             "Opaque reader dispatch syntax cannot be evaluated as a host form."
                             :format-arguments nil)))))
               (when (or (consp object)
                         (and (vectorp object) (not (stringp object))))
                 (unless (gethash object visited)
                   (setf (gethash object visited) t)
                   (if (consp object)
                       (let ((tail object))
                         (loop while (consp tail)
                               do (when (and (not (eq tail object))
                                             (gethash tail visited))
                                    (return))
                                  (setf (gethash tail visited) t)
                                  (visit (car tail))
                                  (setf tail (cdr tail))
                               finally (when tail (visit tail))))
                       (loop for item across object do (visit item)))))))
      (visit form))))

(defun %find-user-symbol (name)
  (or (find-symbol name (find-package "NSHELL.USER"))
      (intern name (find-package "NSHELL.USER"))))

(defun %resolve-reader-symbol (reader-result symbol)
  (multiple-value-bind (source-name escaped-p package-qualifier)
      (%reader-symbol-origin-info reader-result symbol)
    (if (null source-name)
        symbol
        (let* ((package-name
                 (and package-qualifier
                      (typecase package-qualifier
                        (package (package-name package-qualifier))
                        (string package-qualifier)
                        (symbol (symbol-name package-qualifier)))))
               (name
                 (if (and (not escaped-p)
                          (or package-name
                              (find-symbol (string-upcase source-name)
                                           (find-package "COMMON-LISP"))))
                     (string-upcase source-name)
                     source-name)))
          (cond
            (package-name
             (let ((package (find-package package-name)))
               (unless package
                 (error "Unknown package qualifier ~S" package-name))
               (if (eq package (find-package "KEYWORD"))
                   (intern name package)
                   (or (find-symbol name package)
                       (intern name package)))))
            ((and (not escaped-p)
                  (find-symbol (string-upcase source-name)
                               (find-package "COMMON-LISP")))
             (find-symbol (string-upcase source-name)
                          (find-package "COMMON-LISP")))
            (t (%find-user-symbol source-name)))))))

(defun %materialize-reader-form (form reader-result)
  (cond
    ((symbolp form) (%resolve-reader-symbol reader-result form))
    ((consp form)
     (cons (%materialize-reader-form (car form) reader-result)
           (%materialize-reader-form (cdr form) reader-result)))
    ((and (vectorp form) (not (stringp form)))
     (map 'vector (lambda (item)
                    (%materialize-reader-form item reader-result))
          form))
    (t form)))

(defun %make-reader-origin-overlay (reader-result)
  (let ((origins (make-hash-table :test #'eq)))
    (maphash (lambda (form span) (setf (gethash form origins) span))
             (nshell.domain.parsing:reader-result-form-span-map reader-result))
    origins))

(defun %source-form-span (form reader-result)
  (or (and *macro-expansion-origin-map*
           (gethash form *macro-expansion-origin-map*))
      (gethash form
               (nshell.domain.parsing:reader-result-form-span-map
                reader-result))
      (and (eq form (nshell.domain.parsing:reader-result-form reader-result))
           (nshell.domain.parsing:reader-result-source-span reader-result))))

(defun %copy-form-origins (source-form target-form reader-result)
  (let ((visited (make-hash-table :test #'eq)))
    (labels ((walk (source target)
               (when (and (consp source) (consp target)
                          (not (gethash source visited)))
                 (setf (gethash source visited) t)
                 (when (and (symbolp (car source))
                            (symbolp (car target))
                            *macro-expansion-symbol-origin-map*)
                   (let ((origin (%reader-symbol-origin reader-result
                                                       (car source))))
                     (when origin
                       (setf (gethash (car target)
                                      *macro-expansion-symbol-origin-map*)
                             origin))))
                 (let ((span
                         (gethash
                          source
                          (nshell.domain.parsing:reader-result-form-span-map
                           reader-result))))
                   (when (and span *macro-expansion-origin-map*)
                     (setf (gethash target *macro-expansion-origin-map*) span)))
                 (walk (car source) (car target))
                 (walk (cdr source) (cdr target)))
               (when (and (vectorp source) (not (stringp source))
                          (vectorp target) (not (stringp target)))
                 (let ((span
                         (gethash
                          source
                          (nshell.domain.parsing:reader-result-form-span-map
                           reader-result))))
                   (when (and span *macro-expansion-origin-map*)
                     (setf (gethash target *macro-expansion-origin-map*) span))
                   (loop for left across source
                         for right across target
                         do (walk left right))))))
      (walk source-form target-form)))
  target-form)

(defun %propagate-expansion-origin (form span)
  (when (and span *macro-expansion-origin-map*)
    (let ((visited (make-hash-table :test #'eq)))
      (labels ((walk (node)
                 (when (and (or (consp node)
                                (and (vectorp node) (not (stringp node))))
                            (not (gethash node visited)))
                   (setf (gethash node visited) t)
                   (unless (gethash node *macro-expansion-origin-map*)
                     (setf (gethash node *macro-expansion-origin-map*) span))
                   (cond
                     ((consp node)
                      (walk (car node))
                      (walk (cdr node)))
                     ((and (vectorp node) (not (stringp node)))
                      (map nil #'walk node))))))
        (walk form))))
  form)

(defun %head-source-separator (source)
  (loop with in-bars-p = nil
        with escaped-p = nil
        for index below (length source)
        for character = (char source index)
        do (cond
             (escaped-p (setf escaped-p nil))
             ((char= character #\\) (setf escaped-p t))
             ((char= character #\|) (setf in-bars-p (not in-bars-p)))
             ((and (not in-bars-p) (char= character #\:))
              (return index)))))

(defun %decode-head-source-part (source start end)
  (with-output-to-string (decoded)
    (loop with in-bars-p = nil
          with escaped-p = nil
          for index from start below end
          for character = (char source index)
          do (cond
               (escaped-p
                (write-char character decoded)
                (setf escaped-p nil))
               ((char= character #\\) (setf escaped-p t))
               ((char= character #\|) (setf in-bars-p (not in-bars-p)))
               (t (write-char character decoded))))))

(defun %parse-head-source (source)
  (let* ((source (or source ""))
         (forced-p (and (plusp (length source))
                        (char= (char source 0) #\^)))
         (token (if forced-p (subseq source 1) source))
         (separator (%head-source-separator token))
         (name-start
           (if separator
               (if (and (< (1+ separator) (length token))
                        (char= (char token (1+ separator)) #\:))
                   (+ separator 2)
                   (1+ separator))
               0))
         (package-source (and separator
                              (subseq token 0 separator)))
         (package-escaped-p
           (and package-source
                (plusp (length package-source))
                (char= (char package-source 0) #\|)))
         (package-name
           (cond
             ((and separator (zerop separator)) "KEYWORD")
             (separator
              (let ((decoded (%decode-head-source-part
                              token 0 separator)))
                (if package-escaped-p decoded (string-upcase decoded))))))
         (name (%decode-head-source-part token name-start (length token)))
         (escaped-p
           (and (< name-start (length token))
                (char= (char token name-start) #\|))))
    (values name escaped-p package-name forced-p)))

(defun %cl-head-name (name escaped-p)
  (if escaped-p name (string-upcase name)))

(defun %evaluator-aware-head-p (name escaped-p)
  (and (not escaped-p)
       (member (string-upcase name)
               '("IF" "WHEN" "UNLESS" "AND" "OR" "NOT" "LET" "LET*"
                 "PROGN" "COND" "CASE" "HANDLER-CASE" "DEFUN" "DEFMACRO"
                 "DEFINE-SHELL-FUNCTION")
               :test #'string=)))

(defun %user-package-function-or-macro-p (name)
  (multiple-value-bind (symbol status)
      (find-symbol name (find-package "NSHELL.USER"))
    (and symbol (member status '(:internal :external))
         (or (fboundp symbol) (macro-function symbol)))))

(defun %peek-shell-function-p (context name escaped-p)
  (multiple-value-bind (binding found-p)
      (peek-shell-function (context-shell-function-registry context)
                           name
                           :scope (active-shell-function-scope)
                           :escaped-p escaped-p)
    (declare (ignore binding))
    found-p))

(defun %command-path-candidate-p (context name)
  (not (null (%resolve-command-path-candidates context name))))

(defun classify-sexp-head (context head-source)
  (multiple-value-bind (name escaped-p package-name forced-p)
      (%parse-head-source head-source)
    (cond
      (forced-p :command-island)
      (package-name :host-form)
      ((%evaluator-aware-head-p name escaped-p) :host-form)
      ((%user-package-function-or-macro-p name) :host-form)
      ((%peek-shell-function-p context name escaped-p) :command-island)
      ((nth-value 1 (lookup-builtin-binding name)) :command-island)
      ((%command-path-candidate-p context name) :command-island)
      ((let ((symbol (find-symbol (%cl-head-name name escaped-p) "CL")))
         (and symbol
              (or (special-operator-p symbol)
                  (macro-function symbol)
                  (fboundp symbol))))
       :host-form)
      (t :command-island))))

(defun %source-head-token (source span)
  (when (and source span)
    (let ((position (1+ (first span)))
          (end (second span)))
      (loop while (< position end)
            for character = (char source position)
            do (cond
                 ((find character
                        (quote (#\Space #\Tab #\Newline #\Return)))
                  (incf position))
                 ((char= character #\;)
                  (loop while (and (< position end)
                                   (char/= (char source position) #\Newline))
                        do (incf position)))
                 (t (return))))
      (let ((start position))
        (loop with in-bars-p = nil
              with escaped-p = nil
              while (< position end)
              for character = (char source position)
              do (cond
                   (escaped-p (setf escaped-p nil) (incf position))
                   ((char= character #\\)
                    (setf escaped-p t)
                    (incf position))
                   ((char= character #\|)
                    (setf in-bars-p (not in-bars-p))
                    (incf position))
                   ((and (not in-bars-p)
                         (find character
                               (quote (#\Space #\Tab #\Newline #\Return
                                       #\; #\)))))
                    (return-from %source-head-token
                      (subseq source start position)))
                   (t (incf position)))
              finally (return (subseq source start position)))))))

(defun %form-head-source (form reader-result)
  (%source-head-token
   (nshell.domain.parsing:reader-result-source reader-result)
   (%source-form-span form reader-result)))

(defun %source-backed-form-p (form reader-result)
  (or (gethash form
               (nshell.domain.parsing:reader-result-form-span-map reader-result))
      (eq form (nshell.domain.parsing:reader-result-form reader-result))))

(defun %symbol-command-classification (context symbol)
  (let* ((package (symbol-package symbol))
         (origin (and *macro-expansion-symbol-origin-map*
                      (gethash symbol *macro-expansion-symbol-origin-map*)))
         (source-name (%origin-field origin :source-name))
         (escaped-p (%origin-field origin :escaped-p))
         (package-qualifier
           (%origin-field origin :package-qualifier :package))
         (name (or source-name (symbol-name symbol))))
    (cond
      (package-qualifier :host-form)
      ((and (null origin)
            (or (null package)
           (member (package-name package) '("COMMON-LISP" "KEYWORD")
                   :test #'string=)))
       :host-form)
      ((and (not escaped-p)
            (%evaluator-aware-head-p name nil))
       :host-form)
      ((and (string= (package-name package) "NSHELL.USER")
            (or (fboundp symbol) (macro-function symbol)))
       :host-form)
      ((%peek-shell-function-p context name escaped-p) :command-island)
      ((nth-value 1 (lookup-builtin-binding name)) :command-island)
      ((%command-path-candidate-p context name) :command-island)
      ((and (not escaped-p)
            (let ((host-symbol (find-symbol (string-upcase name) "CL")))
         (and host-symbol
              (or (special-operator-p host-symbol)
                  (macro-function host-symbol)
                  (fboundp host-symbol)))))
       :host-form)
      (t :command-island))))

(defun %form-command-classification (context form reader-result)
  (if (%source-backed-form-p form reader-result)
      (classify-sexp-head context (%form-head-source form reader-result))
      (%symbol-command-classification context (first form))))

(defun %resolve-form-operator (context form reader-result)
  (let ((head (first form)))
    (if (or (not (%source-backed-form-p form reader-result))
            (not (symbolp head))
            (null (%reader-symbol-origin reader-result head)))
        (if (symbolp head) (%resolve-reader-symbol reader-result head) head)
        (multiple-value-bind (source-name escaped-p package-qualifier)
            (%reader-symbol-origin-info reader-result head)
          (cond
            (package-qualifier (%resolve-reader-symbol reader-result head))
            (escaped-p (%find-user-symbol source-name))
            ((%evaluator-aware-head-p source-name nil)
             (or (find-symbol (string-upcase source-name) "CL")
                 (%find-user-symbol source-name)))
            ((%user-package-function-or-macro-p source-name)
             (%find-user-symbol source-name))
            ((find-symbol (string-upcase source-name) "CL")
             (find-symbol (string-upcase source-name) "CL"))
            (t (%find-user-symbol source-name)))))))

(defun %reader-pipeline-form-p (form reader-result)
  (and (consp form)
       (let* ((head (first form))
              (name (if (symbolp head)
                        (or (nth-value 0
                             (%reader-symbol-origin-info reader-result head))
                            (symbol-name head))
                        nil)))
         (or (and name (member name '("|" "|&") :test #'string=))
             (member head '(:pipeline :pipeline-stderr-to-stdout))))))

(defun %command-form->ast (context form reader-result)
  (nshell.domain.parsing:command-form->ast
   (nshell.domain.parsing:reader-result-source reader-result)
   form
   (nshell.domain.parsing:reader-result-form-span-map reader-result)
   (lambda (head-source) (classify-sexp-head context head-source))))

(defun %proper-list-p (value)
  (loop with slow = value
        with fast = value
        do (cond
             ((null fast) (return t))
             ((atom fast) (return nil))
             (t (setf fast (cdr fast))))
           (cond
             ((null fast) (return t))
             ((atom fast) (return nil))
             (t (setf fast (cdr fast) slow (cdr slow))))
           (when (eq fast slow) (return nil))))

(defun %eval-command-value-operand
    (context form reader-result lexical-environment)
  (%reject-opaque-dispatch-markers form reader-result)
  (if (symbolp form)
      (let ((symbol (%resolve-reader-symbol reader-result form)))
        (multiple-value-bind (value found-p)
            (%lexical-value lexical-environment symbol)
          (cond
            (found-p value)
            ((keywordp symbol) symbol)
            ((or (eq symbol t) (null symbol)) symbol)
            ((boundp symbol) (symbol-value symbol))
            (t
             (let ((name (nth-value 0
                                    (%reader-symbol-origin-info
                                     reader-result form)))
                   (package-qualifier
                     (nth-value 2 (%reader-symbol-origin-info
                                   reader-result form))))
               (when (and (null name)
                          (symbolp symbol)
                          (symbol-package symbol)
                          (string= (package-name (symbol-package symbol))
                                   "NSHELL.USER"))
                 (setf name (symbol-name symbol)))
               (if (or package-qualifier (null name)
                       (and (null (%reader-symbol-origin reader-result form))
                            (symbol-package symbol)
                            (not (string= (package-name (symbol-package symbol))
                                          "NSHELL.USER"))))
                   (error 'unbound-variable :name symbol)
                   (or (and (shell-context-environment context)
                            (nshell.domain.environment:env-get
                             (shell-context-environment context) name))
                       "")))))))
      (%eval-form context form reader-result lexical-environment :value)))

(defun %evaluate-command-value-form
    (context value-form reader-result lexical-environment)
  (let* ((span
           (nshell.domain.parsing:command-value-form-source-span value-form))
         (form (nshell.domain.parsing:command-value-form-form value-form)))
    (labels ((source-form-at-span ()
               (block found
                 (maphash (lambda (candidate candidate-span)
                            (when (equal span candidate-span)
                              (return-from found candidate)))
                          (nshell.domain.parsing:reader-result-form-span-map
                           reader-result))
                 (maphash (lambda (symbol origin)
                            (when (equal
                                   span
                                   (%origin-field origin :source-span))
                              (return-from found symbol)))
                          (nshell.domain.parsing:reader-result-symbol-origins
                           reader-result))
                 nil)))
      (%reject-opaque-dispatch-markers
       (or (source-form-at-span) form)
       reader-result)
      (case (nshell.domain.parsing:command-value-form-kind value-form)
        (:quoted
         (list (nshell.domain.parsing:make-evaluated-command-arg
                (%materialize-reader-form form reader-result)
                span nil nil)))
        (:value
         (list (nshell.domain.parsing:make-evaluated-command-arg
                (nth-value 0
                  (%eval-command-value-operand
                   context form reader-result lexical-environment))
                span nil nil)))
        (:splice
         (let ((value
                 (nth-value 0
                   (%eval-command-value-operand
                    context form reader-result lexical-environment))))
           (unless (%proper-list-p value)
             (error
              (make-condition
               (quote sexp-evaluation-syntax-error)
               :source-span span
               :source-path
               (nshell.domain.parsing:reader-result-source-path
                reader-result)
               :cause
               (make-condition
                (quote simple-error)
                :format-control
                "A command splice value must be a proper list."
                :format-arguments nil))))
           (mapcar (lambda (item)
                     (nshell.domain.parsing:make-evaluated-command-arg
                      item span nil nil))
                   value)))))))

(defun %evaluate-command-argument
    (context argument reader-result lexical-environment)
  (if (nshell.domain.parsing:command-arg-p argument)
      (list (nshell.domain.parsing:make-evaluated-command-arg
             (nshell.domain.parsing:command-arg-value argument)
             (nshell.domain.parsing:command-arg-source-span argument)
             (nshell.domain.parsing:command-arg-glob-p argument)
             (nshell.domain.parsing:command-arg-expand-p argument)))
      (%evaluate-command-value-form
       context argument reader-result lexical-environment)))

(defun %evaluate-command-arguments
    (context command-node reader-result lexical-environment)
  (loop for argument in
        (nshell.domain.parsing:command-node-argument-forms command-node)
        append (%evaluate-command-argument
                context argument reader-result lexical-environment)))

(defun %evaluate-redirect-target-values
    (command-node reader-result lexical-environment)
  (declare (ignore reader-result lexical-environment))
  (loop for redirect in
        (nshell.domain.parsing:command-node-redirects command-node)
        for target = (nshell.domain.parsing:ast-redirect-entry-target redirect)
        when (nshell.domain.parsing:command-arg-p target)
          collect
          (cons
           (nshell.domain.parsing:ast-redirect-entry-source-order redirect)
           (nshell.domain.parsing:make-evaluated-command-arg
            (nshell.domain.parsing:command-arg-value target)
            (nshell.domain.parsing:command-arg-source-span target)
            nil nil))))

(defun %command-node-head-source (command-node)
  (let ((origin (and *generated-command-head-origin-map*
                     (gethash command-node
                              *generated-command-head-origin-map*))))
    (or (and origin
             (let ((name (%origin-field origin :source-name)))
               (if (%origin-field origin :escaped-p)
                   (format nil "|~a|" name)
                   name)))
        (and *command-stage-reader-result*
           (%source-head-token
            (nshell.domain.parsing:reader-result-source
             *command-stage-reader-result*)
            (nshell.domain.parsing:ast-node-span command-node)))
        (nshell.domain.parsing:command-node-command command-node))))

(defun %resolve-command-stage-binding (context command-node)
  (let* ((name (nshell.domain.parsing:command-node-command command-node))
         (head-source (%command-node-head-source command-node)))
    (multiple-value-bind (ignored-name escaped-p ignored-package forced-p)
        (%parse-head-source head-source)
      (declare (ignore ignored-name ignored-package))
      (if (or forced-p
              (nshell.domain.parsing:command-node-force-external-p
               command-node))
          (values :external nil)
          (multiple-value-bind (shell-binding shell-found-p)
              (lookup-shell-function
               (context-shell-function-registry context)
               name :scope (active-shell-function-scope)
               :escaped-p escaped-p)
            (if shell-found-p
                (values :shell-function shell-binding)
                (multiple-value-bind (builtin-binding builtin-found-p)
                    (lookup-builtin-binding name)
                  (cond
                    (builtin-found-p (values :builtin builtin-binding))
                    ((%command-path-candidate-p context name)
                     (values :external nil))
                    (t (values :external nil))))))))))

(defun evaluate-command-stage-in-context (context command-node)
  (multiple-value-bind (dispatch-kind binding)
      (%resolve-command-stage-binding context command-node)
    (when (and (eq dispatch-kind :builtin)
               (eq :value (builtin-binding-argument-mode binding))
               (not (eq *command-stage-call-position* :value)))
      (error 'command-execution-plan-error
             :source-span (nshell.domain.parsing:ast-node-span command-node)
             :operation :value-builtin-position
             :cause
             (make-condition 'simple-error
                             :format-control
                             "A :value builtin requires value position."
                             :format-arguments nil)))
    (make-evaluated-command-stage
     command-node dispatch-kind binding
     (%evaluate-command-arguments
      context command-node *command-stage-reader-result*
      *command-stage-lexical-environment*)
     (%evaluate-redirect-target-values
      command-node *command-stage-reader-result*
      *command-stage-lexical-environment*))))

(defun %eval-command-ast-in-position
    (context ast reader-result lexical-environment position)
  (let* ((*command-test-position-p* (eq position :test))
         (*command-stage-reader-result* reader-result)
         (*command-stage-lexical-environment* lexical-environment)
         (*command-evaluation-position* position)
         (*command-stage-call-position*
           (if (and (nshell.domain.parsing:command-node-p ast)
                    (eq position :value))
               :value
               :stream))
         (*current-user-evaluator-context* context)
         (*current-user-evaluator-position* position))
    (handler-case
        (multiple-value-bind (value status pipeline-result)
            (call-with-command-failure-policy
             ast
             (lambda ()
               (execute-reader-ast-in-context
                context ast
                (lambda (stage-context command-node)
                  (evaluate-command-stage-in-context
                   stage-context command-node)))))
          (declare (ignore pipeline-result))
          (setf *current-evaluation-status* status)
          (values (if (eq position :test) (zerop status) value)))
      (command-failed (condition)
        (setf *current-evaluation-status*
              (command-failed-status condition))
        (error condition)))))

(defun %eval-body (context forms reader-result lexical-environment position)
  (cond
    ((null forms) nil)
    ((null (cdr forms))
     (%eval-form context (car forms) reader-result lexical-environment position))
    (t
     (%eval-form context (car forms) reader-result lexical-environment :stream)
     (%eval-body context (cdr forms) reader-result lexical-environment position))))

(defun %special-form-syntax-error (operator)
  (error "Malformed evaluator form ~S" operator))

(defun %check-special-form-arity (operator form minimum &optional maximum)
  (let ((count (length (cdr form))))
    (unless (and (<= minimum count)
                 (or (null maximum) (<= count maximum)))
      (%special-form-syntax-error operator))))

(defun %parse-let-binding (operator binding)
  (cond
    ((symbolp binding) (values binding nil nil))
    ((and (consp binding) (symbolp (first binding))
          (<= (length binding) 2))
     (values (first binding) (second binding) (consp (rest binding))))
    (t (%special-form-syntax-error operator))))

(defun %eval-let-form
    (context form reader-result lexical-environment position sequential-p)
  (%check-special-form-arity (if sequential-p 'cl:let* 'cl:let) form 1)
  (let ((binding-forms (second form))
        (body (cddr form))
        (environment lexical-environment)
        (bindings nil))
    (unless (%proper-list-p binding-forms)
      (%special-form-syntax-error (if sequential-p 'cl:let* 'cl:let)))
    (dolist (binding binding-forms)
      (multiple-value-bind (name initializer initializer-p)
          (%parse-let-binding (if sequential-p 'cl:let* 'cl:let) binding)
        (let* ((value (if initializer-p
                          (%eval-form context initializer reader-result
                                      environment :value)
                          nil))
               (entry (cons (%resolve-reader-symbol reader-result name) value)))
          (push entry bindings)
          (when sequential-p
            (setf environment
                  (%extend-lexical-environment environment (list entry)))))))
    (%eval-body
     context body reader-result
     (if sequential-p environment
         (%extend-lexical-environment lexical-environment (nreverse bindings)))
     position)))

(defun %eval-cond-form
    (context clauses reader-result lexical-environment position)
  (dolist (clause clauses nil)
    (unless (and (%proper-list-p clause) clause)
      (%special-form-syntax-error 'cl:cond))
    (let ((test (%eval-form context (first clause) reader-result
                            lexical-environment :test)))
      (when test
        (if (rest clause)
            (return-from %eval-cond-form
              (%eval-body context (rest clause) reader-result
                          lexical-environment position))
            (return-from %eval-cond-form test))))))

(defun %case-keys-match-p (selector keys)
  (if (consp keys)
      (member selector keys :test #'eql)
      (eql selector keys)))

(defun %eval-case-form
    (context selector-form clauses reader-result lexical-environment position)
  (let ((selector (%eval-form context selector-form reader-result
                              lexical-environment :value)))
    (dolist (clause clauses nil)
      (unless (and (%proper-list-p clause) clause)
        (%special-form-syntax-error 'cl:case))
      (let* ((keys (%materialize-reader-form (first clause) reader-result))
             (default-p (or (eq keys t)
                            (eq keys 'otherwise)
                            (and (consp keys)
                                 (member 'otherwise keys :test #'eq)))))
        (when (or default-p (%case-keys-match-p selector keys))
          (return-from %eval-case-form
            (%eval-body context (rest clause) reader-result
                        lexical-environment position)))))))

(defun %handler-clause-bindings
    (lambda-list values reader-result &optional allow-empty-p)
  (let ((variables (%materialize-reader-form lambda-list reader-result)))
    (unless (and (%proper-list-p variables)
                 (every (lambda (variable)
                          (and (symbolp variable)
                               (not (keywordp variable))
                               (not (member variable '(nil t) :test #'eq))
                               (not (member variable lambda-list-keywords
                                            :test #'eq))))
                        variables)
                 (or (and allow-empty-p (null variables))
                     (= (length variables) (length values))))
      (%special-form-syntax-error 'cl:handler-case))
    (loop for variable in variables
          for value in values
          collect (cons variable value))))

(defun %find-handler-case-clause (condition clauses reader-result)
  (loop for clause in clauses
        for type-specifier = (%materialize-reader-form
                              (first clause) reader-result)
        when (and (not (eq type-specifier :no-error))
                  (typep condition type-specifier))
          return clause))

(defun %eval-handler-case-form
    (context form reader-result lexical-environment position)
  (%check-special-form-arity 'cl:handler-case form 1)
  (let* ((protected-form (second form))
         (clauses (cddr form))
         (tag (gensym "HANDLER-CASE-"))
         (outcome
           (catch tag
             (handler-bind
                 ((condition
                    (lambda (condition)
                      (let ((clause
                              (%find-handler-case-clause
                               condition clauses reader-result)))
                        (when clause
                          (throw tag (list :handler clause condition)))))))
               (cons :values
                     (multiple-value-list
                      (%eval-form context protected-form reader-result
                                  lexical-environment position)))))))
    (if (eq (first outcome) :values)
        (let* ((values (rest outcome))
               (no-error-clause (find :no-error clauses :key #'first)))
          (if no-error-clause
              (%eval-body
               context (cddr no-error-clause) reader-result
               (%extend-lexical-environment
                lexical-environment
                (%handler-clause-bindings (second no-error-clause)
                                          values reader-result))
               position)
              (values-list values)))
        (let ((clause (second outcome))
              (condition (third outcome)))
          (%eval-body
           context (cddr clause) reader-result
           (%extend-lexical-environment
            lexical-environment
            (%handler-clause-bindings (second clause) (list condition) reader-result t))
           position)))))

(defun %eval-and-form (context operands reader-result lexical-environment)
  (let ((last-value t))
    (dolist (operand operands last-value)
      (setf last-value
            (%eval-form context operand reader-result lexical-environment :test))
      (unless last-value (return last-value)))))

(defun %eval-or-form (context operands reader-result lexical-environment)
  (dolist (operand operands nil)
    (let ((value (%eval-form context operand reader-result
                             lexical-environment :test)))
      (when value (return value)))))

(defun %eval-special-form
    (context form reader-result lexical-environment position)
  (let ((operator (%resolve-form-operator context form reader-result)))
    (case operator
      (cl:if
       (%check-special-form-arity 'cl:if form 2 3)
       (if (%eval-form context (second form) reader-result
                       lexical-environment :test)
           (%eval-form context (third form) reader-result
                       lexical-environment position)
           (if (cdddr form)
               (%eval-form context (fourth form) reader-result
                           lexical-environment position)
               nil)))
      (cl:when
       (%check-special-form-arity 'cl:when form 1)
       (when (%eval-form context (second form) reader-result
                         lexical-environment :test)
         (%eval-body context (cddr form) reader-result
                     lexical-environment position)))
      (cl:unless
       (%check-special-form-arity 'cl:unless form 1)
       (unless (%eval-form context (second form) reader-result
                           lexical-environment :test)
         (%eval-body context (cddr form) reader-result
                     lexical-environment position)))
      (cl:and (%eval-and-form context (rest form) reader-result
                              lexical-environment))
      (cl:or (%eval-or-form context (rest form) reader-result
                            lexical-environment))
      (cl:not
       (%check-special-form-arity 'cl:not form 1 1)
       (not (%eval-form context (second form) reader-result
                        lexical-environment :test)))
      (cl:let
       (%eval-let-form context form reader-result lexical-environment
                       position nil))
      (cl:let*
       (%eval-let-form context form reader-result lexical-environment
                       position t))
      (cl:progn
       (%eval-body context (rest form) reader-result lexical-environment
                   position))
      (cl:cond
       (%eval-cond-form context (rest form) reader-result
                        lexical-environment position))
      (cl:case
       (%check-special-form-arity 'cl:case form 1)
       (%eval-case-form context (second form) (cddr form) reader-result
                        lexical-environment position))
      (cl:handler-case
       (%eval-handler-case-form context form reader-result
                               lexical-environment position))
      (cl:setq (%eval-setq-form context form reader-result lexical-environment))
      (otherwise (%special-form-syntax-error operator)))))

(defun %set-lexical-value (environment symbol value)
  (loop for frame = environment then (%sexp-lexical-environment-parent frame)
        while frame
        do (multiple-value-bind (old found-p)
               (gethash symbol (%sexp-lexical-environment-table frame))
             (declare (ignore old))
             (when found-p
               (setf (gethash symbol (%sexp-lexical-environment-table frame))
                     value)
               (return-from %set-lexical-value value)))
        finally (setf (symbol-value symbol) value))
  value)

(defun %eval-setq-form (context form reader-result lexical-environment)
  (unless (and (evenp (length (rest form)))
               (every #'symbolp (loop for (name value) on (rest form) by #'cddr
                                      collect name)))
    (%special-form-syntax-error 'cl:setq))
  (let ((value nil))
    (loop for (name expression) on (rest form) by #'cddr
          for symbol = (%resolve-reader-symbol reader-result name)
          do (setf value
                   (%eval-form context expression
                               reader-result lexical-environment :value))
             (%set-lexical-value lexical-environment symbol value))
    value))

(defun %eval-dotimes-form
    (context form reader-result lexical-environment position)
  (declare (ignore position))
  (%check-special-form-arity 'cl:dotimes form 1)
  (let* ((spec (%materialize-reader-form (second form) reader-result))
         (body (cddr form)))
    (unless (and (%proper-list-p spec) (<= 2 (length spec) 3)
                 (symbolp (first spec)))
      (%special-form-syntax-error 'cl:dotimes))
    (let* ((variable (first spec))
           (count (%eval-form context (second spec) reader-result
                              lexical-environment :value)))
      (unless (and (integerp count) (not (minusp count)))
        (error 'type-error :datum count :expected-type '(integer 0 *)))
      (let ((environment
              (%extend-lexical-environment
               lexical-environment (list (cons variable 0)))))
        (loop while (and (consp (first body))
                         (eq (%resolve-reader-symbol
                              reader-result (first (first body)))
                             'cl:declare))
              do (pop body))
        (dotimes (index count)
          (setf (gethash variable
                         (%sexp-lexical-environment-table environment))
                index)
          (%eval-body context body reader-result environment :stream))
        (setf (gethash variable
                       (%sexp-lexical-environment-table environment))
              count)
        (if (cddr spec)
            (%eval-form context (third spec) reader-result environment :value)
            nil)))))

(defun %function-lambda-list-variables (lambda-list)
  (let ((mode :required)
        (variables nil))
    (dolist (item lambda-list (nreverse variables))
      (if (member item lambda-list-keywords)
          (setf mode item)
          (let ((variable
                  (cond
                    ((member mode '(:required &rest &body &whole &environment &aux)
                             :test #'eq)
                     (if (symbolp item) item (first item)))
                    ((eq mode '&optional)
                     (if (symbolp item) item (first item)))
                    ((eq mode '&key)
                     (if (symbolp item)
                         item
                         (let ((spec (first item)))
                           (if (consp spec) (second spec) spec))))
                    (t nil))))
            (when (and variable (symbolp variable)
                       (not (keywordp variable)))
              (push variable variables)))))))

(defun %ordinary-function-body-parts (body &optional reader-result)
  (let* ((body (copy-list body))
         (documentation (and (stringp (first body)) (pop body)))
         (declarations nil))
    (loop while (and (consp (first body))
                     (eq (%resolve-reader-symbol
                          reader-result (first (first body)))
                         'cl:declare))
          do (push (pop body) declarations))
    (values documentation (nreverse declarations) body)))

(defun %make-evaluator-function (lambda-list body reader-result)
  (let* ((lambda-list (%materialize-reader-form lambda-list reader-result))
         (variables (%function-lambda-list-variables lambda-list)))
    (multiple-value-bind (documentation declarations executable-body)
        (%ordinary-function-body-parts body reader-result)
      (eval
       `(lambda ,lambda-list
          ,@(when documentation (list documentation))
          ,@(mapcar (lambda (declaration)
                      (%materialize-reader-form declaration reader-result))
                    declarations)
          (%eval-user-function-body
           ',executable-body ',reader-result
           (list ,@(mapcar (lambda (variable)
                             `(cons ',variable ,variable))
                           variables))))))))

(defun %eval-user-function-body (body reader-result bindings)
  (let* ((context *current-user-evaluator-context*)
         (position (if (eq *current-user-evaluator-position* :test)
                       :value
                       *current-user-evaluator-position*))
         (*interactive-top-level-p* nil)
         (*command-test-position-p* nil))
    (%eval-body context body reader-result
                (%extend-lexical-environment nil bindings)
                position)))

(defun %resolve-user-function-name (reader-result name)
  (multiple-value-bind (source-name ignored-escaped-p package-qualifier)
      (%reader-symbol-origin-info reader-result name)
    (declare (ignore ignored-escaped-p))
    (when package-qualifier
      (error "A user function name must be unqualified: ~S" name))
    (%find-user-symbol (or source-name (symbol-name name)))))

(defun %eval-defun-form (form reader-result)
  (destructuring-bind (operator name lambda-list &rest body) form
    (declare (ignore operator))
    (let* ((function-name (%resolve-user-function-name reader-result name))
           (function (%make-evaluator-function lambda-list body reader-result)))
      (setf (symbol-function function-name) function)
      (multiple-value-bind (documentation declarations executable-body)
          (%ordinary-function-body-parts
           body reader-result)
        (declare (ignore declarations executable-body))
        (setf (documentation function-name 'function) documentation))
      function-name)))

(defun %eval-defmacro-form (form reader-result)
  (let ((*package* (find-package "NSHELL.USER")))
    (eval (%materialize-reader-form form reader-result))))

(defun %call-with-command-macro-origin (reader-result call-span thunk)
  (handler-case
      (funcall thunk)
    (command-macro-syntax-error (condition)
      (error 'command-macro-syntax-error
             :source-span
             (or (command-macro-syntax-error-source-span condition) call-span)
             :source-path
             (or (command-macro-syntax-error-source-path condition)
                 (nshell.domain.parsing:reader-result-source-path
                  reader-result))
             :cause (command-macro-syntax-error-cause condition)))))

(defun %call-with-macro-expansion-depth (form reader-result thunk)
  (when (>= *macro-expansion-depth* *macro-expansion-depth-limit*)
    (error 'command-macro-syntax-error
           :source-span (%source-form-span form reader-result)
           :source-path
           (nshell.domain.parsing:reader-result-source-path reader-result)
           :cause
           (make-condition 'simple-error
                           :format-control "Macro expansion exceeded its nesting limit."
                           :format-arguments nil)))
  (let ((*macro-expansion-depth* (1+ *macro-expansion-depth*)))
    (funcall thunk)))

(defun %eval-user-macro-call
    (context form reader-result lexical-environment position)
  (let* ((call-span (%source-form-span form reader-result))
         (host-form (%materialize-reader-form form reader-result)))
    (setf (first host-form) (%resolve-form-operator context form reader-result))
    (%copy-form-origins form host-form reader-result)
    (%call-with-command-macro-origin
     reader-result call-span
     (lambda ()
       (%call-with-macro-expansion-depth
        form reader-result
        (lambda ()
          (let ((*package* (find-package "NSHELL.USER")))
            (multiple-value-bind (expansion expanded-p)
                (macroexpand-1 host-form nil)
              (if expanded-p
                  (progn
                    (%propagate-expansion-origin expansion call-span)
                    (%eval-form context expansion reader-result
                                lexical-environment position))
                  (%eval-host-form context host-form reader-result
                                   lexical-environment position))))))))))

(defun %macro-generated-argument (form span)
  (cond
    ((stringp form)
     (nshell.domain.parsing:make-command-arg form :double nil nil span nil nil))
    ((symbolp form)
     (nshell.domain.parsing:make-command-arg
      (if (keywordp form) (symbol-name form) (symbol-name form))
      nil nil nil span nil nil))
    ((numberp form)
     (nshell.domain.parsing:make-command-arg
      (princ-to-string form) nil nil nil span nil nil))
    ((characterp form)
     (nshell.domain.parsing:make-command-arg
      (string form) nil nil nil span nil nil))
    (t
     (nshell.domain.parsing:make-command-value-form :value form span))))

(defun %macro-generated-form->ast (context form reader-result span)
  (let ((head (first form)))
    (if (and (symbolp head)
             (member (symbol-name head) '("|" "|&") :test #'string=))
        (let* ((commands
                 (mapcar (lambda (stage)
                           (%macro-generated-form->ast
                            context stage reader-result
                            (%source-form-span stage reader-result)))
                         (rest form)))
               (edges
                 (loop repeat (max 0 (1- (length commands)))
                       collect
                       (nshell.domain.parsing:make-pipeline-edge
                        (if (string= (symbol-name head) "|&")
                            :pipe-stderr-to-stdout
                            :pipe)
                        span))))
          (nshell.domain.parsing:make-pipeline-node commands span edges))
        (let* ((command-name (symbol-name head))
               (argument-forms
                 (mapcar (lambda (argument)
                           (%macro-generated-argument
                            argument (%source-form-span argument reader-result)))
                         (rest form)))
               (arguments
                 (remove-if-not
                  #'nshell.domain.parsing:command-arg-p argument-forms))
               (node
                 (nshell.domain.parsing:make-command-node
                  command-name arguments span nil nil nil nil argument-forms))
               (origin (and *macro-expansion-symbol-origin-map*
                            (gethash head
                                     *macro-expansion-symbol-origin-map*))))
          (when (and origin *generated-command-head-origin-map*)
            (setf (gethash node *generated-command-head-origin-map*) origin))
          node))))

(defun %eval-macro-generated-command
    (context form reader-result lexical-environment position)
  (%eval-command-ast-in-position
   context (%macro-generated-form->ast
            context form reader-result (%source-form-span form reader-result))
   reader-result lexical-environment position))

(defun %eval-symbol (context form reader-result lexical-environment)
  (let ((symbol (%resolve-reader-symbol reader-result form)))
    (multiple-value-bind (value found-p)
        (%lexical-value lexical-environment symbol)
      (cond
        (found-p value)
        ((keywordp symbol) symbol)
        ((eq symbol t) t)
        ((null symbol) nil)
        ((boundp symbol) (symbol-value symbol))
        (t (let ((name (nth-value 0
                                  (%reader-symbol-origin-info
                                   reader-result form)))
                 (package-qualifier
                   (nth-value 2 (%reader-symbol-origin-info
                                 reader-result form))))
             (when (and (null name)
                        (symbol-package symbol)
                        (string= (package-name (symbol-package symbol))
                                 "NSHELL.USER"))
               (setf name (symbol-name symbol)))
             (if (or package-qualifier (null name)
                     (and (null (%reader-symbol-origin reader-result form))
                          (symbol-package symbol)
                          (not (string= (package-name (symbol-package symbol))
                                        "NSHELL.USER"))))
                 (error 'unbound-variable :name symbol)
                 (or (and (shell-context-environment context)
                          (nshell.domain.environment:env-get
                           (shell-context-environment context) name))
                     ""))))))))

(defun %eval-host-form
    (context form reader-result lexical-environment position)
  (let* ((operator (%resolve-form-operator context form reader-result))
         (form (%materialize-reader-form form reader-result)))
    (setf (first form) operator)
    (cond
      ((and (symbolp operator) (special-operator-p operator))
       (let ((bindings nil))
         (loop for frame = lexical-environment then
                   (%sexp-lexical-environment-parent frame)
               while frame
               do (maphash (lambda (symbol value)
                             (unless (assoc symbol bindings :test #'eq)
                               (push (cons symbol value) bindings)))
                           (%sexp-lexical-environment-table frame)))
         (eval `(let ,(mapcar (lambda (binding)
                                (list (car binding) (cdr binding)))
                              bindings)
                  ,form))))
      ((and (symbolp operator) (macro-function operator))
       (%call-with-macro-expansion-depth
        form reader-result
        (lambda ()
          (multiple-value-bind (expansion expanded-p)
              (macroexpand-1 form nil)
            (if expanded-p
                (progn
                  (%propagate-expansion-origin
                   expansion (%source-form-span form reader-result))
                  (%eval-form context expansion reader-result
                              lexical-environment position))
                (%eval-host-function-call context form reader-result
                                          lexical-environment position))))))
      (t
       (%eval-host-function-call context form reader-result
                                 lexical-environment position)))))

(defun %eval-host-function-call
    (context form reader-result lexical-environment position)
  (let* ((operator (%resolve-form-operator context form reader-result))
         (function
           (if (symbolp operator)
               (fdefinition operator)
               (%eval-form context operator reader-result lexical-environment
                           :value)))
         (arguments
           (mapcar (lambda (argument)
                     (%eval-form context argument reader-result
                                 lexical-environment :value))
                   (rest form))))
    (unless (functionp function)
      (error 'undefined-function :name operator))
    (let ((*current-user-evaluator-context* context)
          (*current-user-evaluator-position* position))
      (apply function arguments))))

(defun %eval-form
    (context form reader-result lexical-environment position
     &optional (supplied-classification nil classification-supplied-p))
  (let* ((raw-operator (and (consp form) (first form)))
         (operator (and (consp form) (symbolp raw-operator)
                        (%resolve-form-operator context form reader-result)))
         (classification
           (if classification-supplied-p
               supplied-classification
               (and (consp form) (symbolp raw-operator)
                    (%form-command-classification
                     context form reader-result)))))
    (unless (or (nshell.domain.parsing::ast-node-p form)
                (%reader-pipeline-form-p form reader-result)
                (eq classification :command-island))
      (%reject-opaque-dispatch-markers form reader-result))
    (cond
      ((nshell.domain.parsing::ast-node-p form)
       (%eval-command-ast-in-position
        context form reader-result lexical-environment position))
      ((symbolp form)
       (%eval-symbol context form reader-result lexical-environment))
      ((atom form) form)
      ((not (%proper-list-p form))
       (error "Cannot evaluate an improper form: ~S" form))
      ((eq operator 'cl:quote)
       (%check-special-form-arity 'cl:quote form 1 1)
       (%materialize-reader-form (second form) reader-result))
      ((eq operator 'cl:function)
       (%check-special-form-arity 'cl:function form 1 1)
       (let ((name (%materialize-reader-form (second form) reader-result)))
         (cond
           ((symbolp name) (fdefinition name))
           ((and (consp name) (eq (first name) 'cl:lambda))
            (%make-evaluator-function (second name) (cddr name) reader-result))
           (t name))))
      ((member operator
               '(cl:if cl:when cl:unless cl:and cl:or cl:not cl:let cl:let*
                 cl:progn cl:cond cl:case cl:handler-case cl:setq)
               :test #'eq)
       (%eval-special-form context form reader-result lexical-environment
                           position))
      ((eq operator 'cl:defun)
       (%eval-defun-form form reader-result))
      ((eq operator 'cl:defmacro)
       (%eval-defmacro-form form reader-result))
      ((and (symbolp raw-operator)
            (let ((origin (%reader-symbol-origin reader-result raw-operator)))
              (if origin
                  (and (not (%origin-field origin :escaped-p))
                       (null (%origin-field origin :package-qualifier :package))
                       (string-equal
                        (%origin-field origin :source-name)
                        "DEFINE-SHELL-FUNCTION"))
                  (and (eq (symbol-package raw-operator)
                           (find-package "NSHELL.USER"))
                       (string-equal (symbol-name raw-operator)
                                     "DEFINE-SHELL-FUNCTION")))))
       (%eval-define-shell-function-form
        context form reader-result lexical-environment))
      ((and (eq classification :host-form)
            (eq operator 'cl:dotimes))
       (%eval-dotimes-form context form reader-result lexical-environment
                           position))
      ((and (eq classification :host-form)
            (symbolp operator)
            (macro-function operator))
       (%eval-user-macro-call context form reader-result lexical-environment
                              position))
      ((%reader-pipeline-form-p form reader-result)
       (%eval-command-ast-in-position
        context
        (if (%source-backed-form-p form reader-result)
            (%command-form->ast context form reader-result)
            (%macro-generated-form->ast
             context form reader-result (%source-form-span form reader-result)))
        reader-result lexical-environment position))
      ((eq classification :command-island)
       (if (%source-backed-form-p form reader-result)
           (%eval-command-ast-in-position
            context (%command-form->ast context form reader-result)
            reader-result lexical-environment position)
           (%eval-macro-generated-command
            context form reader-result lexical-environment position)))
      (t
       (%eval-host-form context form reader-result lexical-environment
                        position)))))

(defun %eval-define-shell-function-form
    (context form reader-result lexical-environment)
  (declare (ignore lexical-environment))
  (destructuring-bind (operator name lambda-list &rest body) form
    (declare (ignore operator))
    (multiple-value-bind (source-name escaped-p package-qualifier)
        (%reader-symbol-origin-info reader-result name)
      (when package-qualifier
        (error 'command-macro-syntax-error
               :source-span (%source-form-span form reader-result)
               :source-path
               (nshell.domain.parsing:reader-result-source-path reader-result)
               :cause (make-condition 'simple-error
                                      :format-control
                                      "A shell-function name must be unqualified."
                                      :format-arguments nil)))
      (let* ((function-name (or source-name (symbol-name name)))
             (materialized-lambda-list
               (%materialize-reader-form lambda-list reader-result))
             (evaluator-function
               (%make-evaluator-function lambda-list body reader-result))
             (callable
               (lambda (call-context evaluated-command-args call-position)
                 (let ((*current-user-evaluator-context* call-context)
                       (*current-user-evaluator-position* call-position)
                       (*interactive-top-level-p* nil)
                       (*command-test-position-p* nil))
                   (apply evaluator-function
                          (mapcar
                           #'nshell.domain.parsing:evaluated-command-arg-value
                           evaluated-command-args)))))
             (binding
               (make-shell-function-binding
                callable materialized-lambda-list function-name
                (nshell.domain.parsing:reader-result-source-path reader-result)
                (%source-form-span form reader-result))))
        (register-shell-function
         (context-shell-function-registry context) function-name binding
         :escaped-p escaped-p)
         function-name))))

(defun %with-reader-evaluation-state (reader-result thunk)
  (let ((*macro-expansion-origin-map* (%make-reader-origin-overlay reader-result))
        (*macro-expansion-symbol-origin-map* (make-hash-table :test #'eq))
        (*generated-command-head-origin-map* (make-hash-table :test #'eq))
        (*macro-expansion-depth* 0))
    (funcall thunk)))

(defun evaluate-reader-result-in-context (context reader-result)
  (let ((*current-evaluation-status*
          (shell-context-last-exit-code context)))
    (%with-reader-evaluation-state
     reader-result
     (lambda ()
       (let* ((form (nshell.domain.parsing:reader-result-form reader-result))
              (classification
                (and (consp form) (symbolp (first form))
                     (%form-command-classification
                      context form reader-result)))
              (stream-form-p
                (or (nshell.domain.parsing::ast-node-p form)
                    (%reader-pipeline-form-p form reader-result)
                    (eq classification :command-island)))
              (position (if stream-form-p :stream :value))
              (value
                (%eval-form context form reader-result nil position
                            classification)))
         (values value *current-evaluation-status*))))))
