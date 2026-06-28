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
           (kb (nshell.domain.completion:make-knowledge-base)))
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

(test completion-context-word-like-token-p-returns-canonical-booleans
  (is (eq t (nshell.domain.completion::word-like-token-p
             (nshell.domain.parsing:make-token :word "git"))))
  (is (eq t (nshell.domain.completion::word-like-token-p
             (nshell.domain.parsing:make-token :error "git"))))
  (is (null (nshell.domain.completion::word-like-token-p
             (nshell.domain.parsing:make-token :pipe "|")))))

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
