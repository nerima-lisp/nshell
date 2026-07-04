(in-package #:nshell/test)
(in-suite completion-rules-tests)

(test completion-context-for-escaped-space-keeps-logical-argument-prefix
  (let ((context (nshell.domain.completion:completion-context-for "git ch\\ file")))
    (is (string= "git"
                 (nshell.domain.completion:completion-context-command context)))
    (is (string= "ch file"
                 (nshell.domain.completion:completion-context-argument-prefix context)))
    (is (not (nshell.domain.completion:completion-context-command-position-p context)))
    (is (null (nshell.domain.completion:completion-context-redirection-target-p context)))))

(test completion-context-for-double-quoted-backslash-space-keeps-literal-prefix
  (let ((context (nshell.domain.completion:completion-context-for "git \"ch\\ ")))
    (is (string= "git"
                 (nshell.domain.completion:completion-context-command context)))
    (is (string= "ch\\ "
                 (nshell.domain.completion:completion-context-argument-prefix context)))
    (is (not (nshell.domain.completion:completion-context-command-position-p context)))
    (is (null (nshell.domain.completion:completion-context-redirection-target-p context)))))

(test completion-context-for-leading-assignment-words-uses-real-command
  (let ((context (nshell.domain.completion:completion-context-for "FOO=bar git ch")))
    (is (string= "git"
                 (nshell.domain.completion:completion-context-command context)))
    (is (string= "ch"
                 (nshell.domain.completion:completion-context-argument-prefix context)))
    (is (equal '("ch")
               (nshell.domain.completion:completion-context-argument-words context)))
    (is (not (nshell.domain.completion:completion-context-command-position-p context)))
    (is (null (nshell.domain.completion:completion-context-redirection-target-p context)))))

(test completion-context-for-leading-assignment-command-prefix-stays-command-position
  (let ((context (nshell.domain.completion:completion-context-for "FOO=bar gi")))
    (is (string= "gi"
                 (nshell.domain.completion:completion-context-command context)))
    (is (string= ""
                 (nshell.domain.completion:completion-context-argument-prefix context)))
    (is (equal '()
               (nshell.domain.completion:completion-context-argument-words context)))
    (is (nshell.domain.completion:completion-context-command-position-p context))
    (is (null (nshell.domain.completion:completion-context-redirection-target-p context)))))

(test completion-context-for-respects-command-separators
  (dolist (case '(("echo ignored && git ch" "git" "ch")
                  ("echo ignored || git ch" "git" "ch")
                  ("echo ignored ; git ch" "git" "ch")
                  ("echo ignored & git ch" "git" "ch")))
    (destructuring-bind (line expected-command expected-prefix) case
      (let ((context (nshell.domain.completion:completion-context-for line)))
        (is (string= expected-command
                     (nshell.domain.completion:completion-context-command context)))
        (is (string= expected-prefix
                     (nshell.domain.completion:completion-context-argument-prefix context)))
        (is (equal (list expected-prefix)
                   (nshell.domain.completion:completion-context-argument-words context)))
        (is (not (nshell.domain.completion:completion-context-command-position-p context)))
        (is (null (nshell.domain.completion:completion-context-redirection-target-p context)))))))

(test completion-context-keeps-segment-local-argument-words
  (let ((context (nshell.domain.completion:completion-context-for
                  "FOO=bar git --color a")))
    (is (string= "git"
                 (nshell.domain.completion:completion-context-command context)))
    (is (string= "a"
                 (nshell.domain.completion:completion-context-argument-prefix context)))
    (is (equal '("--color" "a")
               (nshell.domain.completion:completion-context-argument-words context)))))

(test completion-context-argument-words-respect-command-separators
  (let ((context (nshell.domain.completion:completion-context-for
                  "echo ignored; kubectl -o ")))
    (is (string= "kubectl"
                 (nshell.domain.completion:completion-context-command context)))
    (is (string= ""
                 (nshell.domain.completion:completion-context-argument-prefix context)))
    (is (equal '("-o")
               (nshell.domain.completion:completion-context-argument-words context)))))

