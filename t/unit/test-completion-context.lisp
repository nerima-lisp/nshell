(in-package #:nshell/test)

(describe "completion-rules-tests"
  (it "completion-context-for-escaped-space-keeps-logical-argument-prefix"
    (let ((context (nshell.domain.completion:completion-context-for "git ch\\ file")))
      (expect "git" :to-equal (nshell.domain.completion:completion-context-command context))
      (expect "ch file" :to-equal (nshell.domain.completion:completion-context-argument-prefix context))
      (expect (nshell.domain.completion:completion-context-command-position-p context) :to-be-falsy)
      (expect (nshell.domain.completion:completion-context-redirection-target-p context) :to-be-null)))

  (it "completion-context-for-double-quoted-backslash-space-keeps-literal-prefix"
    (let ((context (nshell.domain.completion:completion-context-for "git \"ch\\ ")))
      (expect "git" :to-equal (nshell.domain.completion:completion-context-command context))
      (expect "ch\\ " :to-equal (nshell.domain.completion:completion-context-argument-prefix context))
      (expect (nshell.domain.completion:completion-context-command-position-p context) :to-be-falsy)
      (expect (nshell.domain.completion:completion-context-redirection-target-p context) :to-be-null)))

  (it "completion-context-for-leading-assignment-words-uses-real-command"
    (let ((context (nshell.domain.completion:completion-context-for "FOO=bar git ch")))
      (expect "git" :to-equal (nshell.domain.completion:completion-context-command context))
      (expect "ch" :to-equal (nshell.domain.completion:completion-context-argument-prefix context))
      (expect '("ch") :to-equal (nshell.domain.completion:completion-context-argument-words context))
      (expect (nshell.domain.completion:completion-context-command-position-p context) :to-be-falsy)
      (expect (nshell.domain.completion:completion-context-redirection-target-p context) :to-be-null)))

  (it "completion-context-for-leading-assignment-command-prefix-stays-command-position"
    (let ((context (nshell.domain.completion:completion-context-for "FOO=bar gi")))
      (expect "gi" :to-equal (nshell.domain.completion:completion-context-command context))
      (expect "" :to-equal (nshell.domain.completion:completion-context-argument-prefix context))
      (expect '() :to-equal (nshell.domain.completion:completion-context-argument-words context))
      (expect (nshell.domain.completion:completion-context-command-position-p context) :to-be-truthy)
      (expect (nshell.domain.completion:completion-context-redirection-target-p context) :to-be-null)))

  (it "completion-context-for-respects-command-separators"
    (dolist (case '(("echo ignored && git ch" "git" "ch")
                    ("echo ignored || git ch" "git" "ch")
                    ("echo ignored ; git ch" "git" "ch")
                    ("echo ignored & git ch" "git" "ch")))
      (destructuring-bind (line expected-command expected-prefix) case
        (let ((context (nshell.domain.completion:completion-context-for line)))
          (expect expected-command :to-equal (nshell.domain.completion:completion-context-command context))
          (expect expected-prefix :to-equal (nshell.domain.completion:completion-context-argument-prefix context))
          (expect (list expected-prefix) :to-equal (nshell.domain.completion:completion-context-argument-words context))
          (expect (nshell.domain.completion:completion-context-command-position-p context) :to-be-falsy)
          (expect (nshell.domain.completion:completion-context-redirection-target-p context) :to-be-null)))))

  (it "completion-context-keeps-segment-local-argument-words"
    (let ((context (nshell.domain.completion:completion-context-for
                    "FOO=bar git --color a")))
      (expect "git" :to-equal (nshell.domain.completion:completion-context-command context))
      (expect "a" :to-equal (nshell.domain.completion:completion-context-argument-prefix context))
      (expect '("--color" "a") :to-equal (nshell.domain.completion:completion-context-argument-words context))))

  (it "completion-context-argument-words-respect-command-separators"
    (let ((context (nshell.domain.completion:completion-context-for
                    "echo ignored; kubectl -o ")))
      (expect "kubectl" :to-equal (nshell.domain.completion:completion-context-command context))
      (expect "" :to-equal (nshell.domain.completion:completion-context-argument-prefix context))
      (expect '("-o") :to-equal (nshell.domain.completion:completion-context-argument-words context))))

  (it "pbt-redirection-target-completion-does-not-leak-command-options"
    (check-property (:trials 50)
        ((suffix (gen-command-prefix :min-length 1 :max-length 8) nil)
         (stem (gen-command-prefix :min-length 1 :max-length 4) nil))
      (let* ((command (concatenate 'string "zz-nshell-" suffix))
             (option (concatenate 'string stem "-option"))
             (kb (nshell.domain.completion:make-empty-knowledge-base)))
        (nshell.domain.completion:kb-add-command kb command :flags (list option))
        (with-file-completion-adapters (nil nil)
          (let ((candidates
                  (nshell.domain.completion:complete
                   kb
                   (format nil "~a > ~a" command stem))))
            (and (= 1 (length candidates))
                 (string= stem
                          (nshell.domain.completion:candidate-text (first candidates)))
                 (eq :file
                     (nshell.domain.completion:candidate-kind (first candidates)))))))))

  (it "completion-command-position-p-classifies-word-state"
    (let ((empty (nshell.domain.completion:completion-context-for ""))
          (command (nshell.domain.completion:completion-context-for "git"))
          (argument (nshell.domain.completion:completion-context-for "git status"))
          (after-argument (nshell.domain.completion:completion-context-for "git status ")))
      (expect "" :to-equal (nshell.domain.completion:completion-context-command empty))
      (expect (nshell.domain.completion:completion-context-command-position-p empty) :to-be-truthy)
      (expect "git" :to-equal (nshell.domain.completion:completion-context-command command))
      (expect (nshell.domain.completion:completion-context-command-position-p command) :to-be-truthy)
      (expect "status" :to-equal (nshell.domain.completion:completion-context-argument-prefix argument))
      (expect (nshell.domain.completion:completion-context-command-position-p argument) :to-be-falsy)
      (expect "" :to-equal (nshell.domain.completion:completion-context-argument-prefix after-argument))
      (expect (nshell.domain.completion:completion-context-command-position-p after-argument) :to-be-falsy)))

  (it "completion-context-skips-leading-assignments-for-command-word"
    (let ((context (nshell.domain.completion:completion-context-for "FOO=bar git")))
      (expect "git" :to-equal (nshell.domain.completion:completion-context-command context))
      (expect (nshell.domain.completion:completion-context-command-position-p context) :to-be-truthy)
      (expect '() :to-equal (nshell.domain.completion:completion-context-argument-words context))))

  (it "completion-context-uses-latest-word-only-at-cursor-boundary"
    (let ((at-argument (nshell.domain.completion:completion-context-for "git status"))
          (after-argument (nshell.domain.completion:completion-context-for "git status ")))
      (expect "status" :to-equal (nshell.domain.completion:completion-context-argument-prefix at-argument))
      (expect '("status") :to-equal (nshell.domain.completion:completion-context-argument-words at-argument))
      (expect "" :to-equal (nshell.domain.completion:completion-context-argument-prefix after-argument))
      (expect '("status") :to-equal (nshell.domain.completion:completion-context-argument-words after-argument))))

  (it "completion-context-argument-words-list-is-domain-owned"
    "Completion contexts should not expose mutable aggregate storage."
    (let* ((words (list "status" "--short"))
           (context (nshell.domain.completion::%make-completion-context
                     :command "git"
                     :argument-prefix "--short"
                     :argument-words words
                     :command-position-p nil
                     :redirection-target-p nil))
           (projected
             (nshell.domain.completion:completion-context-argument-words context)))
      (setf (first words) "mutated-input")
      (setf (first projected) "mutated-projection")
      (expect '("status" "--short") :to-equal (nshell.domain.completion:completion-context-argument-words context))))

  (it "completion-context-constructors-are-internal-boundaries"
    "Completion context construction should not expose legacy unprefixed helper names."
    (flet ((defined-symbol-p (name)
             (nth-value 1 (find-symbol name '#:nshell.domain.completion))))
      (dolist (name '("%MAKE-COMPLETION-CONTEXT"
                      "%MAKE-RAW-COMPLETION-CONTEXT"
                      "%COMPLETION-CONTEXT-COMMAND"
                      "%COMPLETION-CONTEXT-ARGUMENT-PREFIX"
                      "%COMPLETION-CONTEXT-ARGUMENT-WORDS"
                      "%COMPLETION-CONTEXT-COMMAND-POSITION-P"
                      "%COMPLETION-CONTEXT-REDIRECTION-TARGET-P"
                      "%MAKE-COMPLETION-WORD"
                      "%MAKE-COMPLETION-INPUT-ANALYSIS"
                      "%STARTS-WITH-P"
                      "%WORD-LIKE-TOKEN-P"
                      "%REDIRECTION-TOKEN-P"
                      "%COMMAND-SEGMENT-TOKENS"
                      "%SHELL-COMPLETION-WORDS"
                      "%TOKEN-ENDING-BEFORE-POSITION"
                      "%REDIRECTION-TARGET-POSITION-P"
                      "%COMMAND-WORD"
                      "%ARGUMENT-WORD-VALUES-AFTER-COMMAND"
                      "%LATEST-COMPLETION-WORD"
                      "%CURRENT-COMPLETION-WORD-AT-CURSOR"
                      "%ANALYZE-COMPLETION-INPUT"
                      "%COMPLETION-COMMAND-POSITION-P"
                      "%COMPLETION-ANALYSIS-COMMAND-POSITION-P"
                      "%COMPLETION-ANALYSIS-COMMAND"
                      "%COMPLETION-ANALYSIS-ARGUMENT-PREFIX"
                      "%COMPLETION-ANALYSIS-ARGUMENT-WORDS"
                      "%COMPLETION-ANALYSIS-REDIRECTION-TARGET-P"
                      "%COMPLETION-CONTEXT-FROM-ANALYSIS"
                      "%COMPLETION-WORD-VALUE"
                      "%COMPLETION-WORD-START"
                      "%COMPLETION-WORD-END"
                      "%COMPLETION-INPUT-ANALYSIS-COMMAND-WORD"))
        (expect (fboundp (find-symbol name '#:nshell.domain.completion)) :to-be-truthy))
      (dolist (name '("MAKE-COMPLETION-CONTEXT"
                      "MAKE-COMPLETION-WORD"
                      "MAKE-COMPLETION-INPUT-ANALYSIS"
                      "COMPLETION-WORD-VALUE"
                      "COMPLETION-WORD-START"
                      "COMPLETION-WORD-END"
                      "COMPLETION-INPUT-ANALYSIS-COMMAND-WORD"))
        (expect (defined-symbol-p name) :to-be-falsy))
      (dolist (name '("STARTS-WITH-P"
                      "WORD-LIKE-TOKEN-P"
                      "REDIRECTION-TOKEN-P"
                      "COMMAND-SEGMENT-TOKENS"
                      "SHELL-COMPLETION-WORDS"
                      "TOKEN-ENDING-BEFORE-POSITION"
                      "REDIRECTION-TARGET-POSITION-P"
                      "COMMAND-WORD"
                      "ARGUMENT-WORD-VALUES-AFTER-COMMAND"
                      "LATEST-COMPLETION-WORD"
                      "CURRENT-COMPLETION-WORD-AT-CURSOR"
                      "ANALYZE-COMPLETION-INPUT"
                      "COMPLETION-COMMAND-POSITION-P"
                      "COMPLETION-ANALYSIS-COMMAND-POSITION-P"
                      "COMPLETION-ANALYSIS-COMMAND"
                      "COMPLETION-ANALYSIS-ARGUMENT-PREFIX"
                      "COMPLETION-ANALYSIS-ARGUMENT-WORDS"
                      "COMPLETION-ANALYSIS-REDIRECTION-TARGET-P"
                      "COMPLETION-CONTEXT-FROM-ANALYSIS"))
        (multiple-value-bind (symbol status)
            (find-symbol name '#:nshell.domain.completion)
          (expect (and status (fboundp symbol)) :to-be-falsy)))))

  (it "completion-query-constructor-is-internal-boundary"
    "Completion query construction should stay behind completion-query-for."
    (expect (fboundp 'nshell.domain.completion::make-completion-query) :to-be-falsy)
    (expect (fboundp 'nshell.domain.completion::%make-completion-query) :to-be-truthy))

  (it "completion-context-word-like-token-p-returns-canonical-booleans"
    (expect t :to-be (nshell.domain.completion::%word-like-token-p
               (nshell.domain.parsing:make-token :word "git")))
    (expect t :to-be (nshell.domain.completion::%word-like-token-p
               (nshell.domain.parsing:make-token :error "git")))
    (expect (nshell.domain.completion::%word-like-token-p
               (nshell.domain.parsing:make-token :pipe "|")) :to-be-null))

  (it "completion-context-starts-with-p-performs-case-insensitive-prefix-match"
    "%starts-with-p returns true when text starts with prefix (case-folded)."
    (flet ((swp (prefix text)
             (nshell.domain.completion::%starts-with-p prefix text)))
      (expect (swp "" "anything") :to-be-truthy)
      (expect (swp "git" "git checkout") :to-be-truthy)
      (expect (swp "GIT" "git checkout") :to-be-truthy)
      (expect (swp "gitx" "git") :to-be-falsy)
      (expect (swp "checkout" "git") :to-be-falsy)))

  (it "completion-context-redirection-token-p-recognizes-redirect-type"
    "%redirection-token-p returns true only for :redirect tokens."
    (flet ((redir (type)
             (nshell.domain.completion::%redirection-token-p
              (nshell.domain.parsing:make-token type ""))))
      (expect (redir :redirect) :to-be-truthy)
      (expect (redir :pipe) :to-be-falsy)
      (expect (redir :word) :to-be-falsy)
      (expect (redir :newline) :to-be-falsy)))

  (it "completion-context-command-segment-tokens-returns-tokens-after-last-separator"
    "%command-segment-tokens strips everything up to and including the last separator."
    (flet ((tokens (input)
             (nshell.domain.parsing:tokenization-result-tokens
              (nshell.domain.parsing:tokenize input))))
      (flet ((seg (input)
               (nshell.domain.completion::%command-segment-tokens
                (tokens input))))
        ;; no separator: whole token list returned
        (expect 2 :to-equal (length (seg "git checkout")))
        ;; after &&: only "git" and "ch" returned
        (expect 2 :to-equal (length (seg "echo a && git ch")))
        ;; after semicolon
        (expect 1 :to-equal (length (seg "a ; b"))))))

  (it "completion-context-shell-completion-words-merges-adjacent-word-tokens"
    "%shell-completion-words combines adjacent word-like tokens into single logical words."
    (flet ((tokens (input)
             (nshell.domain.parsing:tokenization-result-tokens
              (nshell.domain.parsing:tokenize input))))
      (flet ((words (input)
               (mapcar #'nshell.domain.completion::%completion-word-value
                       (nshell.domain.completion::%shell-completion-words
                        (tokens input)))))
        (expect '("git" "checkout") :to-equal (words "git checkout"))
        ;; pipe is not word-like so it triggers a flush
        (expect '("ls" "foo") :to-equal (words "ls | foo"))
        ;; multiple args
        (expect '("git" "--color" "status") :to-equal (words "git --color status")))))

  (it "pbt-filesystem-redirection-completion-preserves-prefix"
    (check-property (:trials 50)
        ((prefix (gen-command-prefix :min-length 1 :max-length 4) nil))
      (with-file-completion-adapters
          ((lambda (dir)
             (declare (ignore dir))
             (list (concatenate 'string prefix "-out.log")
                   "unrelated.log"))
           (lambda (dir)
             (declare (ignore dir))
             (list (concatenate 'string prefix "-dir/"))))
        (let ((candidates
                (nshell.domain.completion:complete
                 nshell.domain.completion::*built-in-rule-knowledge-base*
                 (concatenate 'string "git > " prefix))))
          (and candidates
               (every (lambda (candidate)
                        (completion-prefix-p
                         prefix
                         (nshell.domain.completion:candidate-text candidate)))
                      candidates)
               (every (lambda (candidate)
                        (member (nshell.domain.completion:candidate-kind candidate)
                                '(:file :directory)))
                      candidates))))))

  (it "command-path-candidates-projects-path-directories"
    "command-path-candidates returns matching executable candidates in PATH order."
    (flet ((executable-p (path)
             (member path '("/bin/git" "/usr/bin/git") :test #'string=)))
      (expect '("/bin/git" "/usr/bin/git") :to-equal
              (nshell.domain.completion:command-path-candidates
               "git" "/bin:/usr/bin" #'executable-p))))

(it "first-command-path-candidate-stops-at-first-executable"
    "The first-candidate lookup does not inspect later PATH entries."
    (let ((calls nil))
      (flet ((executable-p (path)
               (push path calls)
               (string= path "/two/git")))
        (expect "/two/git" :to-equal
                (nshell.domain.completion::%first-command-path-candidate
                 "git" "/one:/two:/three" #'executable-p))
        (expect '("/one/git" "/two/git") :to-equal (nreverse calls)))))

(it "first-command-path-candidate-checks-each-path-entry-on-miss"
    "A missing command checks every PATH entry exactly once."
    (let ((calls nil))
      (flet ((executable-p (path)
               (push path calls)
               nil))
        (expect (nshell.domain.completion::%first-command-path-candidate
                 "git" "/one:/two:/three" #'executable-p) :to-be-null)
        (expect '("/one/git" "/two/git" "/three/git")
                :to-equal (nreverse calls)))))

(it "first-command-path-candidate-preserves-path-projection-rules"
    "Empty PATH elements and qualified commands preserve existing semantics."
    (let ((calls nil))
      (flet ((executable-p (path)
               (push path calls)
               (member path '("./git" "./bin/git") :test #'string=)))
        (expect "./git" :to-equal
                (nshell.domain.completion::%first-command-path-candidate
                 "git" "" #'executable-p :empty-directory "."))
        (expect '("./git") :to-equal (nreverse calls))
        (setf calls nil)
        (expect "./bin/git" :to-equal
                (nshell.domain.completion::%first-command-path-candidate
                 "./bin/git" "/one:/two" #'executable-p))
        (expect '("./bin/git") :to-equal (nreverse calls)))))

(it "executable-file-p-handles-file-modes-and-missing-paths"
    "Executable lookup accepts executable files and rejects other paths."
    (let ((path (format nil "/tmp/nshell-executable-test-~d" (get-universal-time))))
      (unwind-protect
           (progn
             (with-open-file (stream path :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (write-line "test" stream))
             (sb-posix:chmod path #o600)
             (expect (nshell.infrastructure.acl::%executable-file-p path) :to-be-null)
             (sb-posix:chmod path #o700)
             (expect (nshell.infrastructure.acl::%executable-file-p path) :to-be-truthy))
        (when (probe-file path) (delete-file path)))
      (expect (nshell.infrastructure.acl::%executable-file-p
               (concatenate 'string path "-missing")) :to-be-null)))


  (it "command-path-candidates-honors-directory-command"
    "command-path-candidates checks directory-qualified commands directly."
    (flet ((executable-p (path)
             (string= path "./git")))
      (expect '("./git") :to-equal (nshell.domain.completion:command-path-candidates
                  "./git" "/bin:/usr/bin" #'executable-p))
      (expect (nshell.domain.completion:command-path-candidates
            "./missing" "/bin:/usr/bin" #'executable-p) :to-be-null)))

  (it "command-path-candidates-keeps-empty-directory-policy-explicit"
    "command-path-candidates lets callers choose how empty PATH elements are projected."
    (flet ((executable-p (path)
             (member path '("git" "./git" "/bin/git") :test #'string=)))
      (expect '("git" "/bin/git") :to-equal (nshell.domain.completion:command-path-candidates
                  "git" ":/bin" #'executable-p :empty-directory ""))
      (expect '("./git" "/bin/git") :to-equal (nshell.domain.completion:command-path-candidates
                  "git" ":/bin" #'executable-p :empty-directory "."))))

  (it "path-command-helpers-are-internal-boundaries"
    "Path command helper functions should not expose unprefixed legacy names."
    (expect :external :to-be (nth-value 1
                       (find-symbol "COMMAND-PATH-CANDIDATES"
                                    '#:nshell.domain.completion)))
    (flet ((defined-symbol-p (name)
             (nth-value 1 (find-symbol name '#:nshell.domain.completion))))
      (dolist (name '("%PATH-SEPARATOR-P"
                      "%COMMAND-PREFIX-HAS-DIRECTORY-P"
                      "%SPLIT-PATH"
                      "%JOIN-DIRECTORY-COMMAND"
                      "%ENTRY-COMMAND-NAME"
                      "%EXECUTABLE-CANDIDATE-P"
                      "%PATH-COMMAND-DIRECTORY-PATHNAME"
                      "%LIST-PATH-COMMAND-DIRECTORY"
                      "%PATH-COMMAND-ENTRY-CANDIDATE"
                      "%PATH-COMMAND-CANDIDATES-FROM-ENTRIES"
                      "%COMMAND-CANDIDATES-FROM-PATH"))
        (expect (fboundp (find-symbol name '#:nshell.domain.completion)) :to-be-truthy))
      (dolist (name '("PATH-SEPARATOR-P"
                      "COMMAND-PREFIX-HAS-DIRECTORY-P"
                      "SPLIT-PATH"
                      "JOIN-DIRECTORY-COMMAND"
                      "ENTRY-COMMAND-NAME"
                      "EXECUTABLE-CANDIDATE-P"
                      "PATH-COMMAND-DIRECTORY-PATHNAME"
                      "LIST-PATH-COMMAND-DIRECTORY"
                      "PATH-COMMAND-ENTRY-CANDIDATE"
                      "PATH-COMMAND-CANDIDATES-FROM-ENTRIES"
                      "COMMAND-CANDIDATES-FROM-PATH"))
        (expect (defined-symbol-p name) :to-be-falsy))))

  (it "trim-trailing-path-separators-removes-trailing-slashes"
    "trim-trailing-path-separators strips trailing / unless the string is only slashes."
    (flet ((trim (s) (nshell.domain.completion::%trim-trailing-path-separators s)))
      (expect "/usr/bin" :to-equal (trim "/usr/bin/"))
      (expect "/usr/bin" :to-equal (trim "/usr/bin"))
      ;; single slash preserved (only-separator case)
      (expect "/" :to-equal (trim "/"))))

  (it "entry-path-name-falls-back-to-directory-tail-component"
    "entry-path-name uses the final directory component when no file component exists."
    (flet ((entry-name (path) (nshell.domain.completion::%entry-path-name path)))
      (expect "project" :to-equal (entry-name (make-pathname :directory '(:absolute "tmp" "project"))))
      (expect (entry-name (make-pathname :directory '(:absolute))) :to-be-null)))

  (it "filesystem-query-constructors-are-internal-boundaries"
    "Filesystem completion query construction should not expose unprefixed helpers."
    (expect (fboundp 'nshell.domain.completion::%make-file-completion-prefix-projection) :to-be-truthy)
    (expect (fboundp 'nshell.domain.completion::%make-path-command-query) :to-be-truthy)
    (expect (fboundp 'nshell.domain.completion::%make-file-completion-query) :to-be-truthy)
    (expect (fboundp 'nshell.domain.completion::%make-empty-filesystem-candidate-set) :to-be-truthy)
    (flet ((defined-symbol-p (name)
             (nth-value 1 (find-symbol name '#:nshell.domain.completion))))
      (expect (defined-symbol-p "MAKE-FILE-COMPLETION-PREFIX-PROJECTION") :to-be-falsy)
      (expect (defined-symbol-p "MAKE-PATH-COMMAND-QUERY") :to-be-falsy)
      (expect (defined-symbol-p "MAKE-FILE-COMPLETION-QUERY") :to-be-falsy)
      (expect (defined-symbol-p "MAKE-FILESYSTEM-CANDIDATE-SET") :to-be-falsy)))

  (it "filesystem-query-state-accessors-are-internal-boundaries"
    "Filesystem query state should be read through internal accessors only."
    (expect (fboundp 'nshell.domain.completion::%path-command-query-path) :to-be-truthy)
    (expect (fboundp 'nshell.domain.completion::%path-command-query-prefix) :to-be-truthy)
    (expect (fboundp 'nshell.domain.completion::%file-completion-query-directory-prefix) :to-be-truthy)
    (expect (fboundp 'nshell.domain.completion::%file-completion-query-name-prefix) :to-be-truthy)
    (expect (fboundp 'nshell.domain.completion::%file-completion-query-directory) :to-be-truthy)
    (expect (fboundp 'nshell.domain.completion::%file-completion-query-include-files) :to-be-truthy)
    (expect (fboundp 'nshell.domain.completion::%file-completion-query-include-directories) :to-be-truthy)
    (flet ((defined-symbol-p (name)
             (nth-value 1 (find-symbol name '#:nshell.domain.completion))))
      (expect (defined-symbol-p "PATH-COMMAND-QUERY-PATH") :to-be-falsy)
      (expect (defined-symbol-p "PATH-COMMAND-QUERY-PREFIX") :to-be-falsy)
      (expect (defined-symbol-p "FILE-COMPLETION-QUERY-DIRECTORY-PREFIX") :to-be-falsy)
      (expect (defined-symbol-p "FILE-COMPLETION-QUERY-NAME-PREFIX") :to-be-falsy)
      (expect (defined-symbol-p "FILE-COMPLETION-QUERY-DIRECTORY") :to-be-falsy)
      (expect (defined-symbol-p "FILE-COMPLETION-QUERY-INCLUDE-FILES") :to-be-falsy)
      (expect (defined-symbol-p "FILE-COMPLETION-QUERY-INCLUDE-DIRECTORIES") :to-be-falsy)
      (expect (defined-symbol-p "PATH-COMMAND-QUERY-ACTIVE-P") :to-be-falsy)
      (expect (defined-symbol-p "FILE-COMPLETION-QUERY-FROM-PREFIX") :to-be-falsy)))

  (it "split-file-completion-prefix-splits-on-last-slash"
    "split-file-completion-prefix returns (dir-prefix . file-prefix) split at last /."
    (flet ((split (s)
             (multiple-value-list
              (nshell.domain.completion::%split-file-completion-prefix s))))
      (expect '("" "foo") :to-equal (split "foo"))
      (expect '("/usr/" "bin") :to-equal (split "/usr/bin"))
      (expect '("src/" "") :to-equal (split "src/")))
    (let ((projection
            (nshell.domain.completion::%project-file-completion-prefix "src/main")))
      (expect "src/" :to-equal (nshell.domain.completion::%file-completion-prefix-projection-directory-prefix
                    projection))
      (expect "main" :to-equal (nshell.domain.completion::%file-completion-prefix-projection-file-prefix
                    projection))))

  (it "file-completion-prefix-projection-accessors-are-internal-boundaries"
    "File prefix projection readers should stay internal to the filesystem boundary."
    (expect (fboundp 'nshell.domain.completion::%file-completion-prefix-projection-directory-prefix) :to-be-truthy)
    (expect (fboundp 'nshell.domain.completion::%file-completion-prefix-projection-file-prefix) :to-be-truthy)
    (flet ((defined-symbol-p (name)
             (nth-value 1 (find-symbol name '#:nshell.domain.completion))))
      (expect (defined-symbol-p "FILE-COMPLETION-PREFIX-PROJECTION-DIRECTORY-PREFIX") :to-be-falsy)
      (expect (defined-symbol-p "FILE-COMPLETION-PREFIX-PROJECTION-FILE-PREFIX") :to-be-falsy)))

  (it "file-completion-helpers-are-internal-boundaries"
    "File completion helper functions should not expose unprefixed legacy names."
    (flet ((defined-symbol-p (name)
             (nth-value 1 (find-symbol name '#:nshell.domain.completion))))
      (dolist (name '("%TRIM-TRAILING-PATH-SEPARATORS"
                      "%PATHNAME-DIRECTORY-TAIL-COMPONENT"
                      "%PATHNAME-LAST-DIRECTORY-COMPONENT"
                      "%PATHNAME-FILE-COMPONENT-NAME"
                      "%ENTRY-PATH-NAME"
                      "%PROJECT-FILE-COMPLETION-PREFIX"
                      "%SPLIT-FILE-COMPLETION-PREFIX"
                      "%FILE-COMPLETION-DIRECTORY-PATHNAME"
                      "%SAFE-FILE-COMPLETION-LIST"
                      "%ENSURE-DIRECTORY-CANDIDATE-SUFFIX"
                      "%FILE-COMPLETION-ENTRY-CANDIDATE"
                      "%ADD-FILE-COMPLETION-ENTRIES"
                      "%FILE-CANDIDATES-FROM-DIRECTORY"))
        (expect (fboundp (find-symbol name '#:nshell.domain.completion)) :to-be-truthy))
      (dolist (name '("TRIM-TRAILING-PATH-SEPARATORS"
                      "PATHNAME-DIRECTORY-TAIL-COMPONENT"
                      "PATHNAME-LAST-DIRECTORY-COMPONENT"
                      "PATHNAME-FILE-COMPONENT-NAME"
                      "ENTRY-PATH-NAME"
                      "PROJECT-FILE-COMPLETION-PREFIX"
                      "SPLIT-FILE-COMPLETION-PREFIX"
                      "FILE-COMPLETION-DIRECTORY-PATHNAME"
                      "SAFE-FILE-COMPLETION-LIST"
                      "ENSURE-DIRECTORY-CANDIDATE-SUFFIX"
                      "FILE-COMPLETION-ENTRY-CANDIDATE"
                      "ADD-FILE-COMPLETION-ENTRIES"
                      "FILE-CANDIDATES-FROM-DIRECTORY"))
        (expect (defined-symbol-p name) :to-be-falsy))))

  (it "file-candidates-from-directory-deduplicates-by-candidate-text"
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           (list #p"tool" #p"tool"))
         (lambda (dir)
           (declare (ignore dir))
           nil))
      (let* ((candidates
               (nshell.domain.completion::%file-candidates-from-directory
                "to"
                :include-files t
                :include-directories nil))
             (texts (completion-texts candidates)))
        (expect '("tool") :to-equal texts)
        (expect :file :to-be (nshell.domain.completion:candidate-kind
                       (first candidates)))))))
