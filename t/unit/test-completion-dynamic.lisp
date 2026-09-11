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

  (it "ranking-orders-case-sensitive-prefix-then-case-insensitive-then-substring"
    (let* ((cs (nshell.domain.completion:make-candidate "gitk"))
           (ci (nshell.domain.completion:make-candidate "GitHub"))
           (substring-only (nshell.domain.completion:make-candidate "digit"))
           (ranked (nshell.domain.completion::%rank-candidates
                    "git" (list substring-only ci cs))))
      (expect '("gitk" "GitHub" "digit") :to-equal (completion-texts ranked))))

  (it "ranking-smart-case-excludes-case-insensitive-only-matches"
    (let* ((cs (nshell.domain.completion:make-candidate "GitHub"))
           (ci-only (nshell.domain.completion:make-candidate "github-cli"))
           (ranked (nshell.domain.completion::%rank-candidates
                    "Git" (list ci-only cs))))
      (expect '("GitHub") :to-equal (completion-texts ranked))))

  (it "candidate-prefix-match-p-rejects-a-substring-only-match"
    "Exercises the not-yet-exported predicate via an internal reference; see
this agent's report for the NSHELL.DOMAIN.COMPLETION export it still needs."
    (let ((substring-only (nshell.domain.completion:make-candidate "digit"))
          (real-prefix (nshell.domain.completion:make-candidate "gitk")))
      (expect (nshell.domain.completion::candidate-prefix-match-p "git" substring-only) :to-be-falsy)
      (expect (nshell.domain.completion::candidate-prefix-match-p "git" real-prefix) :to-be-truthy)))

  (it "runtime-alias-completion-falls-back-to-substring-match"
    (let ((alias-table (make-hash-table :test #'equal)))
      (setf (gethash "zz-mytool-deploy" alias-table) t)
      (let ((candidates (nshell.domain.completion:complete
                         (nshell.domain.completion:make-empty-knowledge-base)
                         "deploy"
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
