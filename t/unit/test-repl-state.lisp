(in-package #:nshell/test)

(defmacro expect-repl-table-contract (table test)
  `(progn
     (expect (hash-table-p ,table) :to-be-truthy)
     ,test))

(describe "repl-state-data-contracts"
  (it "preserves every input-state constructor field"
    (let* ((values (list "echo あ" 4 2 "echo " 5 '("echo hi") " suggestion"
                         :insert 3 7 1 9 #'identity '("old") 0 4 2 5 8 1
                         "needle" "echo あ" 3 1 '((:buffer "before"))
                         '((:buffer "after"))))
           (state (apply #'nshell.presentation:make-input-state
                         (mapcan (lambda (key value) (list key value))
                                 '(:buffer :cursor-pos :completion-index
                                   :completion-base-buffer :completion-base-cursor
                                   :last-candidates :suggestion :mode :vi-count
                                   :vi-visual-anchor :mouse-selection-anchor
                                   :mouse-selection-end :abbreviation-expander
                                   :kill-ring :last-yank-start :last-yank-end
                                   :last-yank-index :last-argument-start
                                   :last-argument-end :last-argument-index
                                   :search-query :search-original-buffer
                                   :search-original-cursor :search-index
                                   :undo-stack :redo-stack)
                                 values))))
      (loop :for accessor :in '(nshell.presentation::input-state-buffer
                                nshell.presentation::input-state-cursor-pos
                                nshell.presentation::input-state-completion-index
                                nshell.presentation::input-state-completion-base-buffer
                                nshell.presentation::input-state-completion-base-cursor
                                nshell.presentation::input-state-last-candidates
                                nshell.presentation::input-state-suggestion
                                nshell.presentation::input-state-mode
                                nshell.presentation::input-state-vi-count
                                nshell.presentation::input-state-vi-visual-anchor
                                nshell.presentation::input-state-mouse-selection-anchor
                                nshell.presentation::input-state-mouse-selection-end
                                nshell.presentation::input-state-abbreviation-expander
                                nshell.presentation::input-state-kill-ring
                                nshell.presentation::input-state-last-yank-start
                                nshell.presentation::input-state-last-yank-end
                                nshell.presentation::input-state-last-yank-index
                                nshell.presentation::input-state-last-argument-start
                                nshell.presentation::input-state-last-argument-end
                                nshell.presentation::input-state-last-argument-index
                                nshell.presentation::input-state-search-query
                                nshell.presentation::input-state-search-original-buffer
                                nshell.presentation::input-state-search-original-cursor
                                nshell.presentation::input-state-search-index
                                nshell.presentation::input-state-undo-stack
                                nshell.presentation::input-state-redo-stack)
            :for value :in values
            :always (equal value (funcall accessor state)))))

  (it "creates isolated tables for each shell state"
    (multiple-value-bind (aliases abbreviations functions sources processes)
        (nshell.presentation::%make-repl-state-tables)
      (expect-repl-table-contract aliases (expect (eq (hash-table-test aliases) 'equal) :to-be-truthy))
      (expect-repl-table-contract abbreviations (expect (eq (hash-table-test abbreviations) 'equal) :to-be-truthy))
      (expect-repl-table-contract functions (expect (eq (hash-table-test functions) 'equal) :to-be-truthy))
      (expect-repl-table-contract sources (expect (eq (hash-table-test sources) 'equal) :to-be-truthy))
      (expect-repl-table-contract processes (expect (eq (hash-table-test processes) 'eql) :to-be-truthy))
      (expect (not (eq aliases abbreviations)) :to-be-truthy)))

  (it "runs continuation chains to completion"
    (let ((steps 0))
      (expect nil
              :to-equal
              (nshell.presentation:trampoline
               (lambda ()
                 (incf steps)
                 (lambda ()
                   (incf steps)
                   (lambda ()
                     (incf steps)
                     nil)))))
      (expect 3 :to-equal steps)))

  (it "returns immediately for an exhausted continuation"
    (expect nil
            :to-equal
            (nshell.presentation:trampoline (lambda () nil))))

  (it "resets mutable tables and completion cache"
    (let ((stale-aliases (nshell.presentation::%make-repl-name-table))
          (stale-cache (nshell.presentation::%make-repl-name-table)))
      (setf (gethash "stale" stale-aliases) t
            (gethash "cached" stale-cache) t)
      (let ((nshell.presentation::*aliases* stale-aliases)
            (nshell.presentation::*completion-help-cache* stale-cache))
        (nshell.presentation::%reset-repl-state-tables)
        (expect (not (eq stale-aliases nshell.presentation::*aliases*)) :to-be-truthy)
        (expect 0 :to-equal (hash-table-count nshell.presentation::*aliases*))
        (expect 0 :to-equal (hash-table-count nshell.presentation::*completion-help-cache*)))))

  (it "binds fresh state without changing the caller tables"
    (let ((outer (make-hash-table :test #'equal)))
      (let ((nshell.presentation::*aliases* outer))
        (nshell.presentation::with-fresh-repl-state-tables
          (setf (gethash "inner" nshell.presentation::*aliases*) t)
          (expect (not (eq outer nshell.presentation::*aliases*)) :to-be-truthy)
          (expect (gethash "inner" nshell.presentation::*aliases*) :to-be-truthy))))))

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

  (it "repl-constructs-host-filesystem-capability"
    "The REPL execution context carries one host filesystem capability."
    (with-repl-test-state
      (let ((filesystem (nshell.infrastructure.acl:make-host-filesystem)))
        (host-kit:with-temporary-directory (directory)
          (let* ((file (merge-pathnames "entry.txt" directory))
                 (nested-file (merge-pathnames "nested/child.txt" directory)))
            (ensure-directories-exist nested-file)
            (host-kit:write-file-string "entry" file)
            (host-kit:write-file-string "child" nested-file)
            (let ((directory-files
                    (nshell.domain.filesystem:filesystem-directory-files
                     filesystem))
                  (subdirectories
                    (nshell.domain.filesystem:filesystem-subdirectories
                     filesystem)))
              (let ((path-files (funcall directory-files directory))
                    (file-files (funcall directory-files directory))
                    (file-subdirectories (funcall subdirectories directory))
                    (glob-files
                      (nshell.domain.expansion::recursive-directory-files
                       directory filesystem))
                    (glob-subdirectories (funcall subdirectories directory)))
            (expect (consp path-files) :to-be-truthy)
            (expect (consp file-files) :to-be-truthy)
            (expect (consp file-subdirectories) :to-be-truthy)
            (expect (consp glob-files) :to-be-truthy)
            (expect (consp glob-subdirectories) :to-be-truthy)))
            (expect (funcall
                     (nshell.domain.filesystem:filesystem-executable-p filesystem)
                     (pathname (current-sbcl-executable)))
                  :to-be-truthy)
            (expect (funcall
                     (nshell.domain.filesystem:filesystem-executable-p filesystem)
                     #P"/definitely/not/a/nshell-executable")
                  :to-be-falsy)
            (expect (funcall
                     (nshell.domain.filesystem:filesystem-executable-p filesystem)
                     nil)
                    :to-be-falsy))))))
  (it "vi-mode-flag-values-control-mode" "The vi-mode environment flag accepts explicit truthy values and rejects disabled values." (expect (nshell.presentation::%vi-mode-flag-enabled-p nil) :to-be-falsy) (expect (nshell.presentation::%vi-mode-flag-enabled-p "") :to-be-falsy) (expect (nshell.presentation::%vi-mode-flag-enabled-p "0") :to-be-falsy) (expect (nshell.presentation::%vi-mode-flag-enabled-p "false") :to-be-falsy) (expect (nshell.presentation::%vi-mode-flag-enabled-p "no") :to-be-falsy) (expect (nshell.presentation::%vi-mode-flag-enabled-p "1") :to-be-truthy) (expect (nshell.presentation::%vi-mode-flag-enabled-p "yes") :to-be-truthy))
  (it "repl-filesystem-boundary-uses-host-kit"
    "The REPL filesystem boundary distinguishes files from directories."
    (host-kit:with-temporary-directory (directory)
      (let ((file (merge-pathnames "entry.txt" directory)))
        (host-kit:write-file-string "entry" file)
        (expect (and (probe-file file)
                     (not (host-kit:directory-pathname-p file)))
                :to-be-truthy)
        (expect (and (probe-file directory)
                     (host-kit:directory-pathname-p directory))
                :to-be-truthy)
        (expect (probe-file "/definitely/not/a/nshell-file")
                :to-be-falsy)
        (expect (host-kit:directory-exists-p "/definitely/not/a/nshell-directory")
                :to-be-falsy)))))