(test pbt-redirection-target-completion-does-not-leak-command-options
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

(test completion-command-position-p-classifies-word-state
  (let ((empty (nshell.domain.completion:completion-context-for ""))
        (command (nshell.domain.completion:completion-context-for "git"))
        (argument (nshell.domain.completion:completion-context-for "git status"))
        (after-argument (nshell.domain.completion:completion-context-for "git status ")))
    (is (string= "" (nshell.domain.completion:completion-context-command empty)))
    (is (nshell.domain.completion:completion-context-command-position-p empty))
    (is (string= "git" (nshell.domain.completion:completion-context-command command)))
    (is (nshell.domain.completion:completion-context-command-position-p command))
    (is (string= "status" (nshell.domain.completion:completion-context-argument-prefix argument)))
    (is (not (nshell.domain.completion:completion-context-command-position-p argument)))
    (is (string= "" (nshell.domain.completion:completion-context-argument-prefix after-argument)))
    (is (not (nshell.domain.completion:completion-context-command-position-p after-argument)))))

(test completion-context-skips-leading-assignments-for-command-word
  (let ((context (nshell.domain.completion:completion-context-for "FOO=bar git")))
    (is (string= "git" (nshell.domain.completion:completion-context-command context)))
    (is (nshell.domain.completion:completion-context-command-position-p context))
    (is (equal '() (nshell.domain.completion:completion-context-argument-words context)))))

(test completion-context-uses-latest-word-only-at-cursor-boundary
  (let ((at-argument (nshell.domain.completion:completion-context-for "git status"))
        (after-argument (nshell.domain.completion:completion-context-for "git status ")))
    (is (string= "status"
                 (nshell.domain.completion:completion-context-argument-prefix at-argument)))
    (is (equal '("status")
               (nshell.domain.completion:completion-context-argument-words at-argument)))
    (is (string= ""
                 (nshell.domain.completion:completion-context-argument-prefix after-argument)))
    (is (equal '("status")
               (nshell.domain.completion:completion-context-argument-words after-argument)))))

(test completion-context-constructors-are-internal-boundaries
  "Completion context construction should not expose legacy unprefixed helper names."
  (is (not (fboundp 'nshell.domain.completion::make-completion-context)))
  (is (not (fboundp 'nshell.domain.completion::make-completion-word)))
  (is (not (fboundp 'nshell.domain.completion::make-completion-input-analysis)))
  (is (not (fboundp 'nshell.domain.completion::make-completion-command-word-projection)))
  (is (not (fboundp 'nshell.domain.completion::make-completion-word-stream-projection)))
  (is (not (fboundp 'nshell.domain.completion::project-completion-command-word)))
  (is (not (fboundp 'nshell.domain.completion::project-completion-word-stream)))
  (is (not (fboundp 'nshell.domain.completion::completion-command-word-projection-word)))
  (is (not (fboundp 'nshell.domain.completion::completion-word-stream-projection-latest-word)))
  (is (fboundp 'nshell.domain.completion::%make-completion-context))
  (is (fboundp 'nshell.domain.completion::%make-completion-word))
  (is (fboundp 'nshell.domain.completion::%make-completion-input-analysis))
  (is (fboundp 'nshell.domain.completion::%make-completion-command-word-projection))
  (is (fboundp 'nshell.domain.completion::%make-completion-word-stream-projection))
  (is (fboundp 'nshell.domain.completion::%project-completion-command-word))
  (is (fboundp 'nshell.domain.completion::%project-completion-word-stream))
  (is (fboundp 'nshell.domain.completion::%completion-command-word-projection-word))
  (is (fboundp 'nshell.domain.completion::%completion-word-stream-projection-latest-word)))

(test completion-query-constructor-is-internal-boundary
  "Completion query construction should stay behind completion-query-for."
  (is (not (fboundp 'nshell.domain.completion::make-completion-query)))
  (is (fboundp 'nshell.domain.completion::%make-completion-query)))

(test completion-context-word-like-token-p-returns-canonical-booleans
  (is (eq t (nshell.domain.completion::word-like-token-p
             (nshell.domain.parsing:make-token :word "git"))))
  (is (eq t (nshell.domain.completion::word-like-token-p
             (nshell.domain.parsing:make-token :error "git"))))
  (is (null (nshell.domain.completion::word-like-token-p
             (nshell.domain.parsing:make-token :pipe "|")))))

(test starts-with-p-performs-case-insensitive-prefix-match
  "starts-with-p returns true when text starts with prefix (case-folded)."
  (flet ((swp (prefix text)
           (nshell.domain.completion::starts-with-p prefix text)))
    (is (swp "" "anything"))
    (is (swp "git" "git checkout"))
    (is (swp "GIT" "git checkout"))
    (is (not (swp "gitx" "git")))
    (is (not (swp "checkout" "git")))))

(test redirection-token-p-recognizes-redirect-type
  "redirection-token-p returns true only for :redirect tokens."
  (flet ((redir (type)
           (nshell.domain.completion::redirection-token-p
            (nshell.domain.parsing:make-token type ""))))
    (is (redir :redirect))
    (is (not (redir :pipe)))
    (is (not (redir :word)))
    (is (not (redir :newline)))))

(test command-segment-tokens-returns-tokens-after-last-separator
  "command-segment-tokens strips everything up to and including the last separator."
  (flet ((tokens (input)
           (nshell.domain.parsing:tokenization-result-tokens
            (nshell.domain.parsing:tokenize input))))
    (flet ((seg (input)
             (nshell.domain.completion::command-segment-tokens
              (tokens input))))
      ;; no separator: whole token list returned
      (is (= 2 (length (seg "git checkout"))))
      ;; after &&: only "git" and "ch" returned
      (is (= 2 (length (seg "echo a && git ch"))))
      ;; after semicolon
      (is (= 1 (length (seg "a ; b")))))))

(test shell-completion-words-merges-adjacent-word-tokens
  "shell-completion-words combines adjacent word-like tokens into single logical words."
  (flet ((tokens (input)
           (nshell.domain.parsing:tokenization-result-tokens
            (nshell.domain.parsing:tokenize input))))
    (flet ((words (input)
             (mapcar #'nshell.domain.completion::completion-word-value
                     (nshell.domain.completion::shell-completion-words
                      (tokens input)))))
      (is (equal '("git" "checkout") (words "git checkout")))
      ;; pipe is not word-like so it triggers a flush
      (is (equal '("ls" "foo") (words "ls | foo")))
      ;; multiple args
      (is (equal '("git" "--color" "status") (words "git --color status"))))))

(test pbt-filesystem-redirection-completion-preserves-prefix
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

(test path-separator-p-detects-forward-slash
  "path-separator-p returns true only for / (path separator on Unix)."
  (flet ((sep (ch) (nshell.domain.completion:path-separator-p ch)))
    (is (sep #\/))
    (is (not (sep #\:)))
    (is (not (sep #\a)))))

(test command-prefix-has-directory-p-detects-slash-in-prefix
  "command-prefix-has-directory-p returns the slash position when one is present."
  (flet ((has-dir (s)
           (nshell.domain.completion:command-prefix-has-directory-p s)))
    (is (null (has-dir "git")))
    (is (not (null (has-dir "./git"))))
    (is (not (null (has-dir "/usr/bin/git"))))))

(test split-path-splits-colon-separated-directories
  "split-path splits a colon-separated PATH into a list of directory strings."
  (flet ((sp (s) (nshell.domain.completion:split-path s)))
    (is (equal '("/bin" "/usr/bin") (sp "/bin:/usr/bin")))
    (is (equal '("/bin") (sp "/bin")))
    (is (equal '("" "/bin") (sp ":/bin")))))

(test join-directory-command-handles-empty-directory-policy
  "join-directory-command keeps empty PATH element policy explicit at call sites."
  (flet ((join (directory command &key (empty-directory directory))
           (nshell.domain.completion:join-directory-command
            directory command :empty-directory empty-directory)))
    (is (string= "git" (join "" "git" :empty-directory "")))
    (is (string= "./git" (join "" "git" :empty-directory ".")))
    (is (string= "/bin/git" (join "/bin/" "git")))
    (is (string= "/bin/git" (join "/bin" "git")))))

(test trim-trailing-path-separators-removes-trailing-slashes
  "trim-trailing-path-separators strips trailing / unless the string is only slashes."
  (flet ((trim (s) (nshell.domain.completion::trim-trailing-path-separators s)))
    (is (string= "/usr/bin" (trim "/usr/bin/")))
    (is (string= "/usr/bin" (trim "/usr/bin")))
    ;; single slash preserved (only-separator case)
    (is (string= "/" (trim "/")))))

(test entry-path-name-falls-back-to-directory-tail-component
  "entry-path-name uses the final directory component when no file component exists."
  (flet ((entry-name (path) (nshell.domain.completion::entry-path-name path)))
    (is (string= "project"
                 (entry-name (make-pathname :directory '(:absolute "tmp" "project")))))
    (is (null (entry-name (make-pathname :directory '(:absolute)))))))

(test filesystem-query-constructors-are-internal-boundaries
  "Filesystem completion query construction should not expose unprefixed helpers."
  (is (fboundp 'nshell.domain.completion::%make-file-completion-prefix-projection))
  (is (fboundp 'nshell.domain.completion::%make-path-command-query))
  (is (fboundp 'nshell.domain.completion::%make-empty-filesystem-candidate-set))
  (is (not (fboundp 'nshell.domain.completion::make-file-completion-prefix-projection)))
  (is (not (fboundp 'nshell.domain.completion::make-path-command-query)))
  (is (not (fboundp 'nshell.domain.completion::make-filesystem-candidate-set))))

(test split-file-completion-prefix-splits-on-last-slash
  "split-file-completion-prefix returns (dir-prefix . file-prefix) split at last /."
  (flet ((split (s)
           (multiple-value-list
            (nshell.domain.completion::split-file-completion-prefix s))))
    (is (equal '("" "foo")      (split "foo")))
    (is (equal '("/usr/" "bin") (split "/usr/bin")))
    (is (equal '("src/" "")     (split "src/"))))
  (let ((projection
          (nshell.domain.completion::project-file-completion-prefix "src/main")))
    (is (string= "src/"
                 (nshell.domain.completion::file-completion-prefix-projection-directory-prefix
                  projection)))
    (is (string= "main"
                 (nshell.domain.completion::file-completion-prefix-projection-file-prefix
                  projection)))))

(test file-candidates-from-directory-deduplicates-by-candidate-text
  (with-file-completion-adapters
      ((lambda (dir)
         (declare (ignore dir))
         (list #p"tool" #p"tool"))
       (lambda (dir)
         (declare (ignore dir))
         nil))
    (let* ((candidates
             (nshell.domain.completion::file-candidates-from-directory
              "to"
              :include-files t
              :include-directories nil))
           (texts (completion-texts candidates)))
      (is (equal '("tool") texts))
      (is (eq :file (nshell.domain.completion:candidate-kind
                     (first candidates)))))))
