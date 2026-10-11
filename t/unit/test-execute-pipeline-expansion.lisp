(in-package #:nshell/test)

(describe "fragment-escape-provenance-regressions"
  (it "restores an escaped command name"
    (cl-weave:expect-assertions 1)
    (let* ((env (nshell.domain.environment:make-default-environment))
           (fragment (nshell.domain.parsing:make-command-fragment "echo" nil '(1)))
           (node (nshell.domain.parsing:make-command-node
                  "echo" nil nil nil (list fragment))))
      (expect (nshell.application::%expand-command-name-fields-from-fragments node env)
              :to-equal '("echo"))))
  (it "preserves private-use literals alongside a genuine escape"
    (cl-weave:expect-assertions 4)
    (let* ((env (nshell.domain.environment:make-default-environment))
           (data (concatenate 'string
                              (coerce (loop for code from #xe100 below #xe200
                                            collect (code-char code)) 'string)
                              (string (code-char #xf0000))))
           (value (concatenate 'string "$" data))
           (fragment (nshell.domain.parsing:make-command-fragment value nil '(0)))
           (arg (nshell.domain.parsing:make-command-arg value nil nil (list fragment))))
      (expect (nshell.application::%expand-source-arg arg env) :to-equal (list value))
      (expect (nshell.application::%expand-source-arg-in-context
               (make-test-shell-context :environment env) arg) :to-equal (list value))
      (dolist (style '(:single :double))
        (expect (nshell.application::%expand-source-arg
                 (nshell.domain.parsing:make-command-arg data style) env)
                :to-equal (list data)))))
  (it "preserves scalar braced and list data alongside a genuine escape"
    (cl-weave:expect-assertions 6)
    (let* ((env (nshell.domain.environment:make-default-environment))
           (data (concatenate 'string (string (code-char #xe141))
                              (string (code-char #xf0000)))))
      (setf env (nshell.domain.environment:env-set env "PUA" data nil))
      (dolist (suffix '("$PUA" "${PUA}"))
        (let* ((value (concatenate 'string "$" suffix))
               (fragment (nshell.domain.parsing:make-command-fragment value nil '(0)))
               (arg (nshell.domain.parsing:make-command-arg value nil nil (list fragment))))
          (expect (nshell.application::%expand-source-arg arg env)
                  :to-equal (list (concatenate 'string "$" data)))
          (expect (nshell.application::%expand-source-arg-in-context
                   (make-test-shell-context :environment env) arg)
                  :to-equal (list (concatenate 'string "$" data)))))
      (setf env (nshell.domain.environment:env-set-values env "PUA" (list data data) nil))
      (let* ((fragment (nshell.domain.parsing:make-command-fragment "$$PUA" nil '(0)))
             (arg (nshell.domain.parsing:make-command-arg "$$PUA" nil nil (list fragment)))
             (expected (list (concatenate 'string "$" data)
                             (concatenate 'string "$" data))))
        (expect (nshell.application::%expand-source-arg arg env) :to-equal expected)
        (expect (nshell.application::%expand-source-arg-in-context
                 (make-test-shell-context :environment env) arg) :to-equal expected))))
  (it "preserves substitution output alongside a genuine escape"
    (cl-weave:expect-assertions 2)
    (let ((data (concatenate 'string (string (code-char #xe141))
                             (string (code-char #xf0000))))
          (context (make-test-shell-context)))
      (with-temporary-function
          ('nshell.application::%execute-command-substitution-output
           (lambda (&rest args) (declare (ignore args)) data))
        (dolist (style '(nil :double))
          (let* ((fragment (nshell.domain.parsing:make-command-fragment
                            "$(echo marker)$" style '(14)))
                 (arg (nshell.domain.parsing:make-command-arg
                       "$(echo marker)$" style nil (list fragment))))
            (expect (nshell.application::%expand-source-arg-in-context context arg)
                    :to-equal (list (concatenate 'string data "$"))))))))
  (it "retains escape syntax when entering a nested substitution"
    (cl-weave:expect-assertions 2)
    (let* ((data (string (code-char #xe141)))
           (value (concatenate 'string "$(echo $PUA" data ")"))
           (fragment (nshell.domain.parsing:make-command-fragment value :double '(7)))
           (arg (nshell.domain.parsing:make-command-arg value :double nil (list fragment)))
           (seen nil))
      (with-temporary-function
          ('nshell.application::%execute-command-substitution-output
           (lambda (context text)
             (declare (ignore context))
             (setf seen text)
             "marker"))
        (expect (nshell.application::%expand-source-arg-in-context
                 (make-test-shell-context) arg) :to-equal '("marker")))
      (expect seen :to-equal (concatenate 'string "echo \\$PUA" data))))
  (it "expands parsed glob paths without treating escaped wildcards as syntax"
    (cl-weave:expect-assertions 63)
    (let* ((private-directory (concatenate 'string (string (code-char #xe141))
                                           (string (code-char #xf0000))))
           (cases (list (list "echo dir/*" "dir" t)
                        (list "echo 'dir/'*" "dir" t)
                        (list "echo dir/'*'" "dir" nil)
                        (list "echo dir\\/*" "dir" t)
                        (list "echo dir/\\*" "dir" nil)
                        (list "echo dir\\/\\*" "dir" nil)
                        (list (concatenate 'string "echo '" private-directory "'/*")
                              private-directory t)
                        (list (concatenate 'string "echo '" private-directory "'\\/*")
                              private-directory t)
                        (list (concatenate 'string "echo '" private-directory "'/\\*")
                              private-directory nil))))
      (dolist (case cases)
        (destructuring-bind (line directory expand-p) case
          (let* ((seen-root nil)
                 (filesystem
                   (make-test-filesystem
                    :directory-files
                    (lambda (root)
                      (setf seen-root (namestring root))
                      (list (make-pathname :directory (list :relative directory)
                                           :name "a" :type "txt")))))
                 (result (nshell.domain.parsing:parse-command-line line)))
            (expect (nshell.domain.parsing:parse-result-state result) :to-be :complete)
            (let* ((arg (first (nshell.domain.parsing:command-node-args
                               (nshell.domain.parsing:parse-result-ast result))))
                   (context (make-test-shell-context :filesystem filesystem)))
              (dolist (expand (list
                              (lambda ()
                                (nshell.application::%expand-source-arg-in-context context arg))
                              (lambda ()
                                (nshell.application::%expand-source-arg
                                 arg (nshell.application:shell-context-environment context)
                                 filesystem))))
                (setf seen-root nil)
                (expect (funcall expand)
                        :to-equal (list (concatenate 'string directory
                                                     (if expand-p "/a.txt" "/*"))))
                (expect seen-root :to-equal
                        (when expand-p (concatenate 'string directory "/"))))
              (setf seen-root nil)
              (expect (nshell.application::%expand-source-arg arg nil filesystem)
                      :to-equal (list (concatenate 'string directory "/*")))
              (expect seen-root :to-be-null)))))))
  (it "expands complete command-name globs and preserves quoted wildcards"
    (cl-weave:expect-assertions 12)
    (dolist (case '(("'dir/'*" t) ("dir/'*'" nil)
                    ("dir\\/*" t) ("dir/\\*" nil)))
      (destructuring-bind (line expand-p) case
        (let* ((seen-root nil)
               (filesystem
                 (make-test-filesystem
                  :directory-files
                  (lambda (root)
                    (setf seen-root (namestring root))
                    (list #p"dir/tool"))))
               (result (nshell.domain.parsing:parse-command-line line)))
          (expect (nshell.domain.parsing:parse-result-state result) :to-be :complete)
          (expect (nshell.application::%expand-command-name-from-fragments
                   (nshell.domain.parsing:parse-result-ast result)
                   (nshell.domain.environment:make-default-environment)
                   filesystem)
                  :to-equal (if expand-p "dir/tool" "dir/*"))
          (expect seen-root :to-equal (when expand-p "dir/"))))))
  (it "keeps parameter assignment data decoded in the environment"
    (cl-weave:expect-assertions 4)
    (let* ((env (nshell.domain.environment:make-default-environment))
           (data (concatenate 'string (string (code-char #xe141))
                              (string (code-char #xf0000)) "$"))
           (value (concatenate 'string "${PUA:=" data "}"))
           (fragment (nshell.domain.parsing:make-command-fragment
                      value :double (list (- (length value) 2))))
           (arg (nshell.domain.parsing:make-command-arg value :double nil
                                                      (list fragment))))
      (expect (nshell.application::%expand-source-arg arg env) :to-equal (list data))
      (expect (nshell.domain.environment:env-get env "PUA") :to-equal data)
      (let ((reference (nshell.domain.parsing:make-command-arg "$PUA" :double)))
        (expect (nshell.application::%expand-source-arg reference env)
                :to-equal (list data))
        (expect (nshell.application::%expand-source-arg-in-context
                 (make-test-shell-context :environment env) reference)
                :to-equal (list data))))))

(describe "execute-pipeline-expansion-branch-tests"
  (it "protects-and-restores-only-valid-byte-escapes"
    (let* ((wide-character (code-char 955))
           (value (format nil "a~Cz" wide-character))
           (protected (nshell.application::%protect-command-fragment-escapes
                       value
                       (list -1 0 1 3)))
           (escape-base #xe100))
      (expect (code-char (+ escape-base (char-code #\a)))
              :to-be
              (char protected 0))
      (expect wide-character :to-be (char protected 1))
      (expect value
              :to-equal
              (nshell.application::%restore-command-fragment-escapes protected))
      (expect "x"
              :to-equal
              (nshell.application::%restore-command-fragment-escapes "x"))))
  (it "expands-source-fragments-with-and-without-an-environment"
    (let* ((fragment (nshell.domain.parsing:make-command-fragment "$FOO"))
           (environment
             (nshell.domain.environment:env-set
              (nshell.domain.environment:make-default-environment)
              "FOO"
              "bar"
              nil)))
      (expect (list "$FOO")
              :to-equal
              (nshell.application::%expand-source-fragment-fields
               fragment nil))
      (expect (list "bar")
              :to-equal
              (nshell.application::%expand-source-fragment-fields
               fragment environment))))
  (it "normalizes-command-substitution-data"
    (expect (nshell.application::%trim-command-substitution-output
             (format nil "one~%two~%~C" #\Return))
            :to-equal
            (format nil "one~%two"))
    (expect (nshell.application::%command-substitution-fields
             (format nil "one~%two~%"))
            :to-equal
            (list "one" "two"))
    (expect (nshell.application::%command-substitution-fields nil)
            :to-equal
            nil))
  (it "appends-command-substitution-fields-with-empty-fallback"
    (expect (nshell.application::%append-command-substitution-fields
             (list "prefix")
             (list "one" "two"))
            :to-equal
            (list "prefixone" "prefixtwo"))
    (expect (nshell.application::%append-command-substitution-fields
             (list "prefix")
             nil)
            :to-equal
            (list "prefix"))
    (expect (nshell.application::%append-command-substitution-char
             (list "a" "b") #\x)
            :to-equal
            (list "ax" "bx"))
    (expect (nshell.application::%append-command-substitution-string
             (list "a" "b") "value")
            :to-equal
            (list "avalue" "bvalue")))
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
  (it "selects-command-substitution-modes-explicitly"
    (let ((context (make-test-shell-context)))
      (with-temporary-functions
          (('nshell.application::%execute-command-substitution-fields
            (lambda (ignored-context text)
              (declare (ignore ignored-context))
              (when (string= text "printf posix")
                (list "one" "two"))))
           ('nshell.application::%execute-command-substitution-output
            (lambda (ignored-context text)
              (declare (ignore ignored-context))
              (when (string= text "printf posix")
                "one\ntwo\n"))))
        (expect (list "(printf bare)")
                :to-equal
                (nshell.application::%expand-command-substitutions
                 context
                 "(printf bare)"
                 nil
                 nil))
        (expect (list "one\ntwo\n")
                :to-equal
                (nshell.application::%expand-command-substitutions
                 context
                 "$(printf posix)"
                 t
                 nil)))))
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
