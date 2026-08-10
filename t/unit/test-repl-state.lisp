(in-package #:nshell/test)

(describe "repl-tests"
  (it "exported-environment-strings-only-include-exported-vars"
    "The REPL passes only exported domain environment variables to process launch."
    (with-repl-test-state
      (repl-test-set-env "LOCAL_ONLY" "hidden")
      (repl-test-set-env "VISIBLE" "yes" t)
      (let ((strings (nshell.presentation:exported-environment-strings)))
        (expect (member "VISIBLE=yes" strings :test #'string=) :to-be-truthy)
        (expect (member "LOCAL_ONLY=hidden" strings :test #'string=) :to-be-falsy))))

  (it "subprocess-environment-prefers-repl-export"
    "Subprocess launch uses the REPL's synchronized export list when present."
    (let ((nshell.infrastructure.acl:*exported-environment*
            '("NSHELL_TEST=from-repl")))
      (expect '("NSHELL_TEST=from-repl")
              :to-equal
              (nshell.infrastructure.acl::%get-environment))))

  (it "subprocess-environment-inherits-process-environment"
    "Subprocess launch inherits the host process environment before REPL synchronization."
    (let ((nshell.infrastructure.acl:*exported-environment* nil))
      (let ((environment (nshell.infrastructure.acl::%get-environment)))
        #+sbcl (expect (consp environment) :to-be-truthy)
        #-sbcl (expect environment :to-be-null))))

  (it "repl-builtin-dispatches-through-application-registry"
    "REPL builtin execution uses the application builtin registry and syncs context state."
    (with-repl-test-state
      (multiple-value-bind (output builtin-p code)
          (call-repl-builtin "set" '("GREETING" "hello"))
        (expect "" :to-equal output)
        (expect (null builtin-p) :to-be-falsy)
        (expect 0 :to-equal code)
        (expect "hello" :to-equal (repl-test-env "GREETING")))
      (multiple-value-bind (output builtin-p code)
          (call-repl-builtin "type" '("echo"))
        (expect (null builtin-p) :to-be-falsy)
        (expect 0 :to-equal code)
        (expect (search "echo is a shell builtin" output) :to-be-truthy))
      (multiple-value-bind (output builtin-p code)
          (call-repl-builtin "not-a-builtin" nil)
        (expect "" :to-equal output)
        (expect builtin-p :to-be-falsy)
        (expect code :to-be-null))))

  (it "repl-builtin-syncs-mutable-shell-state"
    "Registry builtins update REPL aliases, abbreviations, function table, and running flag."
    (with-repl-test-state
      (call-repl-builtin "alias" '("ll" "ls -l"))
      (expect "ls -l" :to-equal (repl-test-alias "ll"))
      (call-repl-builtin "abbr" '("-a" "gco" "git" "checkout"))
      (expect "git checkout" :to-equal (repl-test-abbreviation "gco"))
      (call-repl-builtin "function" '("hi" "echo" "hello" "end"))
      (expect '("echo hello") :to-equal (repl-test-function "hi"))
      (call-repl-builtin "exit" nil)
      (expect (repl-test-running-p) :to-be-falsy)))

  (it "repl-installs-host-filesystem-boundaries"
    "REPL setup installs host filesystem functions into completion and expansion seams."
    (with-repl-test-state
      (nshell.presentation::configure-completion-filesystem)
      (nshell.presentation::install-expansion-filesystem)
      (host-kit:with-temporary-directory (directory)
        (let* ((file (merge-pathnames "entry.txt" directory))
               (nested-file (merge-pathnames "nested/child.txt" directory)))
          (ensure-directories-exist nested-file)
          (host-kit:write-file-string "entry" file)
          (host-kit:write-file-string "child" nested-file)
          (let ((path-files
                  (funcall nshell.domain.completion:*path-command-directory-files-fn*
                           directory))
                (file-files
                  (funcall nshell.domain.completion:*file-completion-directory-files-fn*
                           directory))
                (file-subdirectories
                  (funcall nshell.domain.completion:*file-completion-subdirectories-fn*
                           directory))
                (glob-files
                  (funcall nshell.domain.expansion:*glob-directory-files-fn*
                           directory))
                (glob-subdirectories
                  (funcall nshell.domain.expansion:*glob-subdirectories-fn*
                           directory)))
            (expect (consp path-files) :to-be-truthy)
            (expect (consp file-files) :to-be-truthy)
            (expect (consp file-subdirectories) :to-be-truthy)
            (expect (consp glob-files) :to-be-truthy)
            (expect (consp glob-subdirectories) :to-be-truthy))
          (expect (nshell.presentation::executable-path-p
                   (pathname (current-sbcl-executable)))
                  :to-be-truthy)
          (expect (nshell.presentation::executable-path-p
                   #P"/definitely/not/a/nshell-executable")
                  :to-be-falsy)
          (expect (nshell.presentation::executable-path-p nil)
                  :to-be-falsy)))))
  (it "vi-mode-flag-values-control-mode" "The vi-mode environment flag accepts explicit truthy values and rejects disabled values." (expect (nshell.presentation::%vi-mode-flag-enabled-p nil) :to-be-falsy) (expect (nshell.presentation::%vi-mode-flag-enabled-p "") :to-be-falsy) (expect (nshell.presentation::%vi-mode-flag-enabled-p "0") :to-be-falsy) (expect (nshell.presentation::%vi-mode-flag-enabled-p "false") :to-be-falsy) (expect (nshell.presentation::%vi-mode-flag-enabled-p "no") :to-be-falsy) (expect (nshell.presentation::%vi-mode-flag-enabled-p "1") :to-be-truthy) (expect (nshell.presentation::%vi-mode-flag-enabled-p "yes") :to-be-truthy))
  (it "repl-filesystem-function-table"
    "The REPL filesystem table exposes file and directory predicates."
    (let ((filesystem-fns nshell.presentation::+repl-filesystem-fns+))
      (host-kit:with-temporary-directory (directory)
        (let ((file (merge-pathnames "entry.txt" directory)))
          (host-kit:write-file-string "entry" file)
          (let ((file-exists-p (getf filesystem-fns :file-exists-p))
                (directory-exists-p (getf filesystem-fns :directory-exists-p)))
            (expect (funcall file-exists-p file) :to-be-truthy)
            (expect (funcall file-exists-p directory) :to-be-falsy)
            (expect (funcall file-exists-p "/definitely/not/a/nshell-file") :to-be-falsy)
            (expect (funcall directory-exists-p directory) :to-be-truthy)
            (expect (funcall directory-exists-p "/definitely/not/a/nshell-directory") :to-be-falsy)))))))
