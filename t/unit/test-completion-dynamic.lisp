(in-package #:nshell/test)

(describe "completion-dynamic-tests"
  (it "variable-completion-matches-dollar-prefix-and-shows-value"
    (let ((candidates (nshell.domain.completion:complete
                       (nshell.domain.completion:make-empty-knowledge-base)
                       "echo $HO"
                       :variable-names '(("HOME" . "/home/user") ("HOSTNAME" . "box")))))
      (assert-completion-texts-include candidates "$HOME" "$HOSTNAME")
      (let ((home (completion-candidate-by-text "$HOME" candidates)))
        (expect :variable :to-be (nshell.domain.completion:candidate-kind home))
        (expect "/home/user" :to-equal (nshell.domain.completion:candidate-description home)))))

  (it "variable-completion-handles-the-brace-form"
    (let ((candidates (nshell.domain.completion:complete
                       (nshell.domain.completion:make-empty-knowledge-base)
                       "echo ${HO"
                       :variable-names '(("HOME" . "/home/user")))))
      (assert-completion-texts-include candidates "${HOME")))

  (it "variable-completion-truncates-the-description-to-40-columns"
    (let* ((long-value (make-string 60 :initial-element #\x))
           (candidates (nshell.domain.completion:complete
                       (nshell.domain.completion:make-empty-knowledge-base)
                       "echo $LONG"
                       :variable-names (list (cons "LONGVAR" long-value)))))
      (expect 40 :to-equal
              (length (nshell.domain.completion:candidate-description
                       (completion-candidate-by-text "$LONGVAR" candidates))))))

  (it "variable-completion-does-not-fire-without-a-dollar-prefix"
    (let ((candidates (nshell.domain.completion:complete
                       (nshell.domain.completion:make-empty-knowledge-base)
                       "echo HO"
                       :variable-names '(("HOME" . "/home/user")))))
      (assert-completion-texts-exclude candidates "$HOME" "HOME")))

  (it "directory-only-completion-covers-cd-pushd-popd-and-rmdir"
    (with-test-file-filesystem
        ((lambda (dir) (declare (ignore dir)) (list #p"notes.txt"))
         (lambda (dir) (declare (ignore dir)) (list #p"src/")))
      (dolist (command '("cd" "pushd" "popd" "rmdir"))
        (let ((candidates (nshell.domain.completion:complete
                           (nshell.domain.completion:make-empty-knowledge-base)
                           (format nil "~a s" command)
                           :filesystem *completion-test-filesystem*)))
          (expect '("src/") :to-equal (completion-texts candidates))
          (expect :directory :to-be
                  (nshell.domain.completion:candidate-kind (first candidates)))))))

  (it "tilde-prefix-completion-expands-against-the-injected-home-directory"
    "The mock subdirectories function only returns entries when handed a
listing directory under /home/user, so this only passes if ~/ was actually
expanded rather than listed literally."
    (with-test-file-filesystem
        ((lambda (dir) (declare (ignore dir)) nil)
         (lambda (dir)
           (when (search "/home/user" (namestring dir))
             (list #p"Documents/"))))
      (let ((candidates (nshell.domain.completion:complete
                         (nshell.domain.completion:make-empty-knowledge-base)
                         "ls ~/Doc"
                         :filesystem *completion-test-filesystem*
                         :home-directory "/home/user")))
        (expect '("~/Documents/") :to-equal (completion-texts candidates)))))

  (it "tilde-prefix-completion-without-a-home-directory-does-not-expand"
    (with-test-file-filesystem
        ((lambda (dir) (declare (ignore dir)) nil)
         (lambda (dir)
           (when (search "/home/user" (namestring dir))
             (list #p"Documents/"))))
      (let ((candidates (nshell.domain.completion:complete
                         (nshell.domain.completion:make-empty-knowledge-base)
                         "ls ~/Doc"
                         :filesystem *completion-test-filesystem*)))
        (expect candidates :to-be-null))))

  (it "ranking-keeps-only-the-best-match-stage"
    (let* ((cs (nshell.domain.completion:make-candidate "gitk"))
           (ci (nshell.domain.completion:make-candidate "GitHub"))
           (substring-only (nshell.domain.completion:make-candidate "digit"))
           (ranked (nshell.domain.completion::%rank-candidates
                    "git" (list substring-only ci cs))))
      (expect (list "gitk") :to-equal (completion-texts ranked))))

  (it "ranking-keeps-case-sensitive-prefix-ahead-of-case-insensitive-prefix"
    (let* ((cs (nshell.domain.completion:make-candidate "GitHub"))
           (ci-only (nshell.domain.completion:make-candidate "github-cli"))
           (ranked (nshell.domain.completion::%rank-candidates
                    "Git" (list ci-only cs))))
      (expect (list "GitHub") :to-equal (completion-texts ranked))))

  (it "candidate-prefix-match-p-accepts-case-insensitive-prefixes-but-not-substrings"
    (let ((substring-only (nshell.domain.completion:make-candidate "digit"))
          (real-prefix (nshell.domain.completion:make-candidate "gitk"))
          (case-insensitive-prefix (nshell.domain.completion:make-candidate "GitHub")))
      (expect (nshell.domain.completion:candidate-prefix-match-p "git" substring-only)
              :to-be-falsy)
      (expect (nshell.domain.completion:candidate-prefix-match-p "git" real-prefix)
              :to-be-truthy)
      (expect (nshell.domain.completion:candidate-prefix-match-p "git" case-insensitive-prefix)
              :to-be-truthy)))

  (it "runtime-alias-completion-falls-back-to-fuzzy-subsequence-match"
    (let ((alias-table (make-hash-table :test (function equal))))
      (setf (gethash "zz-mytool-deploy" alias-table) t)
      (let ((candidates (nshell.domain.completion:complete
                         (nshell.domain.completion:make-empty-knowledge-base)
                         "dply"
                         :alias-table alias-table)))
        (assert-completion-texts-include candidates "zz-mytool-deploy"))))

  (it "git-checkout-completes-branch-names-from-the-branch-lister-hook"
    (nshell.domain.completion::%invalidate-git-dynamic-cache)
    (let ((nshell.domain.completion::*git-branch-lister*
            (lambda (directory)
              (expect "/repo" :to-equal directory)
              (list "main" "feature-x" "feature-y"))))
      (let ((candidates (nshell.domain.completion:complete
                         (nshell.domain.completion:make-empty-knowledge-base)
                         "git checkout fea"
                         :directory "/repo")))
        (expect '("feature-x" "feature-y") :to-equal (completion-texts candidates))
        (expect "branch" :to-equal
                (nshell.domain.completion:candidate-description (first candidates))))))

  (it "git-branch-completes-for-branch-dash-d"
    (nshell.domain.completion::%invalidate-git-dynamic-cache)
    (let ((nshell.domain.completion::*git-branch-lister*
            (lambda (directory) (declare (ignore directory)) (list "main" "old-feature"))))
      (let ((candidates (nshell.domain.completion:complete
                         (nshell.domain.completion:make-empty-knowledge-base)
                         "git branch -d old"
                         :directory "/repo")))
        (expect '("old-feature") :to-equal (completion-texts candidates)))))

  (it "git-add-completes-modified-paths-from-the-modified-path-lister-hook"
    (nshell.domain.completion::%invalidate-git-dynamic-cache)
    (let ((nshell.domain.completion::*git-modified-path-lister*
            (lambda (directory)
              (declare (ignore directory))
              (list "src/foo.lisp" "README.md"))))
      (let ((candidates (nshell.domain.completion:complete
                         (nshell.domain.completion:make-empty-knowledge-base)
                         "git add src"
                         :directory "/repo")))
        (expect '("src/foo.lisp") :to-equal (completion-texts candidates)))))

  (it "git-dynamic-candidates-do-nothing-without-a-directory"
    (nshell.domain.completion::%invalidate-git-dynamic-cache)
    (let ((nshell.domain.completion::*git-branch-lister*
            (lambda (directory) (declare (ignore directory)) (list "main"))))
      (let ((candidates (nshell.domain.completion:complete
                         (nshell.domain.completion:make-empty-knowledge-base)
                         "git checkout m")))
        (expect candidates :to-be-null))))

  (it "git-branch-lister-is-cached-per-directory-within-the-ttl"
    (nshell.domain.completion::%invalidate-git-dynamic-cache)
    (let ((call-count 0)
          (now 0))
      (let ((nshell.domain.completion::*git-branch-lister*
              (lambda (directory) (declare (ignore directory)) (incf call-count) (list "main")))
            (nshell.domain.completion::*git-dynamic-cache-clock-fn* (lambda () now)))
        (nshell.domain.completion:complete
         (nshell.domain.completion:make-empty-knowledge-base) "git checkout m" :directory "/repo")
        (nshell.domain.completion:complete
         (nshell.domain.completion:make-empty-knowledge-base) "git checkout m" :directory "/repo")
        (expect 1 :to-equal call-count)
        (setf now 10)
        (nshell.domain.completion:complete
         (nshell.domain.completion:make-empty-knowledge-base) "git checkout m" :directory "/repo")
        (expect 2 :to-equal call-count)))))
(describe "third-party-completion-source-tests"
  (it "parses-literal-ssh-hosts-and-skips-patterns-and-hashed-known-hosts"
    (expect '("another-host" "config-host" "known-host" "other-host") :to-equal
            (nshell.domain.completion::%ssh-host-names-from-text
             '("Host config-host *.example !excluded"
               "Host another-host")
             '("known-host,other-host ssh-ed25519 placeholder-key"
               "|1|hashed-host ssh-ed25519 placeholder-key"
               "@revoked |1|revoked-host ssh-ed25519 placeholder-key"))))

  (it "parses-make-targets-without-recipes-phony-patterns-or-assignments"
    (expect '("build" "deploy" "scenario-test") :to-equal
            (nshell.domain.completion::%makefile-target-names
             (list ".PHONY: scenario-test"
               "scenario-test: dependency"
               "build deploy:"
               (concatenate 'string (string #\Tab) "@echo ignored-target:")
               "%.o: %.c"
               "SOURCE := generated"
               "# ignored: comment"))))

  (it "completes-ssh-hosts-and-make-targets-from-their-listers"
    (let ((nshell.domain.completion::*ssh-host-lister*
            (lambda (home)
              (expect "scenario-home" :to-equal home)
              '("scenario-build-host" "other-host")))
          (nshell.domain.completion::*make-target-lister*
            (lambda (directory)
              (expect "/repo" :to-equal directory)
              '("scenario-test" "clean"))))
      (let ((ssh-candidates
              (nshell.domain.completion:complete
               (nshell.domain.completion:make-empty-knowledge-base)
               "ssh scenario-" :home-directory "scenario-home"))
            (make-candidates
              (nshell.domain.completion:complete
               (nshell.domain.completion:make-empty-knowledge-base)
               "make scenario" :directory "/repo")))
        (expect '("scenario-build-host") :to-equal (completion-texts ssh-candidates))
        (expect '("scenario-test") :to-equal (completion-texts make-candidates)))))

  (it "completes-kill-signals-pids-and-usernames"
    (let ((signals
            (nshell.domain.completion:complete
             (nshell.domain.completion:make-empty-knowledge-base) "kill -T"))
          (pids
            (nshell.domain.completion:complete
             (nshell.domain.completion:make-empty-knowledge-base)
             "kill 12" :process-ids '("123" "234")))
          (users
            (nshell.domain.completion::%username-completion-candidates
             "~scenario" '(("USER" . "scenario-user")))))
      (expect '("-TERM" "-TSTP" "-TTIN" "-TTOU") :to-equal
              (completion-texts signals))
      (expect '("123") :to-equal (completion-texts pids))
      (expect '("~scenario-user/") :to-equal (completion-texts users))))

  (it "unwraps-wrapper-options-before-the-completion-target"
    (dolist (case '(("env cargo bu" "cargo" "bu" ("bu") nil)
                    ("sudo -u 1234 kubectl ge" "kubectl" "ge" ("ge") nil)
                    ("sudo gi" "gi" "" nil t)
                    ("xargs cargo" "cargo" "" nil t)))
      (destructuring-bind (line command prefix words command-position-p) case
        (let* ((raw (nshell.domain.completion:completion-context-for line))
               (context (nshell.domain.completion::%unwrap-completion-context raw)))
          (expect command :to-equal
                  (nshell.domain.completion:completion-context-command context))
          (expect prefix :to-equal
                  (nshell.domain.completion:completion-context-argument-prefix context))
          (expect words :to-equal
                  (nshell.domain.completion:completion-context-argument-words context))
          (expect command-position-p :to-equal
                  (nshell.domain.completion:completion-context-command-position-p context)))))))

(describe "completion-match-stage-tests"
  (it "keeps-only-the-best-match-stage"
    (let* ((candidates (list (nshell.domain.completion:make-candidate "status")
                             (nshell.domain.completion:make-candidate "Status")
                             (nshell.domain.completion:make-candidate "the status")
                             (nshell.domain.completion:make-candidate "s-t-a-t-u-s")))
           (ranked (nshell.domain.completion::%rank-candidates "st" candidates)))
      (expect (list "status") :to-equal (completion-texts ranked))))

  (it "falls-back-to-case-insensitive-prefix-matches"
    (let* ((candidates (list (nshell.domain.completion:make-candidate "Status")
                             (nshell.domain.completion:make-candidate "the Status")))
           (ranked (nshell.domain.completion::%rank-candidates "st" candidates)))
      (expect (list "Status") :to-equal (completion-texts ranked))))
  (it "uppercase-query-falls-back-to-case-insensitive-prefix-match"
    (let ((ranked
            (nshell.domain.completion::%rank-candidates
             "STATUS"
             (list (nshell.domain.completion:make-candidate "status")))))
      (expect (list "status") :to-equal (completion-texts ranked))))

  (it "falls-back-to-case-insensitive-substring-matches"
    (let* ((candidates (list (nshell.domain.completion:make-candidate "staTUs")
                             (nshell.domain.completion:make-candidate "t-u-s")))
           (ranked (nshell.domain.completion::%rank-candidates "tus" candidates)))
      (expect (list "staTUs") :to-equal (completion-texts ranked))))

  (it "falls-back-to-case-insensitive-subsequence-matches"
    (let* ((candidates (list (nshell.domain.completion:make-candidate "s-T-s")))
           (ranked (nshell.domain.completion::%rank-candidates "STS" candidates)))
      (expect (list "s-T-s") :to-equal (completion-texts ranked)))))

(describe "completion-insertion-tests"
  (it "replaces-input-token-when-inserting-a-subsequence-match"
    (let ((candidate (nshell.domain.completion:make-candidate "status" :kind :command)))
      (expect "git status"
              :to-equal
              (nshell.presentation:apply-completion "git stt" candidate)))))
