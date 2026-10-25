(in-package #:nshell/test)

(describe "sexp-value-conversion"
  (it "converts command argument scalars and rejects nil or conses"
    (expect "Ada" :to-equal
            (nshell.application:argv-scalar-string "Ada"))
    (expect "Z" :to-equal
            (nshell.application:argv-scalar-string #\Z))
    (expect "42" :to-equal
            (nshell.application:argv-scalar-string 42))
    (expect "FOO" :to-equal
            (nshell.application:argv-scalar-string :foo))
    (expect (lambda () (nshell.application:argv-scalar-string nil))
            :to-throw 'nshell.application:command-argument-type-error)
    (expect (lambda () (nshell.application:argv-scalar-string '(1 2)))
            :to-throw 'nshell.application:command-argument-type-error)
    (let ((caught nil))
      (handler-case
          (nshell.application:argv-scalar-string nil :source-span '(2 5))
        (nshell.application:command-argument-type-error (condition)
          (setf caught condition)))
      (expect caught :to-be-truthy)
      (expect '(2 5) :to-equal
              (nshell.application:command-argument-type-error-source-span
               caught))))
  (it "converts JSON objects and lists with explicit empty-container behavior"
    (let* ((value '(("name" . "Ada")
                    ("items" . (1 2))
                    ("profile" . (("active" . t)))))
           (text (nshell.user:|to-json| value)))
      (expect "{\"name\":\"Ada\",\"items\":[1,2],\"profile\":{\"active\":true}}"
              :to-equal text)
      (expect value :to-equal (nshell.user:|from-json| text)))
    (expect "[]" :to-equal (nshell.user:|to-json| nil))
    (expect nil :to-equal (nshell.user:|from-json| "{}"))
    (expect nil :to-equal (nshell.user:|from-json| "[]")))
  (it "O09-lowercase-conversion-api-exports"
    (cl-weave:expect-assertions 1)
    (let* ((package (find-package "NSHELL.USER"))
           (names
             (list "to-json" "from-json" "to-tsv" "from-tsv"
                   "to-lines" "from-lines" "regex-match-p" "regex-find"
                   "regex-replace" "split-string" "join-strings"
                   "replace-string"))
           (expected
             (mapcar (lambda (name) (list name :external t)) names))
           (actual
             (mapcar
              (lambda (name)
                (multiple-value-bind (symbol status)
                    (find-symbol name package)
                  (list name status (and symbol (fboundp symbol) t))))
              names)))
      (expect expected :to-equal actual)))
  (it "O09-lowercase-conversion-api-dispatches-through-reader"
    (cl-weave:expect-assertions 3)
    (let* ((reader-result
             (first
              (nshell.domain.parsing:read-submission
               "(to-json CL:NIL)" :reader-context :sexp)))
           (form
             (nshell.domain.parsing:reader-result-form reader-result))
           (context (make-test-shell-context)))
      (expect "to-json" :to-equal (symbol-name (first form)))
      (multiple-value-bind (value status)
          (nshell.application:evaluate-reader-result-in-context
           context reader-result)
        (expect "[]" :to-equal value)
        (expect 0 :to-equal status))))
  (it "wraps malformed JSON with its operation, input, and parser cause"
    (let ((caught nil))
      (handler-case
          (nshell.user:|from-json| "{bad")
        (nshell.application:value-conversion-error (condition)
          (setf caught condition)))
      (expect caught :to-be-truthy)
      (expect :from-json :to-equal
              (nshell.application:value-conversion-error-operation caught))
      (expect "{bad" :to-equal
              (nshell.application:value-conversion-error-input caught))
      (expect (typep (nshell.application:value-conversion-error-cause caught)
                     'json-kit:json-parse-error) :to-be-truthy)))
  (it "converts TSV rows and rejects malformed or unrepresentable data"
    (let ((text
            (nshell.user:|to-tsv| '(("name" "Ada") ("age" "37")))))
      (expect (concatenate 'string
                           "name" (string #\Tab) "Ada" (string #\Newline)
                           "age" (string #\Tab) "37" (string #\Newline))
              :to-equal text)
      (expect '(("name" "Ada") ("age" "37")) :to-equal
              (nshell.user:|from-tsv| text)))
    (expect nil :to-equal (nshell.user:|from-tsv| ""))
    (expect (lambda () (nshell.user:|from-tsv| "field"))
            :to-throw 'nshell.application:value-conversion-error)
    (expect (lambda () (nshell.user:|to-tsv| '(nil)))
            :to-throw 'nshell.application:value-conversion-error)
    (expect (lambda ()
              (nshell.user:|to-tsv|
               (list (list (concatenate 'string "bad" (string #\Tab) "field")))))
            :to-throw 'nshell.application:value-conversion-error))
  (it "normalizes line endings and emits LF-terminated lines"
    (let ((text
            (concatenate 'string "first" (string #\Return) (string #\Newline)
                         "second" (string #\Newline))))
      (expect '("first" "second") :to-equal (nshell.user:|to-lines| text)))
    (expect (concatenate 'string "first" (string #\Newline)
                         "second" (string #\Newline))
            :to-equal (nshell.user:|from-lines| '("first" "second")))
    (expect nil :to-equal (nshell.user:|to-lines| ""))
    (expect (lambda () (nshell.user:|to-lines|
                        (concatenate 'string "bad" (string #\Return) "line")))
            :to-throw 'nshell.application:value-conversion-error)
    (expect (lambda () (nshell.user:|from-lines| '("bad
line")))
            :to-throw 'nshell.application:value-conversion-error))
  (it "returns regex captures and treats replacement strings literally"
    (multiple-value-bind (match start end captures)
        (nshell.user:|regex-find| "(foo)(bar)?" "xfoo!")
      (expect "foo" :to-equal match)
      (expect 1 :to-equal start)
      (expect 4 :to-equal end)
      (expect '("foo" nil) :to-equal captures))
    (multiple-value-bind (match start end captures)
        (nshell.user:|regex-find| "foo" "xfoofoo" :start 2)
      (expect "foo" :to-equal match)
      (expect 4 :to-equal start)
      (expect 7 :to-equal end)
      (expect nil :to-equal captures))
    (multiple-value-bind (match start end captures)
        (nshell.user:|regex-find| "foo" "xfoo" :start 5)
      (expect nil :to-equal match)
      (expect nil :to-equal start)
      (expect nil :to-equal end)
      (expect nil :to-equal captures))
    (multiple-value-bind (match start end captures)
        (nshell.user:|regex-find| "" "abc" :start 3)
      (expect "" :to-equal match)
      (expect 3 :to-equal start)
      (expect 3 :to-equal end)
      (expect nil :to-equal captures))
    (multiple-value-bind (match start end captures)
        (nshell.user:|regex-find| "foo" "λfoo")
      (expect "foo" :to-equal match)
      (expect 1 :to-equal start)
      (expect 4 :to-equal end)
      (expect nil :to-equal captures))
    (expect t :to-equal (nshell.user:|regex-match-p| "foo" "xfoo"))
    (expect nil :to-equal (nshell.user:|regex-match-p| "z" "xfoo"))
    (expect "$1b$1" :to-equal
            (nshell.user:|regex-replace| "a" "$1" "aba" :all-p t))
    (let ((caught nil))
      (handler-case
          (nshell.user:|regex-match-p| "(" "")
        (nshell.application:value-conversion-error (condition)
          (setf caught condition)))
      (expect caught :to-be-truthy)
      (expect :regex-match-p :to-equal
              (nshell.application:value-conversion-error-operation caught))
      (expect "(" :to-equal
              (nshell.application:value-conversion-error-input caught))
      (expect (typep (nshell.application:value-conversion-error-cause caught)
                     'cl-regex-kit:regex-syntax-error) :to-be-truthy)))
  (it "splits, joins, and replaces strings with literal separators"
    (expect '("a" "b" "a") :to-equal
            (nshell.user:|split-string| "a.b.a" "."))
    (expect '("" "a" "" "") :to-equal
            (nshell.user:|split-string| ",a,," ","))
    (expect '("a") :to-equal
            (nshell.user:|split-string| ",a,," "," :omit-empty-p t))
    (expect "a.b" :to-equal
            (nshell.user:|join-strings| '("a" "b") "."))
    (expect "a$&b$&a" :to-equal
            (nshell.user:|replace-string| "a.b.a" "." "$&" :all-p t))
    (expect (lambda () (nshell.user:|from-json| (read-from-string "3")))
            :to-throw 'type-error)
    (expect (lambda () (nshell.user:|join-strings| '("a" 1) ","))
            :to-throw 'type-error)
    (let ((caught nil))
      (handler-case
          (nshell.user:|to-json| :unsupported)
        (type-error (condition)
          (setf caught condition)))
      (expect caught :to-be-truthy)
      (expect nil :to-equal
              (typep :unsupported (type-error-expected-type caught)))
      (expect t :to-equal
              (typep '("valid") (type-error-expected-type caught))))
    (let ((caught nil)
          (value (cons "a" "tail")))
      (handler-case
          (nshell.user:|join-strings| value ",")
        (type-error (condition)
          (setf caught condition)))
      (expect caught :to-be-truthy)
      (expect nil :to-equal
              (typep value (type-error-expected-type caught)))
      (expect t :to-equal
              (typep '("valid") (type-error-expected-type caught))))))
