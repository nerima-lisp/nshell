(in-package #:nshell/test)

(in-suite repl-tests)

(test autosuggest-history-wins-over-completion
  (with-history (history "git clone")
    (let ((kb (nshell.domain.completion:make-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb
                                               "git"
                                               :subcommands '("clean"))
      (is (string= "one"
                   (nshell.presentation:compute-suggestion
                    history
                    "git cl"
                    :knowledge-base kb))))))

(test autosuggest-completes-command-from-knowledge-base
  (let ((history (nshell.domain.history:make-command-history))
        (kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "git")
    (is (string= "t"
                 (nshell.presentation:compute-suggestion
                  history
                  "gi"
                  :knowledge-base kb)))))

(test autosuggest-completes-argument-from-rules
  (let ((history (nshell.domain.history:make-command-history))
        (kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "git" :flags '("status"))
    (is (string= "atus"
                 (nshell.presentation:compute-suggestion
                  history
                  "git st"
                  :knowledge-base kb)))))

(test autosuggest-extends-command-prefix-across-multiple-candidates
  (let ((history (nshell.domain.history:make-command-history))
        (kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "git")
    (nshell.domain.completion:kb-add-command kb "gite")
    (is (string= "t"
                 (nshell.presentation:compute-suggestion
                  history
                  "gi"
                  :knowledge-base kb)))))

(test autosuggest-does-not-repeat-exact-candidate
  (let ((history (nshell.domain.history:make-command-history))
        (kb (nshell.domain.completion:make-knowledge-base)))
    (is (null (nshell.presentation:compute-suggestion
               history
               "git status"
               :knowledge-base kb)))))

(test autosuggest-does-not-repeat-exact-history-entry
  (with-history (history "git status")
    (let ((kb (nshell.domain.completion:make-knowledge-base)))
      (is (null (nshell.presentation:compute-suggestion
                 history
                 "git status"
                 :knowledge-base kb))))))

(test autosuggest-completes-continuation-line-from-history
  (with-history (history "echo setup
git status --short")
    (let ((kb (nshell.domain.completion:make-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb
                                               "git"
                                               :subcommands '("stash"))
      (is (string= "atus --short"
                   (nshell.presentation:compute-suggestion
                    history
                    "git st"
                    :knowledge-base kb))))))

(test autosuggest-does-not-suggest-on-blank-input
  (with-history (history "git status")
    (let ((kb (nshell.domain.completion:make-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "git")
      (is (null (nshell.presentation:compute-suggestion
                 history
                 ""
                 :knowledge-base kb)))
      (is (null (nshell.presentation:compute-suggestion
                 history
                 "   "
                 :knowledge-base kb))))))

(test autosuggest-does-not-suggest-on-operator-only-input
  (with-history (history "git status")
    (let ((kb (nshell.domain.completion:make-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "git")
      (dolist (input '("|" "&&" ">" ";"))
        (is (null (nshell.presentation:compute-suggestion
                   history
                   input
                   :knowledge-base kb)))))))

(test pbt-autosuggest-does-not-suggest-on-operator-only-input
  "Any shell-operator-only input should behave like blank input."
  (with-history (history "git status")
      (let ((kb (nshell.domain.completion:make-knowledge-base)))
        (nshell.domain.completion:kb-add-command kb "git")
        (check-property (:trials 50)
          ((input (gen-shell-operator-only-input :min-length 1 :max-length 8
                                                 :include-return-p nil)))
        (null (nshell.presentation:compute-suggestion
               history
               input
               :knowledge-base kb))))))

(test autosuggest-completes-filesystem-argument
  (let ((history (nshell.domain.history:make-command-history))
        (kb (nshell.domain.completion:make-knowledge-base)))
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           nil)
         (lambda (dir)
           (declare (ignore dir))
           (list #p"src/" #p"tests/")))
      (is (string= "rc/"
                   (nshell.presentation:compute-suggestion
                    history
                    "cd s"
                    :knowledge-base kb))))))

(test autosuggest-escapes-filesystem-argument-tail
  (let ((history (nshell.domain.history:make-command-history))
        (kb (nshell.domain.completion:make-knowledge-base)))
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           (list #p"my file.lisp"))
         (lambda (dir)
           (declare (ignore dir))
           nil))
      (is (string= "\\ file.lisp"
                   (nshell.presentation:compute-suggestion
                    history
                    "source my"
                    :knowledge-base kb))))))

(test autosuggest-keeps-quoted-filesystem-argument-raw
  (let ((history (nshell.domain.history:make-command-history))
        (kb (nshell.domain.completion:make-knowledge-base)))
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           (list #p"my file.lisp"))
         (lambda (dir)
           (declare (ignore dir))
           nil))
      (dolist (input '("source 'my" "source \"my"))
        (is (string= " file.lisp"
                     (nshell.presentation:compute-suggestion
                      history
                      input
                      :knowledge-base kb)))))))

(test autosuggest-keeps-double-quoted-literal-backslash-prefix
  (let ((history (nshell.domain.history:make-command-history))
        (kb (nshell.domain.completion:make-knowledge-base)))
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           (list (make-pathname :name "my\\ file" :type "lisp")))
         (lambda (dir)
           (declare (ignore dir))
           nil))
      (is (string= "file.lisp"
                   (nshell.presentation:compute-suggestion
                    history
                    "source \"my\\ "
                    :knowledge-base kb))))))

(test autosuggest-does-not-append-outside-closed-quoted-token
  (let ((history (nshell.domain.history:make-command-history))
        (kb (nshell.domain.completion:make-knowledge-base)))
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           (list #p"my file.lisp"))
         (lambda (dir)
           (declare (ignore dir))
           nil))
      (dolist (input '("source 'my'" "source \"my\""))
        (is (null (nshell.presentation:compute-suggestion
                   history
                   input
                   :knowledge-base kb)))))))

(test autosuggest-completes-source-filesystem-arguments
  (let ((history (nshell.domain.history:make-command-history))
        (kb (nshell.domain.completion:make-knowledge-base)))
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           nil)
         (lambda (dir)
           (declare (ignore dir))
           (list #p"src/" #p"scripts.sh")))
      (dolist (input '("source sr" ". sr"))
        (is (string= "c/"
                     (nshell.presentation:compute-suggestion
                      history
                      input
                      :knowledge-base kb)))))))

(test autosuggest-completes-source-filesystem-arguments-after-trailing-space
  (let ((history (nshell.domain.history:make-command-history))
        (kb (nshell.domain.completion:make-knowledge-base)))
    (with-file-completion-adapters
        ((lambda (dir)
           (declare (ignore dir))
           nil)
         (lambda (dir)
           (declare (ignore dir))
           (list #p"src/" #p"scripts.sh")))
      (dolist (input '("source " ". "))
        (is (string= "scripts.sh/"
                     (nshell.presentation:compute-suggestion
                      history
                      input
                      :knowledge-base kb))))))

(test autosuggest-closed-quoted-token-p-detects-matching-delimiters
  "autosuggest-closed-quoted-token-p returns true when the token is fully quoted."
  (flet ((cq (input start end)
           (nshell.presentation::%autosuggest-closed-quoted-token-p input start end)))
    (is      (cq "'foo'" 0 5))
    (is      (cq "\"foo\"" 0 5))
    (is (not (cq "'foo"  0 4)))
    (is (not (cq "foo"   0 3)))
    (is (not (cq "''"    0 1)))))

(test accept-suggestion-appends-suggestion-to-input
  "accept-suggestion concatenates current input with the tab-suggestion suffix."
  (is (string= "git checkout"
               (nshell.presentation:accept-suggestion "git " "checkout")))
  (is (string= "git "
               (nshell.presentation:accept-suggestion "git " "")))))
