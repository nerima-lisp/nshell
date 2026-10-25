(in-package #:nshell/test)

(describe "e03-repl-submission"
  (it "e03-reader-route-context-is-derived-from-source-by-default"
    (expect :sexp :to-be
            (nshell.presentation::%repl-reader-context-for-source "(+ 1 2)"))
    (expect :bare-line :to-be
            (nshell.presentation::%repl-reader-context-for-source "echo (+ 1 2)")))
  (it "e03-new-reader-default-passes-context-and-evaluates-results-in-order"
    (with-repl-test-state
      (let ((read-call nil)
            (evaluated-results nil))
        (with-temporary-functions
            (('nshell.presentation::%execute-complete-command
              (lambda (ast text evaluator)
                (expect nil :to-be ast)
                (list :executed text (funcall evaluator))))
             ('nshell.domain.parsing:read-submission
              (lambda (source &key reader-context)
                (setf read-call (list source reader-context))
                '(:first :second)))
             ('nshell.application:evaluate-reader-result-in-context
              (lambda (context reader-result)
                (declare (ignore context))
                (push reader-result evaluated-results)
                (values nil (if (eq reader-result :first) 3 17))))
             ('nshell.presentation::call-with-command-failure-restarts
              (lambda (thunk) (funcall thunk))))
          (expect '(:executed "echo" 17)
                  :to-equal
                  (nshell.presentation::%execute-command-line "echo"))
          (expect '("echo" :bare-line) :to-equal read-call)
          (expect '(:first :second) :to-equal (nreverse evaluated-results))))))
  (it "e03-new-reader-expands-bare-history-and-keeps-raw-mode"
    (with-repl-test-state
      (setf nshell.presentation::*history*
            (history-with-lines "echo first"))
      (let ((read-calls nil)
            (evaluated-results nil))
        (with-temporary-functions
            (('nshell.presentation::%execute-complete-command
              (lambda (ast text evaluator)
                (expect nil :to-be ast)
                (list :executed text (funcall evaluator))))
             ('nshell.domain.parsing:read-submission
              (lambda (source &key reader-context)
                (push (list source reader-context) read-calls)
                '(:first :second)))
             ('nshell.application:evaluate-reader-result-in-context
              (lambda (context reader-result)
                (declare (ignore context))
                (push reader-result evaluated-results)
                (values nil (if (eq reader-result :first) 3 17))))
             ('nshell.presentation::call-with-command-failure-restarts
              (lambda (thunk) (funcall thunk))))
          (expect '(:executed "echo first" 17)
                  :to-equal
                  (nshell.presentation::%execute-command-line "!!"))
          (expect '(:executed "first" 17)
                  :to-equal
                  (nshell.presentation::%execute-command-line "!$"))
          (setf nshell.presentation::*history*
                (history-with-lines "(+ 1 2)"))
          (expect '(:executed "(+ 1 2)" 17)
                  :to-equal
                  (nshell.presentation::%execute-command-line "!!"))
          (expect '(("echo first" :bare-line) ("first" :bare-line) ("(+ 1 2)" :bare-line))
                  :to-equal
                  (nreverse read-calls))
          (expect '(:first :second :first :second :first :second)
                  :to-equal
                  (nreverse evaluated-results))))))
  (it "e03-new-reader-suppresses-history-expansion-for-sexps"
    (with-repl-test-state
      (setf nshell.presentation::*history*
            (history-with-lines "echo previous"))
      (let ((read-call nil))
        (with-temporary-functions
            (('nshell.presentation::%execute-complete-command
              (lambda (ast text evaluator)
                (expect nil :to-be ast)
                (list :executed text (funcall evaluator))))
             ('nshell.domain.parsing:read-submission
              (lambda (source &key reader-context)
                (setf read-call (list source reader-context))
                '(:sexp-result)))
             ('nshell.application:evaluate-reader-result-in-context
              (lambda (context reader-result)
                (declare (ignore context reader-result))
                (values nil 23)))
             ('nshell.presentation::call-with-command-failure-restarts
              (lambda (thunk) (funcall thunk))))
          (expect '(:executed "(list !! !$)" 23)
                  :to-equal
                  (nshell.presentation::%execute-command-line "(list !! !$)"))
          (expect '("(list !! !$)" :sexp) :to-equal read-call)))))
  (it "e03-reader-enter-expands-abbreviation-before-scanning"
    (let ((state
            (completion-session-state
             :buffer "p04"
             :cursor-pos 3
             :completion-index 2
             :suggestion " ignored"
             :abbreviation-expander
             (lambda (token)
               (when (string= token "p04")
                 "echo P04_OK")))))
      (multiple-value-bind (submitted-state output)
          (reduce-once state :enter)
        (expect :execute :to-be output)
        (expect "echo P04_OK" :to-equal
                (nshell.presentation:input-state-buffer submitted-state))
        (expect 11 :to-equal
                (nshell.presentation:input-state-cursor-pos submitted-state))
        (expect -1 :to-equal
                (nshell.presentation::input-state-completion-index submitted-state))
        (expect nil :to-be
                (nshell.presentation:input-state-suggestion submitted-state)))))
  (it "e03-reader-scanner-incomplete-host-form-enters-continuation"
    (let* ((source "(if t")
           (cursor (length source))
           (scan-result
             (nshell.presentation::%repl-input-scan-result
              source
              cursor
              (nshell.presentation::%repl-reader-context-for-source source)))
           (indent
             (nshell.domain.parsing:scan-result-next-indent scan-result))
           (expected-buffer
             (concatenate
              (quote string)
              source
              (string (code-char 10))
              (make-string indent :initial-element (code-char 32)))))
      (expect :incomplete :to-be
              (nshell.domain.parsing:scan-result-status scan-result))
      (multiple-value-bind (continued-state output)
          (reduce-once (input-state :buffer source :cursor-pos cursor) :enter)
        (expect :suggest-update :to-be output)
        (expect expected-buffer :to-equal
                (nshell.presentation:input-state-buffer continued-state))
        (expect (+ cursor 1 indent) :to-equal
                (nshell.presentation:input-state-cursor-pos continued-state)))))
  (it "e03-new-reader-keeps-shell-functions-between-submissions"
      (with-repl-test-state
       (let ((output
              (capture-standard-output
               (expect 0 :to-equal
                       (nshell.presentation::%evaluate-repl-reader-submission
                        "(define-shell-function e03-persistent () (format t \"E03_REPL_FUNCTION_OK~%\"))"
                        :sexp))
               (expect 0 :to-equal
                       (nshell.presentation::%evaluate-repl-reader-submission
                        "e03-persistent"
                        :bare-line)))))
         (expect (search "E03_REPL_FUNCTION_OK" output) :to-be-truthy))))
  (it "e03-new-reader-refreshes-autoload-context-for-each-submission"
      (with-repl-test-state
       (host-kit:with-temporary-directory (config-home-a)
                                          (host-kit:with-temporary-directory (config-home-b)
                                                                             (let* ((functions-directory-a
                                                                                     (merge-pathnames
                                                                                      #P"nshell/functions/"
                                                                                      (uiop:ensure-directory-pathname config-home-a)))
                                                                                    (functions-directory-b
                                                                                     (merge-pathnames
                                                                                      #P"nshell/functions/"
                                                                                      (uiop:ensure-directory-pathname config-home-b)))
                                                                                    (function-file-a
                                                                                     (merge-pathnames "e03-autoloaded.nsh" functions-directory-a))
                                                                                    (function-file-b
                                                                                     (merge-pathnames "e03-autoloaded.nsh" functions-directory-b)))
                                                                               (ensure-directories-exist function-file-a)
                                                                               (ensure-directories-exist function-file-b)
                                                                               (with-open-file (stream function-file-a
                                                                                                       :direction :output
                                                                                                       :if-exists :supersede
                                                                                                       :if-does-not-exist :create)
                                                                                 (write-line
                                                                                  "(defun e03-autoloaded () (format t \"E03_AUTOLOAD_A~%\"))"
                                                                                  stream))
                                                                               (with-open-file (stream function-file-b
                                                                                                       :direction :output
                                                                                                       :if-exists :supersede
                                                                                                       :if-does-not-exist :create)
                                                                                 (write-line
                                                                                  "(defun e03-autoloaded () (format t \"E03_AUTOLOAD_B~%\"))"
                                                                                  stream))
                                                                               (setf nshell.presentation::*environment*
                                                                                     (nshell.domain.environment:env-set
                                                                                      nshell.presentation::*environment*
                                                                                      "XDG_CONFIG_HOME"
                                                                                      (namestring config-home-a)
                                                                                      t))
                                                                               (let* ((context-a
                                                                                       (nshell.presentation::%make-repl-shell-context))
                                                                                      (registry-a
                                                                                       (nshell.application:context-shell-function-registry
                                                                                        context-a)))
                                                                                 (setf nshell.presentation::*environment*
                                                                                       (nshell.domain.environment:env-set
                                                                                        nshell.presentation::*environment*
                                                                                        "XDG_CONFIG_HOME"
                                                                                        (namestring config-home-b)
                                                                                        t))
                                                                                 (let* ((context-b
                                                                                         (nshell.presentation::%make-repl-shell-context))
                                                                                        (registry-b
                                                                                         (nshell.application:context-shell-function-registry
                                                                                          context-b)))
                                                                                   (expect t :to-be (eq registry-a registry-b))))
                                                                               (let ((output
                                                                                      (capture-standard-output
                                                                                       (expect 0 :to-equal
                                                                                               (nshell.presentation::%evaluate-repl-reader-submission
                                                                                                "e03-autoloaded"
                                                                                                :bare-line)))))
                                                                                 (expect (search "E03_AUTOLOAD_B" output) :to-be-truthy)
                                                                                 (expect nil :to-be (search "E03_AUTOLOAD_A" output)))))))))
