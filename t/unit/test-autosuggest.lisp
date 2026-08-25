(in-package #:nshell/test)

(describe "repl-tests"
  (it "autosuggest-history-wins-over-completion"
    (with-history (history "git clone")
      (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
        (nshell.domain.completion:kb-add-command kb
                                                 "git"
                                                 :subcommands '("clean"))
        (expect "one" :to-equal (nshell.presentation:compute-suggestion
                      history
                      "git cl"
                      :knowledge-base kb)))))

  (it "autosuggest-completes-command-from-knowledge-base"
    (let ((history (history-kit:make-history))
          (kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "git")
      (expect "t" :to-equal (nshell.presentation:compute-suggestion
                    history
                    "gi"
                    :knowledge-base kb))))

  (it "autosuggest-completes-argument-from-rules"
    (let ((history (history-kit:make-history))
          (kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "git" :flags '("status"))
      (expect "atus" :to-equal (nshell.presentation:compute-suggestion
                    history
                    "git st"
                    :knowledge-base kb))))

  (it "autosuggest-extends-command-prefix-across-multiple-candidates"
    (let ((history (history-kit:make-history))
          (kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "git")
      (nshell.domain.completion:kb-add-command kb "gite")
      (expect "t" :to-equal (nshell.presentation:compute-suggestion
                    history
                    "gi"
                    :knowledge-base kb))))

  (it "autosuggest-does-not-repeat-exact-candidate"
    (let ((history (history-kit:make-history))
          (kb (nshell.domain.completion:make-empty-knowledge-base)))
      (expect (nshell.presentation:compute-suggestion
                 history
                 "git status"
                 :knowledge-base kb) :to-be-null)))

  (it "autosuggest-does-not-repeat-exact-history-entry"
    (with-history (history "git status")
      (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
        (expect (nshell.presentation:compute-suggestion
                   history
                   "git status"
                   :knowledge-base kb) :to-be-null))))

  (it "autosuggest-completes-continuation-line-from-history"
    (with-history (history "echo setup
git status --short")
      (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
        (nshell.domain.completion:kb-add-command kb
                                                 "git"
                                                 :subcommands '("stash"))
        (expect "atus --short" :to-equal (nshell.presentation:compute-suggestion
                      history
                      "git st"
                      :knowledge-base kb)))))

  (it "autosuggest-does-not-suggest-on-blank-input"
    (with-history (history "git status")
      (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
        (nshell.domain.completion:kb-add-command kb "git")
        (expect (nshell.presentation:compute-suggestion
                   history
                   ""
                   :knowledge-base kb) :to-be-null)
        (expect (nshell.presentation:compute-suggestion
                   history
                   "   "
                   :knowledge-base kb) :to-be-null))))

  (it "autosuggest-does-not-suggest-on-operator-only-input"
    (with-history (history "git status")
      (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
        (nshell.domain.completion:kb-add-command kb "git")
        (dolist (input '("|" "&&" ">" ";"))
          (expect (nshell.presentation:compute-suggestion
                     history
                     input
                     :knowledge-base kb) :to-be-null)))))

  (it "pbt-autosuggest-does-not-suggest-on-operator-only-input"
    "Any shell-operator-only input should behave like blank input."
    (with-history (history "git status")
        (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
          (nshell.domain.completion:kb-add-command kb "git")
          (check-property (:trials 50)
            ((input (gen-shell-operator-only-input :min-length 1 :max-length 8
                                                   :include-return-p nil)))
          (null (nshell.presentation:compute-suggestion
                 history
                 input
                 :knowledge-base kb))))))

  (it "autosuggest-completes-filesystem-argument"
    (let ((history (history-kit:make-history))
          (kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-test-file-filesystem
          ((lambda (dir)
             (declare (ignore dir))
             nil)
           (lambda (dir)
             (declare (ignore dir))
             (list #p"src/" #p"tests/")))
        (expect "rc/" :to-equal (nshell.presentation:compute-suggestion
                      history
                      "cd s"
                      :knowledge-base kb
                      :filesystem *completion-test-filesystem*)))))

  (it "autosuggest-escapes-filesystem-argument-tail"
    (let ((history (history-kit:make-history))
          (kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-test-file-filesystem
          ((lambda (dir)
             (declare (ignore dir))
             (list #p"my file.lisp"))
           (lambda (dir)
             (declare (ignore dir))
             nil))
        (expect "\\ file.lisp" :to-equal (nshell.presentation:compute-suggestion
                      history
                      "source my"
                      :knowledge-base kb
                      :filesystem *completion-test-filesystem*)))))

  (it "autosuggest-keeps-quoted-filesystem-argument-raw"
    (let ((history (history-kit:make-history))
          (kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-test-file-filesystem
          ((lambda (dir)
             (declare (ignore dir))
             (list #p"my file.lisp"))
           (lambda (dir)
             (declare (ignore dir))
             nil))
        (dolist (input '("source 'my" "source \"my"))
          (expect " file.lisp" :to-equal (nshell.presentation:compute-suggestion
                        history
                        input
                        :knowledge-base kb
                        :filesystem *completion-test-filesystem*)))))

  (it "autosuggest-keeps-double-quoted-literal-backslash-prefix"
    (let ((history (history-kit:make-history))
          (kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-test-file-filesystem
          ((lambda (dir)
             (declare (ignore dir))
             (list (make-pathname :name "my\\ file" :type "lisp")))
           (lambda (dir)
             (declare (ignore dir))
             nil))
        (expect "file.lisp" :to-equal (nshell.presentation:compute-suggestion
                      history
                      "source \"my\\ "
                      :knowledge-base kb
                      :filesystem *completion-test-filesystem*)))))

  (it "autosuggest-does-not-append-outside-closed-quoted-token"
    (let ((history (history-kit:make-history))
          (kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-test-file-filesystem
          ((lambda (dir)
             (declare (ignore dir))
             (list #p"my file.lisp"))
           (lambda (dir)
             (declare (ignore dir))
             nil))
        (dolist (input '("source 'my'" "source \"my\""))
          (expect (nshell.presentation:compute-suggestion
                     history
                     input
                     :knowledge-base kb
                     :filesystem *completion-test-filesystem*) :to-be-null))))))

  (it "autosuggest-completes-source-filesystem-arguments"
    (let ((history (history-kit:make-history))
          (kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-test-file-filesystem
          ((lambda (dir)
             (declare (ignore dir))
             nil)
           (lambda (dir)
             (declare (ignore dir))
             (list #p"src/" #p"scripts.sh")))
        (dolist (input '("source sr" ". sr"))
          (expect "c/" :to-equal (nshell.presentation:compute-suggestion
                        history
                        input
                        :knowledge-base kb
                        :filesystem *completion-test-filesystem*))))))

  (it "autosuggest-completes-source-filesystem-arguments-after-trailing-space"
    (let ((history (history-kit:make-history))
          (kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-test-file-filesystem
          ((lambda (dir)
             (declare (ignore dir))
             nil)
           (lambda (dir)
             (declare (ignore dir))
             (list #p"src/" #p"scripts.sh")))
        (dolist (input '("source " ". "))
          (expect "scripts.sh/" :to-equal (nshell.presentation:compute-suggestion
                        history
                        input
                        :knowledge-base kb
                        :filesystem *completion-test-filesystem*))))))

  (it "autosuggest-closed-quoted-token-p-detects-matching-delimiters"
    "autosuggest-closed-quoted-token-p returns true when the token is fully quoted."
    (flet ((cq (input start end)
             (nshell.presentation::%autosuggest-closed-quoted-token-p input start end)))
      (expect (cq "'foo'" 0 5) :to-be-truthy)
      (expect (cq "\"foo\"" 0 5) :to-be-truthy)
      (expect (cq "'foo"  0 4) :to-be-falsy)
      (expect (cq "foo"   0 3) :to-be-falsy)
      (expect (cq "''"    0 1) :to-be-falsy)))

  (it "accept-suggestion-appends-suggestion-to-input"
    "accept-suggestion concatenates current input with the tab-suggestion suffix."
    (expect "git checkout" :to-equal (nshell.presentation:accept-suggestion "git " "checkout"))
    (expect "git " :to-equal (nshell.presentation:accept-suggestion "git " ""))))
