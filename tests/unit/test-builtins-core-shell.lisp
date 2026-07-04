(in-package #:nshell/test)
(in-suite builtin-tests)

(test read-stores-stdin-line-in-current-environment
  "read consumes one stdin line and stores it as a shell variable."
  (with-builtins-context (context)
    (with-input-from-string (*standard-input* (format nil "hello world~%"))
      (multiple-value-bind (output code) (call-builtin context "read" '("answer"))
        (is (null output))
        (is (= 0 code))))
    (is (string= "hello world"
                 (nshell.domain.environment:env-get
                  (nshell.application:shell-context-environment context)
                  "answer")))))

(test set-supports-fish-style-options-and-multiple-values
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
      (is (string= "one two"
                   (nshell.domain.environment:env-get env "NSHELL_TEST_EXPORTED")))
      (is (equal '("one" "two")
                 (nshell.domain.environment:env-get-values env "NSHELL_TEST_EXPORTED")))
      (is (string= "alpha beta"
                   (nshell.domain.environment:env-get env "NSHELL_TEST_LOCAL")))
      (is (equal '("alpha" "beta")
                 (nshell.domain.environment:env-get-values env "NSHELL_TEST_LOCAL")))
      (is (string= ""
                   (nshell.domain.environment:env-get env "NSHELL_TEST_EMPTY")))
      (is (null (nshell.domain.environment:env-get-values env "NSHELL_TEST_EMPTY")))
      (is (equal '("NSHELL_TEST_EXPORTED" . "one two")
                 (assoc "NSHELL_TEST_EXPORTED"
                        (nshell.domain.environment:env-list env)
                        :test #'string=))))
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
      (is (null (nshell.domain.environment:env-get env "NSHELL_TEST_EXPORTED")))
      (is (null (nshell.domain.environment:env-get env "NSHELL_TEST_LOCAL")))
      (is (null (nshell.domain.environment:env-get env "NSHELL_TEST_EMPTY"))))))

(test alias-adds-lists-queries-and-erases-expansions
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

(test alias-accepts-inline-name-value-assignment
  "alias accepts the familiar name=value form while preserving remaining tokens."
  (with-builtins-context (context)
    (multiple-value-bind (output code)
        (call-builtin context "alias" '("gs=git" "status" "--short"))
      (is (null output))
      (is (= 0 code)))
    (is (string= "git status --short"
                 (gethash "gs"
                          (nshell.application:shell-context-alias-table
                           context))))))

(test source-expands-multi-token-aliases-from-context
  "source execution expands aliases before dispatching commands."
  (with-builtins-context (context)
    (call-builtin context "alias" '("say" "echo" "from" "alias"))
    (with-called-source (output code context '("say script"))
      (is (= 0 code))
      (is (string= (format nil "from alias script~%") output)))))

(test abbr-adds-lists-queries-and-erases-expansions
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

(test abbr-accepts-fish-style-long-options
  "abbr accepts long option names for add, query, list, show, and erase."
  (with-builtins-context (context)
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("--add" "gst" "git" "status")))))
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("--query" "gst")))))
    (multiple-value-bind (output code) (call-builtin context "abbr" '("--list"))
      (is (= 0 code))
      (is (search "gst" output))
      (is (not (search "git status" output))))
    (multiple-value-bind (output code) (call-builtin context "abbr" '("--show"))
      (is (= 0 code))
      (is (search "abbr -a gst git status" output)))
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("--erase" "gst")))))
    (is (= 1 (nth-value 1 (call-builtin context "abbr"
                                         '("--query" "gst")))))))

(test abbr-adds-position-scoped-expansions
  "abbr stores optional fish-style position metadata for expansion-time checks."
  (with-builtins-context (context)
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("--add" "--position" "command"
                                           "gco" "git" "checkout")))))
    (let ((value (gethash "gco"
                          (nshell.application:shell-context-abbreviation-table
                           context))))
      (is (nshell.domain.abbreviation:abbreviation-p value))
      (is (string= "git checkout"
                   (nshell.domain.abbreviation:abbreviation-expansion value)))
      (is (eq :command
              (nshell.domain.abbreviation:abbreviation-position value))))
    (multiple-value-bind (output code) (call-builtin context "abbr" '("--show"))
      (is (= 0 code))
      (is (search "abbr -a --position command gco git checkout" output)))
    (is (= 0 (nth-value 1 (call-builtin context "abbr"
                                         '("-a" "-p" "anywhere"
                                           "gst" "git" "status")))))
    (multiple-value-bind (output code) (call-builtin context "abbr" '("--show"))
      (is (= 0 code))
      (is (search "abbr -a --position anywhere gst git status" output)))))

(test abbr-rejects-invalid-position-option
  "abbr rejects missing or unknown --position values."
  (with-builtins-context (context)
    (multiple-value-bind (output code)
        (call-builtin context "abbr" '("-a" "--position" "middle"
                                       "gco" "git" "checkout"))
      (is (= 2 code))
      (is (search "command or anywhere" output)))
    (multiple-value-bind (output code)
        (call-builtin context "abbr" '("-a" "-p"))
      (is (= 2 code))
      (is (search "requires" output)))))

(test split-alias-assignment-extracts-name-and-value
  "split-alias-assignment splits NAME=VALUE into (values NAME VALUE); nil for no equals or empty name."
  (flet ((split (arg)
           (multiple-value-list (nshell.application::%split-alias-assignment arg))))
    (is (equal '("ll" "ls -l") (split "ll=ls -l")))
    (is (equal '("gs" "git status") (split "gs=git status")))
    (is (null (first (split "noequalssign"))))
    (is (null (first (split "=value"))))))

(test abbr-parse-position-maps-known-strings
  "abbr-parse-position returns keyword for 'command'/'anywhere', nil for unknowns."
  (flet ((pos (s) (nshell.application::%abbr-parse-position s)))
    (is (eq :command (pos "command")))
    (is (eq :anywhere (pos "anywhere")))
    (is (null (pos "unknown")))
    (is (null (pos "")))))

(test string-join-concatenates-items-with-separator
  "string-join produces the standard separator-delimited string."
  (flet ((join (items sep)
           (nshell.application::%string-join items sep)))
    (is (string= ""      (join nil "")))
    (is (string= "a"     (join '("a") ",")))
    (is (string= "a,b,c" (join '("a" "b" "c") ",")))
    (is (string= "a b"   (join '("a" "b") " ")))))

(test path-separator-p-detects-unix-slash
  "path-separator-p returns true only for / on Unix."
  (flet ((sep (ch) (nshell.domain.completion:path-separator-p ch)))
    (is (sep #\/))
    (is (not (sep #\\)))
    (is (not (sep #\:)))))

(test command-has-directory-p-detects-slash-in-name
  "command-has-directory-p returns the index of / in the command name."
  (flet ((has (s)
           (nshell.domain.completion:command-prefix-has-directory-p s)))
    (is (null (has "git")))
    (is (not (null (has "./git"))))
    (is (not (null (has "/usr/bin/git"))))))

(test split-path-splits-on-colon-delimiters
  "split-path splits a colon-separated PATH string."
  (flet ((sp (s) (nshell.domain.completion:split-path s)))
    (is (equal '("/bin" "/usr/bin") (sp "/bin:/usr/bin")))
    (is (equal '("/bin") (sp "/bin")))
    (is (equal '("" "/bin") (sp ":/bin")))))

(test join-path-name-forms-directory-slash-command
  "join-path-name joins directory and command with / handling existing trailing slash."
  (flet ((join (dir cmd)
           (nshell.domain.completion:join-directory-command
            dir cmd :empty-directory "")))
    (is (string= "git"          (join "" "git")))
    (is (string= "/bin/git"     (join "/bin/" "git")))
    (is (string= "/bin/git"     (join "/bin" "git")))))
