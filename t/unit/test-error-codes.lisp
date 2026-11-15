(in-package #:nshell/test)

(describe "error-codes-tests"
  (it "error-code-names-are-unique-and-match-their-kind"
    "E_ names are errors, W_ names are warnings, and no name appears twice."
    (let ((names (mapcar #'nshell.domain.error-codes:error-code-name
                         nshell.domain.error-codes:+error-codes+)))
      (expect (length (remove-duplicates names :test #'string=))
              :to-equal (length names))
      (dolist (entry nshell.domain.error-codes:+error-codes+)
        (let ((name (nshell.domain.error-codes:error-code-name entry)))
          (expect (list name (nshell.domain.error-codes:error-code-kind entry))
                  :to-equal
                  (list name
                        (cond ((eql 0 (search "E_" name)) :error)
                              ((eql 0 (search "W_" name)) :warning)
                              (t :unknown-prefix))))))))

  (it "error-code-exit-codes-follow-the-design-table"
    "Each E_ code has exactly the default exit status of L6 6.5; warnings have none."
    (let ((expected
            '(("E_PARSE" . 2) ("E_UNSUPPORTED_SYNTAX" . 2) ("E_PROTOCOL" . 2)
              ("E_ARG_TYPE" . 1) ("E_VALUE_POSITION" . 1) ("E_NO_MATCH" . 1)
              ("E_REDIRECT_TARGET" . 1) ("E_LISP_ERROR" . 1)
              ("E_NOT_IMPLEMENTED" . 1)
              ("E_COMMAND_FAILED" . :child)
              ("E_COMMAND_NOT_FOUND" . 127) ("E_PERMISSION" . 126)
              ("E_TIMEOUT" . 124) ("E_INTERRUPTED" . 130)
              ("E_NEEDS_APPROVAL" . 3) ("E_BLOCKED_BY_POLICY" . 4)
              ("E_WAITING_FOR_INPUT" . 5) ("E_INTERACTIVE_PROGRAM" . 6)
              ("E_INTERNAL" . 70))))
      (expect
       (loop for entry in nshell.domain.error-codes:+error-codes+
             when (eq :error (nshell.domain.error-codes:error-code-kind entry))
               collect (cons (nshell.domain.error-codes:error-code-name entry)
                             (nshell.domain.error-codes:error-code-exit-code entry)))
       :to-equal expected)
      (dolist (entry nshell.domain.error-codes:+error-codes+)
        (when (eq :warning (nshell.domain.error-codes:error-code-kind entry))
          (expect (nshell.domain.error-codes:error-code-exit-code entry)
                  :to-be-null)))
      (expect (nshell.domain.error-codes:error-code-exit-code
               (nshell.domain.error-codes:find-error-code "E_TIMEOUT"))
              :to-equal 124)
      (expect (nshell.domain.error-codes:find-error-code "E_NO_SUCH_CODE")
              :to-be-null)))

  (it "error-code-table-lists-every-required-code"
    "All 19 E_ codes and the 12 v0.8 W_ codes are defined, and nothing else."
    (let ((required
            '("E_PARSE" "E_UNSUPPORTED_SYNTAX" "E_PROTOCOL" "E_ARG_TYPE"
              "E_VALUE_POSITION" "E_NO_MATCH" "E_REDIRECT_TARGET" "E_LISP_ERROR"
              "E_NOT_IMPLEMENTED" "E_COMMAND_FAILED" "E_COMMAND_NOT_FOUND"
              "E_PERMISSION" "E_TIMEOUT" "E_INTERRUPTED" "E_NEEDS_APPROVAL"
              "E_BLOCKED_BY_POLICY" "E_WAITING_FOR_INPUT"
              "E_INTERACTIVE_PROGRAM" "E_INTERNAL"
              "W_RESOLUTION_ORDER" "W_VALUE_POSITION" "W_KEYWORD_ARGUMENT"
              "W_MID_WORD_SPECIAL" "W_BRACE_EXPANSION" "W_LIST_SPLICE"
              "W_STATUS_AS_VALUE" "W_DEFUN_WORD_ARGS" "W_NO_MATCH"
              "W_REDEFINITION" "W_BARE_LINE_UNQUOTE" "W_NAME_CONFLICT")))
      (expect (length required) :to-equal 31)
      (expect (mapcar #'nshell.domain.error-codes:error-code-name
                      nshell.domain.error-codes:+error-codes+)
              :to-equal required)))

  (it "error-code-mixin-carries-the-code-of-each-condition"
    "Each condition that mixes in the error code reports a code from the table."
    (dolist (spec '((nshell.domain.parsing::sexp-reader-error "E_PARSE")
                    (nshell.application::sexp-evaluation-syntax-error "E_PARSE")
                    (nshell.application::command-macro-syntax-error "E_PARSE")
                    (nshell.application::command-failed "E_COMMAND_FAILED")
                    (nshell.application::command-argument-type-error "E_ARG_TYPE")
                    (nshell.application::value-conversion-error "E_LISP_ERROR")
                    (nshell.application::wp-interface-not-implemented
                     "E_NOT_IMPLEMENTED")
                    (nshell.infrastructure.terminal::terminal-mode-operation-failed
                     "E_INTERNAL")))
      (destructuring-bind (type code) spec
        (let ((condition (make-condition type)))
          (expect (list type (typep condition 'error)) :to-equal (list type t))
          (expect (list type
                        (nshell.domain.error-codes:condition-error-code condition))
                  :to-equal (list type code))
          (expect (nshell.domain.error-codes:find-error-code code)
                  :to-be-truthy)))))

  (it "error-code-table-reads-without-evaluation"
    "READ-ERROR-CODE-TABLE, which the generator uses, yields the loaded table."
    (expect (nshell.domain.error-codes:read-error-code-table
             (merge-pathnames "data/domain/error-codes-data.lisp"
                              (uiop:pathname-directory-pathname
                               (asdf:system-source-file (asdf:find-system "nshell")))))
            :to-equal nshell.domain.error-codes:+error-codes+))

  (it "error-code-reference-page-matches-the-table"
    "docs/src/reference/error-codes.md is exactly what the generator renders."
    (let* ((root (uiop:pathname-directory-pathname
                  (asdf:system-source-file (asdf:find-system "nshell"))))
           (committed
             (uiop:read-file-string
              (merge-pathnames "docs/src/reference/error-codes.md" root)
              :external-format :utf-8))
           (rendered (nshell.domain.error-codes:render-error-codes-markdown
                      (nshell.domain.error-codes:read-error-code-table
                       (merge-pathnames "data/domain/error-codes-data.lisp" root)))))
      (expect (if (string= committed rendered)
                  :up-to-date
                  "docs/src/reference/error-codes.md is stale: run sbcl --script scripts/generate-error-codes-doc.lisp")
              :to-equal :up-to-date))))
