(in-package #:nshell/test)

(describe "builtin-tests"
  (it "read-stores-stdin-line-in-current-environment"
    "read consumes one stdin line and stores it as a shell variable."
    (with-builtins-context (context)
      (with-input-from-string (*standard-input* (format nil "hello world~%"))
        (multiple-value-bind (output code) (call-builtin context "read" '("answer"))
          (expect output :to-be-null)
          (expect 0 :to-equal code)))
      (expect "hello world" :to-equal (nshell.domain.environment:env-get
                    (nshell.application:shell-context-environment context)
                    "answer"))))

  (it "read-supports-prompts-and-reports-invalid-input"
    "read emits its prompt, rejects missing arguments, and returns one at EOF."
    (with-builtins-context (context)
      (let ((prompt-output
              (with-output-to-string (stream)
                (let ((*standard-output* stream))
                  (with-input-from-string (*standard-input* (format nil "value~%"))
                    (assert-builtin-call (context "read"
                                                   '("-p" "answer: " "reply"))
                      :code 0
                      :output-null t))))))
        (expect "answer: " :to-equal prompt-output))
      (assert-builtin-call (context "read" nil)
        :code 1
        :contains '("read: usage:"))
      (assert-builtin-call (context "read" '("-p"))
        :code 2
        :contains '("read: -p requires a prompt"))
      (with-input-from-string (*standard-input* "")
        (assert-builtin-call (context "read" '("eof"))
          :code 1
          :output-null t))))

  (it "export-and-set-report-missing-or-unsupported-options"
    "Builtin option errors retain their distinct usage and required-argument statuses."
    (with-builtins-context (context)
      (assert-builtin-call (context "export" nil)
        :code 1
        :contains '("export: usage:"))
      (assert-builtin-cases (context "set")
        (("-e")
         :code 2
         :contains '("set: -e requires a name"))
        (("-q")
         :code 2
         :contains '("set: -q requires a name"))
        (("-x")
         :code 1
         :contains '("set: usage:"))
        (("-o" "pipefail" "extra")
         :code 1
         :contains '("set: usage:")))))

  (it "environment-builtins-reject-invalid-identifiers-and-options"
    "Environment builtins expose stable diagnostics for invalid names and options."
    (with-builtins-context (context)
      (assert-builtin-call (context "export" '("--" "NSHELL_EXPORT_AFTER_TERMINATOR=ok"))
        :code 0
        :output-null t)
      (assert-builtin-call (context "export" '("bad-name"))
        :code 2
        :contains '("export: invalid identifier:"))
      (assert-builtin-call (context "unset" '("--verbose"))
        :code 2
        :contains '("unset: usage:"))
      (assert-builtin-call (context "unset" '("bad-name"))
        :code 2
        :contains '("unset: invalid identifier:"))
      (assert-builtin-call (context "set" '("--unknown"))
        :code 1
        :contains '("set: usage:"))))

  (it "export-parsers-accept-valid-identifiers-and-split-values"
    "Export's small parsers keep identifier validation and assignment parsing deterministic."
    (dolist (name '("A" "_private" "A1" "A_B"))
      (expect (nshell.application::%shell-variable-name-p name)
              :to-be-truthy))
    (dolist (name '("" "1A" "A-B" "A.B" nil))
      (expect (nshell.application::%shell-variable-name-p name)
              :to-be-falsy))
    (multiple-value-bind (name value assignment-p)
        (nshell.application::%export-assignment "NAME=value=with=equals")
      (expect "NAME" :to-equal name)
      (expect "value=with=equals" :to-equal value)
      (expect assignment-p :to-be-truthy))
    (multiple-value-bind (name value assignment-p)
        (nshell.application::%export-assignment "NAME")
      (expect "NAME" :to-equal name)
      (expect value :to-be-null)
      (expect assignment-p :to-be-falsy)))

  (it "export-marks-existing-variable-in-current-environment"
    "export marks an existing shell variable for process environments."
    (with-builtins-context (context)
      (assert-builtin-call (context "set" '("NSHELL_EXPORT_ME" "visible"))
        :code 0
        :output-null t)
      (assert-builtin-call (context "export" '("NSHELL_EXPORT_ME"))
        :code 0
        :output-null t)
      (let ((entry (find "NSHELL_EXPORT_ME"
                         (nshell.domain.environment:env-list
                          (nshell.application:shell-context-environment context))
                         :key #'nshell.domain.environment:env-entry-name
                         :test #'string=)))
        (expect (nshell.domain.environment:env-entry-p entry) :to-be-truthy)
        (expect "visible" :to-equal (nshell.domain.environment:env-entry-value entry)))))

  (it "export-accepts-assignments-and-multiple-names"
    "export accepts NAME=value assignments and several names in one invocation."
    (with-builtins-context (context)
      (assert-builtin-call (context "export"
                                    '("NSHELL_EXPORT_ONE=one"
                                      "NSHELL_EXPORT_TWO"
                                      "NSHELL_EXPORT_THREE=three"))
        :code 0
        :output-null t)
      (let ((environment (nshell.application:shell-context-environment context)))
        (expect "one" :to-equal
                (nshell.domain.environment:env-get environment "NSHELL_EXPORT_ONE"))
        (expect "" :to-equal
                (nshell.domain.environment:env-get environment "NSHELL_EXPORT_TWO"))
        (expect "three" :to-equal
                (nshell.domain.environment:env-get environment "NSHELL_EXPORT_THREE"))
        (dolist (name '("NSHELL_EXPORT_ONE"
                        "NSHELL_EXPORT_TWO"
                        "NSHELL_EXPORT_THREE"))
          (expect (nshell.domain.environment:env-exported-p environment name)
                  :to-be-truthy)))))

  (it "unset-removes-multiple-shell-variables"
    "unset removes several variables and accepts the option terminator."
    (with-builtins-context (context)
      (assert-builtin-call (context "set" '("NSHELL_UNSET_ONE" "one"))
        :code 0
        :output-null t)
      (assert-builtin-call (context "set" '("NSHELL_UNSET_TWO" "two"))
        :code 0
        :output-null t)
      (assert-builtin-call (context "unset"
                                    '("--" "NSHELL_UNSET_ONE" "NSHELL_UNSET_TWO"))
        :code 0
        :output-null t)
      (let ((environment (nshell.application:shell-context-environment context)))
        (expect (nshell.domain.environment:env-defined-p environment "NSHELL_UNSET_ONE")
                :to-be-falsy)
        (expect (nshell.domain.environment:env-defined-p environment "NSHELL_UNSET_TWO")
                :to-be-falsy))))

  (it "set-supports-fish-style-options-and-multiple-values"
    "set supports fish-style export, erase, query, listing, and multi-token values."
    (with-builtins-context (context)
      (assert-builtin-cases (context "set")
        (("--export" "NSHELL_TEST_EXPORTED" "one" "two")
         :code 0
         :output-null t)
        (("NSHELL_TEST_LOCAL" "alpha" "beta")
         :code 0
         :output-null t)
        (("NSHELL_TEST_EMPTY")
         :code 0
         :output-null t))
      (let ((env (nshell.application:shell-context-environment context)))
        (expect "one two" :to-equal (nshell.domain.environment:env-get env "NSHELL_TEST_EXPORTED"))
        (expect '("one" "two") :to-equal (nshell.domain.environment:env-get-values env "NSHELL_TEST_EXPORTED"))
        (expect "alpha beta" :to-equal (nshell.domain.environment:env-get env "NSHELL_TEST_LOCAL"))
        (expect '("alpha" "beta") :to-equal (nshell.domain.environment:env-get-values env "NSHELL_TEST_LOCAL"))
        (expect "" :to-equal (nshell.domain.environment:env-get env "NSHELL_TEST_EMPTY"))
        (expect (nshell.domain.environment:env-get-values env "NSHELL_TEST_EMPTY") :to-be-null)
        (let ((entry (find "NSHELL_TEST_EXPORTED"
                           (nshell.domain.environment:env-list env)
                           :key #'nshell.domain.environment:env-entry-name
                           :test #'string=)))
          (expect (nshell.domain.environment:env-entry-p entry) :to-be-truthy)
          (expect "one two" :to-equal (nshell.domain.environment:env-entry-value entry))))
      (assert-builtin-cases (context "set")
        (("--query" "NSHELL_TEST_EXPORTED" "NSHELL_TEST_LOCAL")
         :code 0
         :output-null t)
        (("--query" "NSHELL_TEST_MISSING")
         :code 1
         :output-null t)
        (nil
         :code 0
         :contains '("set -x NSHELL_TEST_EXPORTED one two"
                     "set NSHELL_TEST_LOCAL alpha beta"
                     "set NSHELL_TEST_EMPTY "))
        (("--erase"
          "NSHELL_TEST_EXPORTED"
          "NSHELL_TEST_LOCAL"
          "NSHELL_TEST_EMPTY")
         :code 0
         :output-null t))
      (let ((env (nshell.application:shell-context-environment context)))
        (expect (nshell.domain.environment:env-get env "NSHELL_TEST_EXPORTED") :to-be-null)
        (expect (nshell.domain.environment:env-get env "NSHELL_TEST_LOCAL") :to-be-null)
        (expect (nshell.domain.environment:env-get env "NSHELL_TEST_EMPTY") :to-be-null))))

  (it "set-toggles-pipefail"
    "set -o/+o pipefail toggles the pipeline policy in the current context."
    (with-builtins-context (context)
      (expect (nshell.application:shell-context-pipefail-p context) :to-be-falsy)
      (assert-builtin-call (context "set" '("-o" "pipefail"))
        :code 0
        :output-null t)
      (expect (nshell.application:shell-context-pipefail-p context) :to-be-truthy)
      (assert-builtin-call (context "set" '("+o" "pipefail"))
        :code 0
        :output-null t)
      (expect (nshell.application:shell-context-pipefail-p context) :to-be-falsy)))

  (it "alias-adds-lists-queries-and-erases-expansions"
    "alias stores fish-style multi-token command expansions in the current context."
    (with-builtins-context (context)
      (assert-fish-style-table-builtin-roundtrip
          (context "alias" (nshell.application:shell-context-alias-table context)
                   "ll" "ls -l /tmp" '("ll" "ls" "-l" "/tmp")
                   "alias ll=ls -l /tmp"
                   "alias: -e requires a name
"
                   '("-e" "ll")
                   "missing"))))

  (it "alias-accepts-inline-name-value-assignment"
    "alias accepts the familiar name=value form while preserving remaining tokens."
    (with-builtins-context (context)
      (multiple-value-bind (output code)
          (call-builtin context "alias" '("gs=git" "status" "--short"))
        (expect output :to-be-null)
        (expect 0 :to-equal code))
      (expect "git status --short" :to-equal (gethash "gs"
                            (nshell.application:shell-context-alias-table
                             context)))))

  (it "alias-reports-invalid-empty-expansions"
    "alias rejects an assignment whose name or expansion is empty."
    (with-builtins-context (context)
      (assert-builtin-call (context "alias" '("ll="))
        :code 1
        :contains '("alias: usage: alias name expansion..."))))

  (it "alias-queries-a-single-name-without-assignment"
    "A single non-assignment argument queries one stored alias by name."
    (with-builtins-context (context)
      (assert-builtin-call (context "alias" '("ll" "ls"))
        :code 0
        :output-null t)
      (assert-builtin-call (context "alias" '("ll"))
        :code 0
        :output (format nil "alias ll=ls~%"))
      (assert-builtin-call (context "alias" '("missing"))
        :code 1
        :output-empty t)))

  (it "source-expands-multi-token-aliases-from-context"
    "source execution expands aliases before dispatching commands."
    (with-builtins-context (context)
      (call-builtin context "alias" '("say" "echo" "from" "alias"))
      (with-called-source (output code context '("say script"))
        (expect 0 :to-equal code)
        (expect (format nil "from alias script~%") :to-equal output))))

  (it "abbr-adds-lists-queries-and-erases-expansions"
    "abbr stores fish-style multi-token expansions in the current shell context."
    (with-builtins-context (context)
      (assert-fish-style-table-builtin-roundtrip
          (context "abbr" (nshell.application:shell-context-abbreviation-table context)
                   "gco" "git checkout" '("-a" "gco" "git" "checkout")
                   "abbr -a gco git checkout"
                   "abbr: -e requires a name
"
                   '("-e" "gco")
                   "missing"))))

  (it "abbr-accepts-fish-style-long-options"
    "abbr accepts long option names for add, query, list, show, and erase."
    (with-builtins-context (context)
      (expect 0 :to-equal (nth-value 1 (call-builtin context "abbr"
                                           '("--add" "gst" "git" "status"))))
      (expect 0 :to-equal (nth-value 1 (call-builtin context "abbr"
                                           '("--query" "gst"))))
      (multiple-value-bind (output code) (call-builtin context "abbr" '("--list"))
        (expect 0 :to-equal code)
        (expect (search "gst" output) :to-be-truthy)
        (expect (search "git status" output) :to-be-falsy))
      (multiple-value-bind (output code) (call-builtin context "abbr" '("--show"))
        (expect 0 :to-equal code)
        (expect (search "abbr -a gst git status" output) :to-be-truthy))
      (expect 0 :to-equal (nth-value 1 (call-builtin context "abbr"
                                           '("--erase" "gst"))))
      (expect 1 :to-equal (nth-value 1 (call-builtin context "abbr"
                                           '("--query" "gst"))))))

  (it "abbr-adds-position-scoped-expansions"
    "abbr stores optional fish-style position metadata for expansion-time checks."
    (with-builtins-context (context)
      (expect 0 :to-equal (nth-value 1 (call-builtin context "abbr"
                                           '("--add" "--position" "command"
                                             "gco" "git" "checkout"))))
      (let ((value (gethash "gco"
                            (nshell.application:shell-context-abbreviation-table
                             context))))
        (expect (nshell.domain.abbreviation:abbreviation-p value) :to-be-truthy)
        (expect "git checkout" :to-equal (nshell.domain.abbreviation:abbreviation-expansion value))
        (expect :command :to-be (nshell.domain.abbreviation:abbreviation-position value)))
      (multiple-value-bind (output code) (call-builtin context "abbr" '("--show"))
        (expect 0 :to-equal code)
        (expect (search "abbr -a --position command gco git checkout" output) :to-be-truthy))
      (expect 0 :to-equal (nth-value 1 (call-builtin context "abbr"
                                           '("-a" "-p" "anywhere"
                                             "gst" "git" "status"))))
      (multiple-value-bind (output code) (call-builtin context "abbr" '("--show"))
        (expect 0 :to-equal code)
        (expect (search "abbr -a --position anywhere gst git status" output) :to-be-truthy))))

  (it "abbr-rejects-invalid-position-option"
    "abbr rejects missing or unknown --position values."
    (with-builtins-context (context)
      (multiple-value-bind (output code)
          (call-builtin context "abbr" '("-a" "--position" "middle"
                                         "gco" "git" "checkout"))
        (expect 2 :to-equal code)
        (expect (search "command or anywhere" output) :to-be-truthy))
      (multiple-value-bind (output code)
          (call-builtin context "abbr" '("-a" "-p"))
        (expect 2 :to-equal code)
        (expect (search "requires" output) :to-be-truthy))))

  (it "abbr-reports-incomplete-add-arguments"
    "abbr requires both a name and an expansion after -a."
    (with-builtins-context (context)
      (assert-builtin-call (context "abbr" '("-a" "name"))
        :code 2
        :contains '("abbr: usage:"))))

  (it "abbr-reports-unknown-options"
    "abbr rejects options outside its supported fish-style command surface."
    (with-builtins-context (context)
      (assert-builtin-call (context "abbr" '("--bogus"))
        :code 1
        :contains '("abbr: usage:"))))

  (it "function-erase-clears-stored-source-body"
    "function -e removes generated body and original source table entry together."
    (with-builtins-context (context)
      (let ((function-table (nshell.application:shell-context-function-table context))
            (source-table (nshell.application:shell-context-function-source-table context)))
        (setf (gethash "greet" function-table) '("echo hi")
              (gethash "greet" source-table) "function greet; echo source; end")
        (assert-builtin-call (context "function" '("-e" "greet"))
          :code 0
          :output-null t)
        (expect (nth-value 1 (gethash "greet" function-table)) :to-be-falsy)
        (expect (nth-value 1 (gethash "greet" source-table)) :to-be-falsy))))

  (it "split-alias-assignment-extracts-name-and-value"
    "split-alias-assignment splits NAME=VALUE into (values NAME VALUE); nil for no equals or empty name."
    (flet ((split (arg)
             (multiple-value-list (nshell.application::%split-alias-assignment arg))))
      (expect '("ll" "ls -l") :to-equal (split "ll=ls -l"))
      (expect '("gs" "git status") :to-equal (split "gs=git status"))
      (expect (first (split "noequalssign")) :to-be-null)
      (expect (first (split "=value")) :to-be-null)))

  (it "table-builtin-case-evaluates-arguments-once"
    "table builtin dispatch evaluates its argument form once before selecting a clause."
    (let ((evaluations 0))
      (expect :empty
              :to-be
              (nshell.application::%table-builtin-case
                  (progn (incf evaluations) nil)
                (:empty :empty)
                (:default :default)))
      (expect 1 :to-equal evaluations)))

  (it "abbr-parse-position-maps-known-strings"
    "abbr-parse-position returns keyword for 'command'/'anywhere', nil for unknowns."
    (flet ((pos (s) (nshell.application::%abbr-parse-position s)))
      (expect :command :to-be (pos "command"))
      (expect :anywhere :to-be (pos "anywhere"))
      (expect (pos "unknown") :to-be-null)
      (expect (pos "") :to-be-null)))

  (it "string-join-concatenates-items-with-separator"
    "string-join produces the standard separator-delimited string."
    (flet ((join (items sep)
             (nshell.application::%string-join items sep)))
      (expect "" :to-equal (join nil ""))
      (expect "a" :to-equal (join '("a") ","))
      (expect "a,b,c" :to-equal (join '("a" "b" "c") ","))
      (expect "a b" :to-equal (join '("a" "b") " "))))

  (it "builtin-option-helpers-cover-common-cli-flag-shape"
    "Builtin option helpers centralize string flag matching and option token detection."
    (expect (nshell.application::%builtin-option-p "-q" '("-q" "--query")) :to-be-truthy)
    (expect (nshell.application::%builtin-option-p "--query" '("-q" "--query")) :to-be-truthy)
    (expect (nshell.application::%builtin-option-p "-x" '("-q" "--query")) :to-be-falsy)
    (expect (nshell.application::%builtin-option-like-p "-q") :to-be-truthy)
    (expect (nshell.application::%builtin-option-like-p "--query") :to-be-truthy)
    (expect (nshell.application::%builtin-option-like-p "-") :to-be-falsy)
    (expect (nshell.application::%builtin-option-like-p "name") :to-be-falsy)
    (expect (nshell.application::%builtin-option-like-p nil) :to-be-falsy)))
