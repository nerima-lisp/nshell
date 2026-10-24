(in-package #:nshell/test)
(describe "l03-builtin-contracts"
  (it "registry-lookup-is-exact-and-reports-misses"
    (let ((nshell.application::*builtin-binding-registry*
            (make-hash-table :test (quote equal))))
      (let* ((binding
               (nshell.application:make-builtin-binding
                (lambda (context arguments)
                  (declare (ignore context arguments))
                  (values nil 0))
                :argv)))
        (expect binding :to-be
                (nshell.application:register-builtin "MiXeD" binding))
        (multiple-value-bind (found found-p)
            (nshell.application:lookup-builtin-binding "MiXeD")
          (expect binding :to-be found)
          (expect t :to-be found-p))
        (multiple-value-bind (found found-p)
            (nshell.application:lookup-builtin-binding "mixed")
          (expect nil :to-be found)
          (expect nil :to-be found-p)))))
  (it "argv-dispatch-uses-supplied-strings-and-normalizes-nil-output"
    (let* ((received nil)
          (binding
            (nshell.application:make-builtin-binding
             (lambda (context arguments)
               (declare (ignore context))
               (setf received arguments)
               (values nil 7))
             :argv)))
      (multiple-value-bind (output status)
          (nshell.application:dispatch-builtin
           nil binding (list :unconverted)
           :argv-strings (list "already-converted"))
        (expect "" :to-equal output)
        (expect 7 :to-equal status)
        (expect (list "already-converted") :to-equal received))))
  (it "value-dispatch-preserves-argument-records-and-result"
    (let* ((argument
             (nshell.domain.parsing:make-evaluated-command-arg
              :structured (list 3 8) nil nil))
           (arguments (list argument))
           (result (list :structured-result 42))
           (received nil)
           (binding
             (nshell.application:make-builtin-binding
              (lambda (context evaluated-arguments)
                (declare (ignore context))
                (setf received evaluated-arguments)
                (values result 5))
              :value)))
      (multiple-value-bind (value status)
          (nshell.application:dispatch-builtin nil binding arguments)
        (expect arguments :to-be received)
        (expect result :to-be value)
        (expect 5 :to-equal status))))
  (it "argv-expansion-is-gated-and-ordered-brace-tilde-glob"
    (let* ((environment
             (nshell.domain.environment:env-set
              (nshell.domain.environment:make-environment)
              "HOME" "/home/l03" nil))
           (seen-directories nil)
           (filesystem
             (make-test-filesystem
              :directory-files
              (lambda (directory)
                (push (namestring directory) seen-directories)
                (list (merge-pathnames "match.txt" directory)))
              :subdirectories (constantly nil)))
           (context
             (nshell.application:make-shell-context
              :environment environment :filesystem filesystem))
           (source-argument
             (nshell.domain.parsing:make-evaluated-command-arg
              "~/{a,b}/*.txt" (list 0 14) t t))
           (no-glob-argument
             (nshell.domain.parsing:make-evaluated-command-arg
              "~/{a,b}/*.txt" (list 0 14) nil t))
           (literal-argument
             (nshell.domain.parsing:make-evaluated-command-arg
              "~/{a,b}/*.txt" (list 0 14) t nil)))
      (with-temporary-function
          ((quote nshell.application:argv-scalar-string)
           (lambda (value &key source-span)
             (declare (ignore source-span))
             value))
        (expect (list "/home/l03/a/match.txt" "/home/l03/b/match.txt")
                :to-equal
                (nshell.application:command-argv-strings
                 context (list source-argument)))
        (expect (list "/home/l03/a/*.txt" "/home/l03/b/*.txt")
                :to-equal
                (nshell.application:command-argv-strings
                 context (list no-glob-argument)))
        (expect (list "~/{a,b}/*.txt")
                :to-equal
                (nshell.application:command-argv-strings
                 context (list literal-argument)))
        (expect (list "/home/l03/a/" "/home/l03/b/")
                :to-equal
                (sort (copy-list seen-directories) (function string<))))))
  (it "eval-handler-reads-and-evaluates-a-host-form-without-l08"
    (let ((context (nshell.application:make-shell-context)))
      (multiple-value-bind (output status)
          (nshell.application::%builtin-eval-sexp
           context (list "(cl:princ \"L03_EVAL_OK\")"))
        (expect "L03_EVAL_OK" :to-equal output)
        (expect 0 :to-equal status)))))
