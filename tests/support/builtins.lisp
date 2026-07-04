(in-package #:nshell/test)


(defun make-test-builtins-context (&key
                                     external-runner
                                     external-capture-runner
                                     (path "/bin:/usr/bin")
                                     (files '("/bin/echo" "/tmp/file.txt"))
                                     (dirs '("/tmp"))
                                     function-table)
  (let ((file-table (make-hash-table :test #'equal))
        (dir-table (make-hash-table :test #'equal)))
    (dolist (file-path files)
      (setf (gethash file-path file-table) t))
    (dolist (dir-path dirs)
      (setf (gethash dir-path dir-table) t))
    (make-test-shell-context
     :environment (nshell.domain.environment:env-set
                   (nshell.domain.environment:make-default-environment)
                   "PATH" path t)
     :function-table (or function-table (make-hash-table :test #'equal))
     :filesystem-fns
     (list :list-dir (lambda (dir) (declare (ignore dir)) nil)
           :stat (lambda (path)
                   (or (gethash path file-table) (gethash path dir-table)))
           :file-exists-p (lambda (path) (gethash path file-table))
           :directory-exists-p (lambda (path) (gethash path dir-table))
           :cwd (lambda () #p"/tmp/")
           :chdir (lambda (path) (declare (ignore path)) t))
     :process-fns
     (let ((fns (list :run-external
                      (or external-runner
                          (lambda (command args)
                            (declare (ignore command args))
                            0)))))
       (if external-capture-runner
           (list* :run-external-capture external-capture-runner fns)
           fns))
     :redirect-fns
     (list :redirect-output #'nshell.infrastructure.acl:redirect-output
           :redirect-error #'nshell.infrastructure.acl:redirect-error
           :redirect-output-error #'nshell.infrastructure.acl:redirect-output-and-error
           :redirect-error-to-output #'nshell.infrastructure.acl:redirect-error-to-output
           :redirect-input #'nshell.infrastructure.acl:redirect-input
           :redirect-input-string #'nshell.infrastructure.acl:redirect-input-string
           :redirect-input-document #'nshell.infrastructure.acl:redirect-input-document
           :restore #'nshell.infrastructure.acl:restore-redirects)
     :terminal-fns nil)))

(defmacro with-builtins-context ((context) &body body)
  `(let ((,context (make-test-builtins-context)))
     ,@body))

(defmacro with-builtins-context-environment ((context context-form &rest bindings) &body body)
  (let ((env (gensym "ENV")))
    `(let ((,context ,context-form))
       (let ((,env (nshell.application:shell-context-environment ,context)))
         ,@(mapcar (lambda (binding)
                     (destructuring-bind (name value &optional (exported-p nil exported-p-supplied-p))
                         binding
                       (declare (ignore exported-p-supplied-p))
                       `(setf ,env
                              (nshell.domain.environment:env-set
                               ,env ,name ,value ,exported-p))))
                   bindings)
         (setf (nshell.application:shell-context-environment ,context) ,env))
       ,@body)))

(defun call-builtin (context name args)
  (funcall (nshell.application:lookup-builtin name) context args))

(defun call-string-builtin (context args)
  (call-builtin context "string" args))

(defun call-source-file (context path)
  (call-builtin context "source" (list (namestring path))))

(defmacro with-called-source ((output code context lines) &body body)
  (let ((source (gensym "SOURCE")))
    `(with-test-source-file (,source nil)
       (write-test-lines ,source ,lines)
       (multiple-value-bind (,output ,code)
           (call-source-file ,context ,source)
         ,@body))))

(defun %builtin-output-contains-all-p (output needles)
  (every (lambda (needle)
           (search needle output))
         needles))

(defun %builtin-call-assertions (actual-output actual-code &key code output output-null
                                                        output-empty contains)
  (append
   (when (not (null code))
     `((is (= ,code ,actual-code))))
   (when output
     `((is (string= ,output ,actual-output))))
   (when output-null
     `((is (null ,actual-output))))
   (when output-empty
     `((is (string= "" ,actual-output))))
   (when contains
     `((is (%builtin-output-contains-all-p ,actual-output ,contains))))
   `((values ,actual-output ,actual-code))))

(defmacro %with-builtin-call-values ((output code) call-form &body body)
  `(multiple-value-bind (,output ,code) ,call-form
     ,@body))

(defmacro assert-builtin-call ((context name args) &key code output output-null
                                           output-empty contains)
  (let ((actual-output (gensym "OUTPUT-"))
        (actual-code (gensym "CODE-")))
    `(%with-builtin-call-values (,actual-output ,actual-code)
         (call-builtin ,context ,name ,args)
       ,@(%builtin-call-assertions actual-output actual-code
                                   :code code
                                   :output output
                                   :output-null output-null
                                   :output-empty output-empty
                                   :contains contains))))

(defmacro assert-builtin-property ((context &key (trials '*pbt-default-trials*)) bindings &body body)
  `(let ((,context (make-test-builtins-context)))
     (check-property (:trials ,trials)
         ,bindings
       ,@body)))

(defmacro assert-string-builtin-property ((context &key (trials '*pbt-default-trials*)) bindings &body body)
  `(assert-builtin-property (,context :trials ,trials) ,bindings ,@body))

(defmacro with-builtins-source ((output code context lines) &body body)
  `(let ((,context (make-test-builtins-context)))
     (with-called-source (,output ,code ,context ,lines)
       ,@body)))

(defmacro with-builtins-source-ok ((output code context lines) expected-output &body extra-assertions)
  "Like WITH-BUILTINS-SOURCE but automatically asserts exit-code=0 and string output equality."
  `(with-builtins-source (,output ,code ,context ,lines)
     (is (= 0 ,code))
     (is (string= ,expected-output ,output))
     ,@extra-assertions))

(defmacro with-stubbed-command-executor ((&rest cases) &body body)
  "Stub %execute-command-by-name-in-context with a CASES dispatch table.
Each case is (command-string &body side-effects-and-return), where the last
form should return (values output exit-code).  Example:
  (with-stubbed-command-executor
      ((\"errcmd\" (write-line \"err\" *error-output*) (values \"out~%\" 7)))
    body)"
  (let ((ctx  (gensym "CTX-"))
        (cmd  (gensym "CMD-"))
        (args (gensym "ARGS-")))
    `(with-temporary-function
         ('nshell.application::%execute-command-by-name-in-context
          (lambda (,ctx ,cmd ,args)
            (declare (ignore ,ctx ,args))
            (cond ,@(mapcar (lambda (c)
                              (destructuring-bind (command-str &body c-body) c
                                `((string= ,cmd ,command-str) ,@c-body)))
                            cases))))
       ,@body)))

(defmacro with-builtins-source-tree ((context root source &key (prefix "nshell-test-source")) &body body)
  `(let ((,context (make-test-builtins-context)))
     (with-test-source-tree (,root ,source :prefix ,prefix)
       ,@body)))

(defmacro assert-builtin-cases ((context name) &body cases)
  "Assert a table of builtin calls for the same CONTEXT and NAME."
  (labels ((case-args-form (args)
             (if (and (consp args)
                      (symbolp (car args)))
                 args
                 `',args)))
  `(progn
     ,@(mapcar (lambda (case)
                 (destructuring-bind (args &rest options) case
                   (list* 'assert-builtin-call
                          (list context name (case-args-form args))
                          options)))
               cases))))

(defmacro assert-string-builtin-cases ((context) &body cases)
  `(assert-builtin-cases (,context "string") ,@cases))

(defmacro assert-fish-style-table-builtin-roundtrip
    ((context name table-form key expansion add-args list-fragment erase-error-output erase-args missing-key
      &key body-contains))
  `(progn
     (multiple-value-bind (output code)
         (call-builtin ,context ,name ,add-args)
       (is (null output))
       (is (= 0 code)))
     (is (equal ,expansion (gethash ,key ,table-form)))
     (is (= 0 (nth-value 1 (call-builtin ,context ,name (list "-q" ,key)))))
     (is (= 1 (nth-value 1 (call-builtin ,context ,name (list "-q" ,missing-key)))))
     ,@(when body-contains
         `((multiple-value-bind (output code)
               (call-builtin ,context ,name (list ,key))
             (is (= 0 code))
             ,@(mapcar (lambda (needle)
                         `(is (search ,needle output)))
                       body-contains))))
     (multiple-value-bind (output code)
         (call-builtin ,context ,name nil)
       (is (= 0 code))
       (is (search ,list-fragment output)))
     (assert-builtin-call (,context ,name '("-e"))
       :code 2
       :output ,erase-error-output)
     (is (= 0 (nth-value 1 (call-builtin ,context ,name ,erase-args))))
     (is (null (gethash ,key ,table-form)))))
