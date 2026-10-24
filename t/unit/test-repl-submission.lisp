(in-package #:nshell/test)

(describe "e03-repl-submission"
  (it "e03-reader-route-context-is-derived-from-the-raw-input-and-dormant-by-default"
    (let ((nshell.presentation::*repl-new-reader-route-enabled-p* nil))
      (expect :bare-line :to-be
              (nshell.presentation::%repl-reader-context-for-source "(+ 1 2)")))
    (let ((nshell.presentation::*repl-new-reader-route-enabled-p* t))
      (expect :sexp :to-be
              (nshell.presentation::%repl-reader-context-for-source "  (+ 1 2)"))
      (expect :bare-line :to-be
              (nshell.presentation::%repl-reader-context-for-source "echo (+ 1 2)"))))
  (it "e03-reader-route-environment-enables-only-exact-sexp"
    (let ((source " (+ 1 2)"))
      (with-temporary-function
          ('uiop:getenv (lambda (name) (declare (ignore name)) nil))
        (expect :bare-line :to-be
                (nshell.presentation::%repl-reader-context-for-source source)))
      (with-temporary-function
          ('uiop:getenv
           (lambda (name)
             (when (string= name "NSHELL_READER") "shell")))
        (expect :bare-line :to-be
                (nshell.presentation::%repl-reader-context-for-source source)))
      (with-temporary-function
          ('uiop:getenv
           (lambda (name)
             (when (string= name "NSHELL_READER") "sexp")))
        (expect :sexp :to-be
                (nshell.presentation::%repl-reader-context-for-source source)))))

  (it "e03-new-reader-route-passes-context-and-evaluates-results-in-order"
    (with-repl-test-state
      (let ((nshell.presentation::*repl-new-reader-route-enabled-p* t)
            (read-call nil)
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
  (it "e03-scanner-complete-block-uses-legacy-parser-continuation"
    (let* ((source "if true")
           (scan-result
             (nshell.domain.parsing:scan-input
              source
              :cursor (length source)
              :reader-context :bare-line
              :indent-width nshell.presentation::+editor-indent-width+)))
      (expect (list :complete :incomplete)
        :to-equal
        (list (nshell.domain.parsing:scan-result-status scan-result)
              (nshell.domain.parsing:parse-result-state
               (nshell.domain.parsing:parse-command-line source))))
      (with-repl-test-state
        (let ((nshell.presentation::*repl-new-reader-route-enabled-p* nil))
          (with-repl-input-state (:buffer source :cursor-pos (length source))
            (let ((continuation nil))
              (capture-standard-output
                (setf continuation
                      (nshell.presentation::process-output-event :execute)))
              (expect (functionp continuation) :to-be-truthy)
              (expect source :to-equal
                      (subseq
                       (nshell.presentation:input-state-buffer
                        nshell.presentation::*input-state*)
                       0
                       (length source)))
              (expect #\Newline :to-equal
                      (char
                       (nshell.presentation:input-state-buffer
                        nshell.presentation::*input-state*)
                       (length source)))
              (expect (length (nshell.presentation:input-state-buffer
                               nshell.presentation::*input-state*))
                      :to-equal
                      (nshell.presentation:input-state-cursor-pos
                       nshell.presentation::*input-state*))))))))
)