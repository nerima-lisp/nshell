(in-package #:nshell/test)

(defun %make-shell-function-registry-test-binding (value)
  (nshell.application:make-shell-function-binding
   (lambda (context evaluated-command-args call-position)
     (declare (ignore context evaluated-command-args call-position))
     value)
   nil (princ-to-string value) nil nil))

(describe "shell-function-registry"
  (it "canonicalizes unescaped names and isolates escaped names"
    (let* ((registry (nshell.application:make-shell-function-registry))
           (plain-binding (%make-shell-function-registry-test-binding :plain))
           (escaped-binding (%make-shell-function-registry-test-binding :escaped)))
      (nshell.application:register-shell-function registry "MyFn" plain-binding)
      (nshell.application:register-shell-function registry "MyFn" escaped-binding
                                                  :escaped-p t)
      (multiple-value-bind (binding found-p)
          (nshell.application:peek-shell-function registry "myfn")
        (expect plain-binding :to-be binding)
        (expect t :to-be found-p))
      (multiple-value-bind (binding found-p)
          (nshell.application:peek-shell-function registry "MyFn" :escaped-p t)
        (expect escaped-binding :to-be binding)
        (expect t :to-be found-p))))

  (it "searches lexical scopes from inner to outer and then global"
    (let* ((registry (nshell.application:make-shell-function-registry))
           (global-binding (%make-shell-function-registry-test-binding :global))
           (outer-binding (%make-shell-function-registry-test-binding :outer))
           (inner-binding (%make-shell-function-registry-test-binding :inner))
           (other-binding (%make-shell-function-registry-test-binding :other)))
      (nshell.application:register-shell-function registry "shared" global-binding)
      (nshell.application:register-shell-function registry "global-only" global-binding)
      (nshell.application:with-shell-functions ((shared outer-binding))
        (let ((outer-scope (nshell.application:active-shell-function-scope)))
          (multiple-value-bind (binding found-p)
              (nshell.application:peek-shell-function registry "shared"
                                                      :scope outer-scope)
            (expect outer-binding :to-be binding)
            (expect t :to-be found-p))
          (nshell.application:with-shell-functions
              ((shared inner-binding) (inner-only other-binding))
            (let ((scope (nshell.application:active-shell-function-scope)))
              (expect outer-scope :to-be
                      (nshell.application:shell-function-scope-parent scope))
              (multiple-value-bind (binding found-p)
                  (nshell.application:peek-shell-function registry "shared"
                                                          :scope scope)
                (expect inner-binding :to-be binding)
                (expect t :to-be found-p))
              (multiple-value-bind (binding found-p)
                  (nshell.application:peek-shell-function registry "inner-only"
                                                          :scope scope)
                (expect other-binding :to-be binding)
                (expect t :to-be found-p))
              (multiple-value-bind (binding found-p)
                  (nshell.application:peek-shell-function registry "global-only"
                                                          :scope scope)
                (expect global-binding :to-be binding)
                (expect t :to-be found-p))))
          (expect outer-scope :to-be
                  (nshell.application:active-shell-function-scope))))
      (expect nil :to-be (nshell.application:active-shell-function-scope))))

  (it "does not autoload on peek and retries lookup once after the hook"
    (let* ((hook-calls 0)
           (binding (%make-shell-function-registry-test-binding :autoloaded))
           (registry
             (nshell.application:make-shell-function-registry
              (make-hash-table :test #'equal)
              (lambda (hook-registry canonical-key)
                (incf hook-calls)
                (setf (gethash canonical-key
                               (nshell.application:shell-function-registry-global-table
                                hook-registry))
                      binding)))))
      (multiple-value-bind (found-binding found-p)
          (nshell.application:peek-shell-function registry "autoloaded")
        (expect nil :to-be found-binding)
        (expect nil :to-be found-p))
      (expect 0 :to-equal hook-calls)
      (multiple-value-bind (found-binding found-p)
          (nshell.application:lookup-shell-function registry "autoloaded")
        (expect binding :to-be found-binding)
        (expect t :to-be found-p))
      (expect 1 :to-equal hook-calls)
      (multiple-value-bind (found-binding found-p)
          (nshell.application:lookup-shell-function registry "AUTOLOADED")
        (expect binding :to-be found-binding)
        (expect t :to-be found-p))
      (expect 1 :to-equal hook-calls)))

  (it "calls a miss hook once and propagates its errors"
    (let* ((hook-calls 0)
           (hook-error (make-condition 'simple-error
                                       :format-control "autoload failed"
                                       :format-arguments nil))
           (registry
             (nshell.application:make-shell-function-registry
              (make-hash-table :test #'equal)
              (lambda (hook-registry canonical-key)
                (declare (ignore hook-registry))
                (incf hook-calls)
                (when (equal canonical-key "BROKEN")
                  (error hook-error))))))
      (multiple-value-bind (binding found-p)
          (nshell.application:lookup-shell-function registry "missing")
        (expect nil :to-be binding)
        (expect nil :to-be found-p))
      (expect 1 :to-equal hook-calls)
      (expect hook-error :to-be
              (handler-case
                  (nshell.application:lookup-shell-function registry "broken")
                (simple-error (condition) condition)))
      (expect 2 :to-equal hook-calls)))

  (it "registers a callable definition in the active shell context"
    (let* ((context (nshell.application:make-shell-context))
           (arguments
             (list (nshell.domain.parsing:make-evaluated-command-arg "first")
                   (nshell.domain.parsing:make-evaluated-command-arg "second"))))
      (let ((nshell.application::*current-user-evaluator-context* context))
        (nshell.application:define-shell-function registry-defined (left right)
          (list left right nshell.application::*current-user-evaluator-position*)))
      (multiple-value-bind (binding found-p)
          (nshell.application:peek-shell-function
           (nshell.application:context-shell-function-registry context)
           "registry-defined")
        (expect t :to-be found-p)
        (expect '(left right) :to-equal
                (nshell.application:shell-function-binding-lambda-list binding))
        (expect "REGISTRY-DEFINED" :to-equal
                (nshell.application:shell-function-binding-display-name binding))
        (expect (list "first" "second" :stream) :to-equal
                (funcall (nshell.application:shell-function-binding-callable binding)
                         context arguments :stream)))))
  (it "preserves escaped string names in lexical bindings"
  (let* ((registry (nshell.application:make-shell-function-registry))
         (plain-global (%make-shell-function-registry-test-binding :plain))
         (escaped-global (%make-shell-function-registry-test-binding :escaped))
         (local-binding (%make-shell-function-registry-test-binding :local)))
    (nshell.application:register-shell-function registry "MixedCase" plain-global)
    (nshell.application:register-shell-function registry "MixedCase" escaped-global
                                                :escaped-p t)
    (nshell.application:with-shell-functions (("MixedCase" local-binding))
      (let ((scope (nshell.application:active-shell-function-scope)))
        (multiple-value-bind (binding found-p)
            (nshell.application:peek-shell-function registry "MixedCase"
                                                    :scope scope :escaped-p t)
          (expect local-binding :to-be binding)
          (expect t :to-be found-p))
        (multiple-value-bind (binding found-p)
            (nshell.application:peek-shell-function registry "mixedcase" :scope scope)
          (expect plain-global :to-be binding)
          (expect t :to-be found-p))))
    (multiple-value-bind (binding found-p)
        (nshell.application:peek-shell-function registry "MixedCase" :escaped-p t)
      (expect escaped-global :to-be binding)
      (expect t :to-be found-p))))
  (it "uses string and escaped symbol names as exact names"
    (let* ((context (nshell.application:make-shell-context))
           (registry
             (nshell.application:context-shell-function-registry context)))
      (let ((nshell.application::*current-user-evaluator-context* context))
        (nshell.application:define-shell-function "FOO" () :string-escaped)
        (nshell.application:define-shell-function |MixedCase| () :symbol-escaped))
      (multiple-value-bind (binding found-p)
          (nshell.application:peek-shell-function registry "FOO" :escaped-p t)
        (expect t :to-be found-p)
        (expect "FOO" :to-equal
                (nshell.application:shell-function-binding-display-name binding))
        (expect :string-escaped :to-equal
                (funcall (nshell.application:shell-function-binding-callable binding)
                         context nil :value)))
      (multiple-value-bind (binding found-p)
          (nshell.application:peek-shell-function registry "FOO")
        (expect nil :to-be binding)
        (expect nil :to-be found-p))
      (multiple-value-bind (binding found-p)
          (nshell.application:peek-shell-function registry "MixedCase" :escaped-p t)
        (expect t :to-be found-p)
        (expect "MixedCase" :to-equal
                (nshell.application:shell-function-binding-display-name binding))
        (expect :symbol-escaped :to-equal
                (funcall (nshell.application:shell-function-binding-callable binding)
                         context nil :value)))
      (multiple-value-bind (binding found-p)
          (nshell.application:peek-shell-function registry "mixedcase")
        (expect nil :to-be binding)
        (expect nil :to-be found-p)))))
(describe "shell-function-directory-autoload"
  (it "loads a real XDG function file into the shell-function registry"
    (host-kit:with-temporary-directory (config-home)
      (let* ((functions-directory
               (merge-pathnames
                #P"nshell/functions/"
                (uiop:ensure-directory-pathname config-home)))
             (function-file
               (merge-pathnames "autoloaded-from-directory.nsh"
                                functions-directory)))
        (ensure-directories-exist function-file)
        (with-open-file (stream function-file
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (write-line "(defun autoloaded-from-directory (value) value)" stream))
        (let* ((environment
                 (nshell.domain.environment:env-set
                  (nshell.domain.environment:make-default-environment)
                  "XDG_CONFIG_HOME"
                  (namestring config-home)
                  t))
               (context
                 (nshell.application:make-shell-context
                  :environment environment))
               (registry
                 (nshell.application:context-shell-function-registry context)))
          (multiple-value-bind (binding found-p)
              (nshell.application:lookup-shell-function
               registry "autoloaded-from-directory")
            (expect t :to-be found-p)
            (expect (namestring function-file)
                    :to-equal
                    (namestring
                     (nshell.application:shell-function-binding-source-path
                      binding)))
            (progn
              (expect (quote (value)) :to-equal
                      (nshell.application:shell-function-binding-lambda-list binding))
              (expect "loaded" :to-equal
                      (funcall
                       (nshell.application:shell-function-binding-callable binding)
                       context
                       (list
                        (nshell.domain.parsing:make-evaluated-command-arg "loaded"))
                       :value)))))))))
