(in-package #:nshell/test)

(describe "execute-pipeline-expansion-branch-tests"
  (it "normalizes-command-substitution-data"
    (expect "one\ntwo"
            :to-equal
            (nshell.application::%trim-command-substitution-output
             "one\ntwo\n\r"))
    (expect (list "one" "two")
            :to-equal
            (nshell.application::%command-substitution-fields "one\ntwo\n"))
    (expect nil
            :to-equal
            (nshell.application::%command-substitution-fields nil)))
  (it "appends-command-substitution-fields-with-empty-fallback"
    (expect (list "prefixone" "prefixtwo")
            :to-equal
            (nshell.application::%append-command-substitution-fields
             (list "prefix")
             (list "one" "two")))
    (expect (list "prefix")
            :to-equal
            (nshell.application::%append-command-substitution-fields
             (list "prefix")
             nil))
    (expect (list "ax" "bx")
            :to-equal
            (nshell.application::%append-command-substitution-char
             (list "a" "b") #\x))
    (expect (list "avalue" "bvalue")
            :to-equal
            (nshell.application::%append-command-substitution-string
             (list "a" "b") "value")))
  (it "expands-balanced-and-falls-back-for-arithmetic-substitutions"
    (let ((balanced "$((1+2))")
          (unbalanced "$((1+2)"))
      (multiple-value-bind (parts position)
          (nshell.application::%expand-arithmetic-command-substitution-at
           balanced 0 (list "") (length balanced))
        (expect (list balanced) :to-equal parts)
        (expect (length balanced) :to-equal position))
      (multiple-value-bind (parts position)
          (nshell.application::%expand-arithmetic-command-substitution-at
           unbalanced 0 (list "") (length unbalanced))
        (expect (list "$") :to-equal parts)
        (expect 1 :to-equal position))))
  (it "expands-posix-and-bare-command-substitutions"
    (let ((context (make-test-shell-context)))
      (with-temporary-function
          ((quote nshell.application::%execute-command-substitution-fields)
           (lambda (ignored-context text)
             (declare (ignore ignored-context))
             (cond
               ((string= text "printf posix") (list "one" "two"))
               ((string= text "printf bare") (list "three"))
               (t nil))))
        (multiple-value-bind (parts position)
            (nshell.application::%expand-posix-command-substitution-at
             context "$(printf posix)" 0 (list "prefix") (length "$(printf posix)"))
          (expect (list "prefixone" "prefixtwo") :to-equal parts)
          (expect (length "$(printf posix)") :to-equal position))
        (multiple-value-bind (parts position)
            (nshell.application::%expand-bare-command-substitution-at
             context "(printf bare)" 0 (list "prefix"))
          (expect (list "prefixthree") :to-equal parts)
          (expect (length "(printf bare)") :to-equal position)))))
  (it "preserves-literal-characters-and-unbalanced-substitutions"
    (let ((context (make-test-shell-context)))
      (multiple-value-bind (parts position)
          (nshell.application::%expand-command-substitution-at
           context "x" 0 (list "prefix") 1)
        (expect (list "prefixx") :to-equal parts)
        (expect 1 :to-equal position))
      (multiple-value-bind (parts position)
          (nshell.application::%expand-command-substitution-at
           context "$(printf" 0 (list "") (length "$(printf"))
        (expect (list "$") :to-equal parts)
        (expect 1 :to-equal position))
      (multiple-value-bind (parts position)
          (nshell.application::%expand-command-substitution-at
           context "(printf" 0 (list "") (length "(printf"))
        (expect (list "(") :to-equal parts)
        (expect 1 :to-equal position))))
  (it "iteratively-expands-command-substitutions-in-order"
    (let ((context (make-test-shell-context)))
      (with-temporary-function
          ((quote nshell.application::%execute-command-substitution-fields)
           (lambda (ignored-context text)
             (declare (ignore ignored-context))
             (when (string= text "printf value")
               (list "one" "two"))))
        (expect (list "aoneb" "atwob")
                :to-equal
                (nshell.application::%expand-command-substitutions
                 context
                 "a$(printf value)b")))))
  (it "classifies-here-document-escapes"
    (dolist (case (list
                   (list (format nil "\\~c" #\Newline) nil 2)
                   (list "\\$" nshell.application::+here-doc-escaped-dollar+ 2)
                   (list "\\$(" nshell.application::+here-doc-escaped-command-open+ 3)
                   (list "\\`" nshell.application::+here-doc-escaped-backtick+ 2)
                   (list "\\\\" nshell.application::+here-doc-escaped-backslash+ 2)
                   (list "\\x" nil nil)
                   (list "x" nil nil)
                   (list "\\" nil nil)))
      (destructuring-bind (input expected-token expected-width) case
        (multiple-value-bind (token width)
            (nshell.application::%here-doc-escape-at input 0)
          (expect expected-token :to-be token)
          (expect expected-width :to-be width)))))
  (it "applies-quote-style-and-here-document-expansion"
    (let* ((environment
             (nshell.domain.environment:env-set
              (nshell.domain.environment:make-default-environment)
              "FOO"
              "bar baz"
              nil))
           (context (make-test-shell-context :environment environment)))
      (expect (nshell.application::%expand-source-arg (nshell.domain.parsing:make-command-arg "$FOO") environment) :to-equal (list "bar baz"))
      (expect (list "bar baz")
              :to-equal
              (nshell.application::%expand-source-arg
               (nshell.domain.parsing:make-command-arg "$FOO" :double)
               environment))
      (expect (list "$FOO")
              :to-equal
              (nshell.application::%expand-source-arg
               (nshell.domain.parsing:make-command-arg "$FOO" :single)
               environment))
      (expect (list "$FOO")
              :to-equal
              (nshell.application::%expand-source-arg
               (nshell.domain.parsing:make-command-arg "$FOO" nil t)
               environment))
      (with-temporary-function
          ((quote nshell.application::%execute-command-substitution-fields)
           (lambda (ignored-context text)
             (declare (ignore ignored-context))
             (cond
               ((string= text "printf bare") (list "bare"))
               ((string= text "printf dollar") (list "dollar"))
               (t nil))))
        (expect (list "(printf bare)")
                :to-equal
                (nshell.application::%expand-source-arg-in-context
                 context
                 (nshell.domain.parsing:make-command-arg
                  "(printf bare)"
                  :double)))
        (expect (list "dollar")
                :to-equal
                (nshell.application::%expand-source-arg-in-context
                 context
                 (nshell.domain.parsing:make-command-arg
                  "$(printf dollar)"
                  :double))))))
  (it "expands-command-arguments-through-a-shell-context"
    (let* ((environment
             (nshell.domain.environment:env-set
              (nshell.domain.environment:make-default-environment)
              "FOO"
              "value"
              nil))
           (context (make-test-shell-context :environment environment))
           (command
             (nshell.domain.parsing:make-command-node
              "echo"
              (list
               (nshell.domain.parsing:make-command-arg "$FOO")
               (nshell.domain.parsing:make-command-arg "literal" :single)))))
      (expect (list "value" "literal")
              :to-equal
              (nshell.application::%line-command-args-in-context context command))
      (expect (list "value" "literal")
              :to-equal
              (nshell.application::%line-command-args command environment))))
  (it "applies-context-redirects-through-the-acl-boundary"
      "Supported redirect kinds delegate to the infrastructure ACL with normalized modes."
      (let ((calls nil))
        (flet ((record (name &rest args)
                       (push (cons name args) calls)))
          (with-temporary-functions
              (('nshell.infrastructure.acl:redirect-output
                (lambda (target mode)
                  (record :output target mode)))
               ('nshell.infrastructure.acl:redirect-output-and-error
                (lambda (target mode)
                  (record :output-error target mode)))
               ('nshell.infrastructure.acl:redirect-error
                (lambda (target mode)
                  (record :error target mode)))
               ('nshell.infrastructure.acl:redirect-error-to-output
                (lambda ()
                  (record :error-to-output)))
               ('nshell.infrastructure.acl:redirect-output-to-error
                (lambda ()
                  (record :output-to-error)))
               ('nshell.infrastructure.acl:redirect-input
                (lambda (target)
                  (record :input target)))
               ('nshell.infrastructure.acl:redirect-input-string
                (lambda (target)
                  (record :input-string target)))
               ('nshell.infrastructure.acl:redirect-input-document
                (lambda (target)
                  (record :input-document target)))
               ('nshell.infrastructure.acl:restore-redirects
                (lambda ()
                  (record :restore))))
            (let ((context (make-test-shell-context)))
              (let ((expected
                      (list
                       (cons :output (list "out" :supersede))
                       (cons :output (list "append" :append))
                       (cons :output-error (list "both" :supersede))
                       (cons :output-error (list "both-append" :append))
                       (cons :error (list "err" :supersede))
                       (cons :error (list "err-append" :append))
                       (cons :error-to-output nil)
                       (cons :output-to-error nil)
                       (cons :error-to-output nil)
                       (cons :input (list "in"))
                       (cons :input-string (list "literal"))
                       (cons :input-document (list "here"))
                       (cons :input-document (list "here-strip")))))
                (expect nil
                        :to-be
                        (nshell.application::%apply-context-redirects
                         context
                         (list
                          (cons :> "out")
                          (cons :>> "append")
                          (cons :&> "both")
                          (cons :&>> "both-append")
                          (cons :2> "err")
                          (cons :2>> "err-append")
                          (cons :2>&1 nil)
                          (cons :fd-dup
                                (nshell.domain.parsing:make-redirect-fd-dup-target
                                 1
                                 2))
                          (cons :fd-dup
                                (nshell.domain.parsing:make-redirect-fd-dup-target
                                 2
                                 1))
                          (cons :< "in")
                          (cons :<<< "literal")
                          (cons :<< "here")
                          (cons :<<- "here-strip")
                          (cons :unknown "ignored"))))
                (expect expected :to-equal (reverse calls))
                (nshell.application::%restore-context-redirects context)
                (expect (append expected (list (cons :restore nil)))
                        :to-equal
                        (reverse calls))))))))
  (it "rejects-invalid-context-file-descriptor-redirects"
    "Malformed descriptor duplication fails before execution dispatch."
    (let ((context (make-test-shell-context)))
       (expect
       (lambda ()
         (nshell.application::%apply-context-redirects
          context
          (list (cons :fd-dup nil))))
       :to-throw (quote error))
      (expect
       (lambda ()
         (nshell.application::%apply-context-redirects
          context
          (list
           (cons :fd-dup
                 (nshell.domain.parsing:make-redirect-fd-dup-target
                 3
                 1)))))
       :to-throw (quote error))))
)
