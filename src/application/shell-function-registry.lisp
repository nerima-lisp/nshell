(in-package #:nshell.application)

(defvar *active-shell-function-scope*
  nil)

(defvar *current-user-evaluator-context*
  nil)

(defvar *current-user-evaluator-position*
  :value)

(defun active-shell-function-scope ()
  *active-shell-function-scope*)

(defun context-shell-function-registry (context)
  (shell-context-shell-function-registry context))

(defun %shell-function-name-text (name)
  (etypecase name
    (string name)
    (symbol (symbol-name name))))

(defun %shell-function-canonical-key (name escaped-p)
  (let ((name-text (%shell-function-name-text name)))
    (if escaped-p
        (list :escaped name-text)
        (string-upcase name-text))))

(defun %shell-function-equal-hash-table-p (table)
  (and (hash-table-p table)
       (let ((test (hash-table-test table)))
         (or (eq test 'equal) (eq test #'equal)))))

(defun %check-shell-function-registry (registry)
  (check-type registry shell-function-registry)
  (unless
      (%shell-function-equal-hash-table-p
       (shell-function-registry-global-table registry))
    (error 'type-error
           :datum
           (shell-function-registry-global-table registry)
           :expected-type
           '(satisfies %shell-function-equal-hash-table-p)))
  registry)

(defun %check-shell-function-scope (scope)
  (when scope
    (check-type scope shell-function-scope)
    (unless
        (%shell-function-equal-hash-table-p (shell-function-scope-table scope))
      (error 'type-error
             :datum
             (shell-function-scope-table scope)
             :expected-type
             '(satisfies %shell-function-equal-hash-table-p))))
  scope)

(defun %find-shell-function (registry canonical-key scope)
  (block found
    (loop for current-scope = scope then (shell-function-scope-parent
                                          current-scope)
          while current-scope
          do (multiple-value-bind (binding present-p)
                 (gethash canonical-key
                          (shell-function-scope-table current-scope))
               (when present-p
                 (return-from found
                   (values binding t)))))
    (gethash canonical-key (shell-function-registry-global-table registry))))

(defun register-shell-function (registry name binding &key escaped-p)
  (%check-shell-function-registry registry)
  (check-type name (or string symbol))
  (check-type binding shell-function-binding)
  (check-type escaped-p boolean)
  (setf (gethash (%shell-function-canonical-key name escaped-p)
                 (shell-function-registry-global-table registry)) binding))

(defun peek-shell-function (registry name &key scope escaped-p)
  (%check-shell-function-registry registry)
  (check-type name (or string symbol))
  (check-type escaped-p boolean)
  (%check-shell-function-scope scope)
  (%find-shell-function registry
                        (%shell-function-canonical-key name escaped-p)
                        scope))

(defun lookup-shell-function (registry name &key scope escaped-p)
  (%check-shell-function-registry registry)
  (check-type name (or string symbol))
  (check-type escaped-p boolean)
  (%check-shell-function-scope scope)
  (let* ((canonical-key (%shell-function-canonical-key name escaped-p))
         (hook (shell-function-registry-lookup-miss-hook registry)))
    (multiple-value-bind (binding found-p)
        (%find-shell-function registry canonical-key scope)
      (when found-p
        (return-from lookup-shell-function
          (values binding t))))
    (when hook
      (funcall hook registry canonical-key))
    (%find-shell-function registry canonical-key scope)))

(defmacro define-shell-function (name lambda-list &body body)
  "Define a shell function; string names preserve exact escaped spelling."
  (let* ((name-text (%shell-function-name-text name))
         (escaped-p (or (stringp name)
                        (and (symbolp name)
                             (not (string= name-text
                                           (string-upcase name-text))))))
         (source-path (or *compile-file-truename* *load-truename*)))
    `(register-shell-function
      (context-shell-function-registry *current-user-evaluator-context*)
      ,name-text
      (make-shell-function-binding
       (lambda (context evaluated-command-args call-position)
         (let ((*current-user-evaluator-context* context)
               (*current-user-evaluator-position* call-position))
           (apply
            (lambda ,lambda-list
              ,@body)
            (mapcar #'nshell.domain.parsing:evaluated-command-arg-value
                    evaluated-command-args))))
       ',lambda-list
       ,name-text
       ',source-path
       nil)
      :escaped-p
      ,escaped-p)))

(defmacro with-shell-functions (bindings &body body)
  "Bind shell functions in a child scope; string names preserve exact spelling."
  (let ((scope (gensym "SCOPE")))
    `(let* ((,scope
             (make-shell-function-scope (make-hash-table :test #'equal)
                                        (active-shell-function-scope))))
       ,@(loop for (name binding) in bindings
               for name-text = (%shell-function-name-text name)
               for escaped-p = (or (stringp name)
                                   (and (symbolp name)
                                        (not
                                         (string= name-text
                                                  (string-upcase name-text)))))
               collect `(setf (gethash
                               (%shell-function-canonical-key ',name ,escaped-p)
                               (shell-function-scope-table ,scope)) ,binding))
       (let ((*active-shell-function-scope* ,scope))
         ,@body))))
(defun %autoload-shell-function-from-directory (context canonical-key)
  (labels ((absolute-directory-p (value)
                                 (and (stringp value)
                                      (plusp (length value))
                                      (eq :absolute
                                          (first (pathname-directory (pathname value))))))
           (autoload-name (key)
                          (cond
                           ((stringp key)
                            (values key nil))
                           ((and (consp key)
                                 (eq (first key) :escaped)
                                 (stringp (second key))
                                 (null (cddr key)))
                            (values (second key) t))))
           (simple-function-name-p (name)
                                   (and (stringp name)
                                        (plusp (length name))
                                        (every (lambda (character)
                                                 (or (char<= #\A character #\Z)
                                                     (char<= #\a character #\z)
                                                     (char<= #\0 character #\9)
                                                     (find character "_-")))
                                               name)))
           (function-directory ()
                               (let* ((environment (shell-context-environment context))
                                      (xdg-config-home
                                       (and environment
                                            (nshell.domain.environment:env-get
                                             environment "XDG_CONFIG_HOME")))
                                      (home
                                       (and environment
                                            (nshell.domain.environment:env-get environment
                                                                               "HOME"))))
                                 (cond
                                  ((absolute-directory-p xdg-config-home)
                                   (merge-pathnames
                                    #P"nshell/functions/"
                                    (uiop:ensure-directory-pathname
                                     (pathname xdg-config-home))))
                                  ((absolute-directory-p home)
                                   (merge-pathnames
                                    #P".config/nshell/functions/"
                                    (uiop:ensure-directory-pathname (pathname home))))
                                  (t
                                   (merge-pathnames
                                    #P".config/nshell/functions/"
                                    (user-homedir-pathname))))))
           (requested-defun-form (reader-results name escaped-p)
                                 (some
                                  (lambda (reader-result)
                                    (let ((form
                                           (nshell.domain.parsing:reader-result-form reader-result)))
                                      (and (consp form)
                                           (symbolp (first form))
                                           (string-equal (symbol-name (first form)) "DEFUN")
                                           (symbolp (second form))
                                           (if escaped-p
                                               (string= name (symbol-name (second form)))
                                             (string= (string-upcase name)
                                                      (string-upcase (symbol-name (second form)))))
                                           form)))
                                  reader-results)))
    (multiple-value-bind (name escaped-p)
        (autoload-name canonical-key)
      (when (simple-function-name-p name)
        (let* ((file-name (if escaped-p name (string-downcase name)))
               (path
                (merge-pathnames
                 (make-pathname :name file-name :type "nsh")
                 (function-directory)))
               (registry (context-shell-function-registry context)))
          (when (probe-file path)
            (let* ((source (uiop:read-file-string path))
                   (scan-result
                    (funcall
                     (symbol-function '%source-reader-scan-result)
                     context source)))
              (unless (eq (nshell.domain.parsing:scan-result-status
                           scan-result)
                          :complete)
                (error "Function file ~a is incomplete." path))
              (let* ((reader-results
                      (nshell.domain.parsing:read-submission
                       source :reader-context :auto :source-path path))
                     (requested-defun
                      (requested-defun-form reader-results name escaped-p)))
                (dolist (reader-result reader-results)
                  (evaluate-reader-result-in-context context reader-result))
                (unless (nth-value 1
                                   (%find-shell-function registry canonical-key nil))
                  (when requested-defun
                    (multiple-value-bind (symbol status)
                        (find-symbol (symbol-name (second requested-defun)) "NSHELL.USER")
                      (when (and symbol
                                 (or (eq status :internal)
                                     (eq status :external))
                                 (fboundp symbol))
                        (let ((function (symbol-function symbol)))
                          (register-shell-function
                           registry name
                           (make-shell-function-binding
                            (lambda (call-context evaluated-command-args call-position)
                              (let ((*current-user-evaluator-context* call-context)
                                    (*current-user-evaluator-position* call-position))
                                (apply
                                 function
                                 (mapcar
                                  (function
                                   nshell.domain.parsing:evaluated-command-arg-value)
                                  evaluated-command-args))))
                            (third requested-defun) name path nil)
                           :escaped-p escaped-p))))))))))))))

