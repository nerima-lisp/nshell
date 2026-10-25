(in-package #:nshell/test)

(describe "completion-rules-tests"
  (it "cd-completes-directories-integration"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "cd ")))
      (expect 1 :to-equal (length candidates))
      (expect :directory :to-be (nshell.domain.completion:candidate-kind (first candidates)))))

  (it "command-flags-are-completed"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "type --")))
      (assert-completion-texts-include candidates "--help")))

  (it "type-command-flags-are-completed"
    (with-seeded-completion-knowledge-base (kb)
      (let ((candidates (nshell.domain.completion:complete
                         kb
                         "type --")))
        (assert-completion-texts-include candidates "--query" "--help"))
      (let ((candidates (nshell.domain.completion:complete
                         kb
                         "type -")))
        (assert-completion-texts-include candidates "-q" "-t"))))

  (it "builtin-command-metadata-follows-runtime-specs"
    (with-seeded-completion-knowledge-base (kb)
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "string co")
        "collect")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "string re")
        "replace" "repeat")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "string su")
        "sub")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "string --co")
        "--count")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "string -N")
        "-N")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "alias -")
        "-e" "-q")
      (assert-completion-texts-for
          '("--color=always" "--color=auto")
          kb
          "type --color=a")))

  (it "complete-command-flags-are-completed"
    (with-seeded-completion-knowledge-base (kb)
      (let ((long-options (completion-texts
                           (nshell.domain.completion:complete kb "complete --")))
            (short-options (completion-texts
                            (nshell.domain.completion:complete kb "complete -"))))
        (assert-texts-include long-options
          "--long-option" "--short-option" "--arguments" "--erase")
        (assert-texts-include short-options
          "-l" "-s" "-a" "-e"))))

  (it "command-completion-includes-type"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "ty")))
      (assert-completion-texts-include candidates "type")
      (assert-completion-candidate "type" candidates
                                   :kind :command
                                   :description "show command type")))

  (it "command-completion-includes-common-builtins"
    (dolist (case '(("he" "help" "show help")
                    ("his" "history" "show and manage command history")
                    ("str" "string" "manipulate strings")
                    ("ec" "echo" "print arguments; use $NAME or ,EXPR for S-expression values")
                    ("pw" "pwd" "print working directory")
                    ("ex" "exit" "exit the shell")
                    ("so" "source" "execute commands from file")
                    ("re" "read" "read line of input")
                    ("fu" "function" "define shell functions with defun")
                    ("co" "contains" "test whether a value is present")
                    ("no" "not" "invert command status")))
      (destructuring-bind (prefix text description) case
        (let ((candidates (nshell.domain.completion:rule-complete
                           nshell.domain.completion::*built-in-rule-knowledge-base*
                           prefix)))
          (assert-completion-texts-include candidates text)
                        (expect description :to-equal (nshell.domain.completion:candidate-description
                        (completion-candidate-by-text text candidates)))))))

  (it "command-completion-includes-runtime-aliases-and-functions"
    (let ((aliases (make-hash-table :test #'equal))
          (functions (make-hash-table :test #'equal)))
      (setf (gethash "ll" aliases) "ls -l"
            (gethash "local-tool" functions) "() { echo ok; }")
      (let ((candidates
              (nshell.domain.completion:complete
               (nshell.domain.completion:make-empty-knowledge-base)
               "l"
               :alias-table aliases
               :function-table functions)))
        (assert-completion-candidate "ll" candidates
                                     :kind :command
                                     :description "alias")
        (assert-completion-candidate "local-tool" candidates
                                     :kind :command
                                     :description "function"))))

  (it "complete-includes-runtime-alias-and-function-candidates"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base))
          (alias-table (make-hash-table :test #'equal))
          (function-table (make-hash-table :test #'equal)))
      (setf (gethash "zz-runtime-zeta" alias-table) t
            (gethash "zz-runtime-alpha" function-table) t)
      (expect '("zz-runtime-alpha" "zz-runtime-zeta")
              :to-equal
              (completion-texts
               (nshell.domain.completion:complete
                kb
                "zz-runtime-"
                :alias-table alias-table
                :function-table function-table)))))

  (it "complete-filters-runtime-command-candidates-by-prefix"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base))
          (alias-table (make-hash-table :test #'equal))
          (function-table (make-hash-table :test #'equal)))
      (setf (gethash "zz-runtime-alpha" alias-table) t
            (gethash "zz-other-function" function-table) t)
      (expect '("zz-runtime-alpha")
              :to-equal
              (completion-texts
               (nshell.domain.completion:complete
                kb
                "zz-runtime-a"
                :alias-table alias-table
                :function-table function-table)))))

  (it "complete-ignores-empty-runtime-command-tables"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base))
          (empty-table (make-hash-table :test #'equal)))
      (expect (nshell.domain.completion:complete
               kb
               "zz-runtime-"
               :alias-table nil
               :function-table empty-table)
              :to-be-null)))

  (it "complete-deduplicates-runtime-command-candidates"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base))
          (alias-table (make-hash-table :test #'equal))
          (function-table (make-hash-table :test #'equal)))
      (setf (gethash "zz-runtime-shared" alias-table) t
            (gethash "zz-runtime-shared" function-table) t
            (gethash "echo" alias-table) t
            (gethash "echo" function-table) t)
      (let ((runtime-candidates
              (nshell.domain.completion:complete
               kb
               "zz-runtime-s"
               :alias-table alias-table
               :function-table function-table))
            (catalog-candidates
              (nshell.domain.completion:complete
               kb
               "echo"
               :alias-table alias-table
               :function-table function-table)))
        (expect '("zz-runtime-shared")
                :to-equal
                (completion-texts runtime-candidates))
        (expect '("echo")
                :to-equal
                (completion-texts catalog-candidates))
        (expect "print arguments; use $NAME or ,EXPR for S-expression values"
                :to-equal
                (nshell.domain.completion:candidate-description
                 (first catalog-candidates))))))

  (it "rule-completion-candidates-carry-descriptions"
    (let* ((candidates (nshell.domain.completion:rule-complete
                        nshell.domain.completion::*built-in-rule-knowledge-base*
                        "git st")))
      (assert-completion-candidate "status" candidates
                                   :kind :option
                                   :description "show working tree status")))

  (it "rule-completion-includes-common-external-command-metadata"
    (let* ((commands (nshell.domain.completion:rule-complete
                      nshell.domain.completion::*built-in-rule-knowledge-base*
                      "ku"))
           (kubectl (completion-candidate-by-text "kubectl" commands))
           (subcommands (completion-texts
                         (nshell.domain.completion:rule-complete
                          nshell.domain.completion::*built-in-rule-knowledge-base*
                          "git sw")))
           (gh-subcommands (completion-texts
                            (nshell.domain.completion:rule-complete
                             nshell.domain.completion::*built-in-rule-knowledge-base*
                             "gh pr")))
           (flags (completion-texts
                   (nshell.domain.completion:rule-complete
                    nshell.domain.completion::*built-in-rule-knowledge-base*
                    "docker --t")))
           (curl-flags (completion-texts
                        (nshell.domain.completion:rule-complete
                         nshell.domain.completion::*built-in-rule-knowledge-base*
                         "curl --req")))
           (rg-flags (completion-texts
                      (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "rg --colo"))))
      (expect (null kubectl) :to-be-falsy)
      (expect "control Kubernetes clusters" :to-equal (nshell.domain.completion:candidate-description kubectl))
      (assert-texts-include subcommands "switch")
      (assert-texts-include gh-subcommands "pr")
      (assert-texts-include flags "--tls" "--tlscert")
      (assert-texts-include curl-flags "--request")
      (assert-texts-include rg-flags "--color")))

  (it "repl-completion-includes-common-external-option-values"
    (with-seeded-completion-knowledge-base (kb)
      (assert-completion-texts-cases kb
        (:input "cargo --color=a" :expected ("--color=always" "--color=auto"))
        (:input "kubectl -o=y" :expected ("-o=yaml"))
        (:input "curl --request=D" :expected ("--request=DELETE"))
        (:input "rg --color=a" :expected ("--color=always" "--color=ansi" "--color=auto")))))

  (it "repl-completion-includes-common-external-separate-option-values"
    (with-seeded-completion-knowledge-base (kb)
      (assert-completion-texts-cases kb
        (:input "cargo --color a" :expected ("always" "auto"))
        (:input "kubectl -o y" :expected ("yaml"))
        (:input "curl -X D" :expected ("DELETE"))
        (:input "rg --color a" :expected ("always" "ansi" "auto")))))

  (it "help-derived-command-metadata-feeds-knowledge-base-completion"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command-from-help
       kb
       "zz-helped"
       (format nil "Usage: zz-helped [OPTIONS] <COMMAND>~%~
                  Commands:~%~
                    run                   execute the task~%~
                    test                  verify the task~%~
                  Options:~%~
                    -h, --help            Show help~%~
                    -o, --output FILE     Write output~%~
                        --color=WHEN      Color mode (always|auto|never)~%")
       :description "help-derived test command")
      (expect (member "zz-helped"
                  (completion-texts-for kb "zz-h")
                  :test #'string=) :to-be-truthy)
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "zz-helped r")
        "run")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "zz-helped t")
        "test")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "zz-helped --h")
        "--help")
      (assert-completion-texts-include
          (nshell.domain.completion:complete kb "zz-helped -")
        "-o")
      (assert-completion-texts-cases kb
        (:input "zz-helped --color=a" :expected ("--color=always" "--color=auto"))
        (:input "zz-helped --color n" :expected ("never")))))

  (it "repl-completion-warms-catalogued-command-help-and-reuses-the-cache"
    (let ((help-text (format nil "Usage: cargo [OPTIONS]~%~
                                 Options:~%~
                                 -h, --help            Show help~%~
                                 -o, --output FILE     Write output~%~
                                 --color=WHEN      Color mode (always|auto|never)~%")))
      (with-repl-completion-help-fetcher (fetch-count help-text)
        (with-repl-completion-refresh (state candidates "cargo -")
          (declare (ignore state))
          (expect 1 :to-equal fetch-count)
          (assert-completion-candidate "--help" candidates :kind :option)
          (assert-completion-candidate "-o" candidates :kind :option))
        (with-repl-completion-refresh (state candidates "cargo --color a")
          (declare (ignore state))
          (expect 1 :to-equal fetch-count)
          (assert-completion-texts-include candidates "always" "auto")))))

  (it "repl-completion-enriches-catalogued-external-command-help"
    (let ((help-text (format nil "Usage: git [OPTIONS] [COMMAND]~%~
                                 Options:~%~
                                 -h, --help            Show help~%~
                                 --dry-run        Preview changes without applying them~%")))
      (with-repl-completion-help-fetcher (fetch-count help-text)
        (with-repl-completion-refresh (state candidates "git --d")
          (declare (ignore state))
          (expect 1 :to-equal fetch-count)
          (assert-completion-candidate "--dry-run" candidates :kind :option)))))

  (it "repl-completion-caches-missing-command-help-lookups"
    (let ((catalog (make-hash-table :test #'equal)))
      (setf (gethash "zz-missing" catalog) t)
      (let ((nshell.presentation::*completion-help-catalog-command-cache* catalog))
        (with-repl-completion-help-fetcher
            (fetch-count "zz-missing: command completed without help metadata" :exit-code 1)
          (with-repl-completion-refresh (state candidates "zz-missing --")
            (declare (ignore state candidates))
            (expect 1 :to-equal fetch-count))
          (with-repl-completion-refresh (state candidates "zz-missing --")
            (declare (ignore state candidates))
            (expect 1 :to-equal fetch-count))))))

  (it "repl-completion-fetches-help-for-available-uncatalogued-commands"
    (with-repl-completion-help-fetcher
        (fetch-count
         (format nil "Usage: zz-uncatalogued~%Options:~%  --from-help"))
      (repl-test-set-env "NSHELL_COMPLETION_HELP_ALLOWLIST" "zz-uncatalogued")
      (with-repl-completion-refresh (state candidates "zz-uncatalogued --")
        (declare (ignore state))
        (expect 1 :to-equal fetch-count)
        (assert-completion-candidate "--from-help" candidates :kind :option))))

  (it "repl-completion-rejects-oversized-help-output-before-parsing"
    (with-repl-test-state
      (let ((nshell.presentation::*completion-help-max-output-chars* 16)
            (help-text (format nil "Usage: zz-large~%~a"
                               (make-string 32 :initial-element #\x))))
        (expect :missing :to-equal
          (nshell.presentation::%completion-help-cache-help-text
           "zz-large" help-text 0))
        (expect nil :to-be
          (nshell.domain.completion:kb-command-present-p
           nshell.presentation::*kb* "zz-large")))))

  (it "completion-help-validates-command-help-shapes-and-allowlist"
    (with-repl-test-state
      (expect '("cargo" "curl" "docker" "find" "gh" "git" "go" "grep" "jq"
                "kubectl" "make" "nix" "npm" "pip" "python" "rg" "ssh" "tar")
              :to-equal
              (nshell.presentation::%completion-help-default-command-names))
      (expect t :to-be
        (nshell.presentation::%completion-help-allowed-command-p "git"))
      (expect nil :to-be
        (nshell.presentation::%completion-help-allowed-command-p "zz-unlisted"))
      (repl-test-set-env "NSHELL_COMPLETION_HELP_ALLOWLIST" "")
      (expect nil :to-be
        (nshell.presentation::%completion-help-allowed-command-p "git"))
      (repl-test-set-env "NSHELL_COMPLETION_HELP_ALLOWLIST" "zz-custom")
      (expect t :to-be
        (nshell.presentation::%completion-help-allowed-command-p "zz-custom"))
      (expect nil :to-be (nshell.presentation::%completion-help-allowed-command-p "git"))
      (let ((xdg-home "/absolute/cache"))
        (with-temporary-function
            ('nshell.infrastructure.acl:current-environment-value
             (lambda (name)
               (when (string= name "XDG_CACHE_HOME")
                 xdg-home)))
          (expect (merge-pathnames #P"nshell/completion-help/"
                                   #P"/absolute/cache/")
                  :to-equal
                  (nshell.presentation::%completion-help-cache-directory))
          (setf xdg-home "relative/cache")
          (expect (merge-pathnames #P".cache/nshell/completion-help/"
                                   (user-homedir-pathname))
                  :to-equal
                  (nshell.presentation::%completion-help-cache-directory))))
      (expect nil :to-be
        (nshell.presentation::%completion-help-command-parts ""))
      (expect nil :to-be
        (nshell.presentation::%completion-help-command-parts "echo; rm"))
      (expect '("echo" "hello") :to-equal
        (nshell.presentation::%completion-help-command-parts "echo  hello"))
      (expect nil :to-be
        (nshell.presentation::%completion-help-text-p nil))
      (expect nil :to-be
        (nshell.presentation::%completion-help-text-p "plain output"))
      (expect (nshell.presentation::%completion-help-text-p "Options: --verbose")
              :to-be-truthy)))

  (it "completion-help-caches-only-successful-text"
    (with-repl-test-state
      (let ((command "zz-cache-policy")
            (help-text "Options: --help"))
        (expect :missing :to-equal
          (nshell.presentation::%completion-help-cache-help-text
           command "Options: --help" 1))
        (expect nil :to-be
          (nshell.domain.completion:kb-command-present-p
           nshell.presentation::*kb* command))
        (expect :missing :to-equal
          (nshell.presentation::%completion-help-cache-help-text
           command 42 0))
        (expect :loaded :to-equal
          (nshell.presentation::%completion-help-cache-help-text
           command help-text 0))
        (expect (nshell.domain.completion:kb-command-present-p
                 nshell.presentation::*kb* command)
                :to-be-truthy)
        (host-kit:with-temporary-directory (directory)
          (let ((fetch-count 0)
                (cache-file
                  (nshell.presentation::%completion-help-cache-file
                   command directory)))
            (multiple-value-bind (status output)
                (nshell.presentation::%completion-help-fetch-cache-result
                 command "/test/bin/zz-cache-policy" 1 directory
                 (lambda (name path)
                   (declare (ignore name path))
                   (incf fetch-count)
                   (values help-text 0)))
              (expect :loaded :to-equal status)
              (expect help-text :to-equal output))
            (expect 1 :to-equal fetch-count)
            (multiple-value-bind (status output)
                (nshell.presentation::%completion-help-fetch-cache-result
                 command "/test/bin/zz-cache-policy" 1 directory
                 (lambda (name path)
                   (declare (ignore name path))
                   (incf fetch-count)
                   (values help-text 0)))
              (expect :loaded :to-equal status)
              (expect help-text :to-equal output))
            (expect 1 :to-equal fetch-count)
            (with-open-file (stream cache-file :direction :output
                                    :if-exists :supersede
                                    :if-does-not-exist :create)
              (write-line "NSHELL-COMPLETION-HELP-1" stream)
              (write-line "ZZZZZZ" stream))
            (multiple-value-bind (status output)
                (nshell.presentation::%completion-help-fetch-cache-result
                 command "/test/bin/zz-cache-policy" 1 directory
                 (lambda (name path)
                   (declare (ignore name path))
                   (incf fetch-count)
                   (values help-text 0)))
              (expect :loaded :to-equal status)
              (expect help-text :to-equal output))
            (expect 2 :to-equal fetch-count))))))

  (it "completion-help-cache-writer-replaces-symlinks-without-changing-target"
    (with-repl-test-state
      (host-kit:with-temporary-directory (directory)
        (let* ((command "zz-cache-symlink")
               (resolved-path "/test/bin/zz-cache-symlink")
               (mtime 123)
               (help-text "Options: --learned")
               (cache-file
                 (nshell.presentation::%completion-help-cache-file
                  command directory))
               (target-file (merge-pathnames "symlink-target.txt" directory)))
          (host-kit:write-file-string "target unchanged" target-file)
          (ensure-directories-exist cache-file)
          (sb-posix:symlink (namestring target-file) (namestring cache-file))
          (nshell.presentation::%completion-help-write-cache
           command resolved-path mtime help-text directory)
          (expect "target unchanged"
                  :to-equal (uiop:read-file-string target-file))
          (expect help-text
                  :to-equal
                  (nshell.presentation::%completion-help-read-cache
                   command resolved-path mtime directory))))))
  (it "completion-help-cache-reader-fetches-on-symlink"
    (with-repl-test-state
      (host-kit:with-temporary-directory (directory)
        (let* ((command "zz-cache-symlink-read")
               (resolved-path "/test/bin/zz-cache-symlink-read")
               (mtime 123)
               (help-text "Options: --from-fetch")
               (cache-file
                 (nshell.presentation::%completion-help-cache-file
                  command directory))
               (target-file (merge-pathnames "cache-target.txt" directory))
               (fetch-count 0))
          (host-kit:write-file-string "target remains unchanged" target-file)
          (ensure-directories-exist cache-file)
          (sb-posix:symlink (namestring target-file) (namestring cache-file))
          (multiple-value-bind (status output)
              (nshell.presentation::%completion-help-fetch-cache-result
               command resolved-path mtime directory
               (lambda (name path)
                 (declare (ignore name path))
                 (incf fetch-count)
                 (values help-text 0)))
            (expect :loaded :to-equal status)
            (expect help-text :to-equal output))
          (expect 1 :to-equal fetch-count)
          (expect "target remains unchanged"
                  :to-equal (uiop:read-file-string target-file))
          (expect help-text
                  :to-equal
                  (nshell.presentation::%completion-help-read-cache
                   command resolved-path mtime directory))))))

  (it "completion-help-rejects-truncated-output"
    (with-repl-test-state
      (let ((command "zz-truncated-help")
            (help-text "Usage: zz-truncated-help"))
        (host-kit:with-temporary-directory (directory)
          (let ((cache-file
                  (nshell.presentation::%completion-help-cache-file
                   command directory))
                (fetch-count 0))
            (multiple-value-bind (status output)
                (nshell.presentation::%completion-help-fetch-cache-result
                 command "/test/bin/zz-truncated-help" 1 directory
                 (lambda (name path)
                   (declare (ignore name path))
                   (incf fetch-count)
                   (values help-text 0 t)))
              (expect :missing :to-equal status)
              (expect nil :to-be output))
            (expect 1 :to-equal fetch-count)
            (expect nil :to-be (probe-file cache-file))))
        (expect :missing :to-equal
          (nshell.presentation::%completion-help-cache-help-text
           command help-text 0 t))
        (expect nil :to-be
          (nshell.domain.completion:kb-command-present-p
           nshell.presentation::*kb* command)))))

  (it "repl-completion-returns-before-delayed-help-and-invalidates-stale-facts"
    (with-repl-test-state
      (repl-test-set-env "NSHELL_COMPLETION_HELP_ALLOWLIST" "zz-delayed")
      (host-kit:with-temporary-directory (cache-directory)
        (let* ((resolved-path "/test/bin/zz-delayed")
               (mtime 1)
               (help-text
                 (format nil "Usage: zz-delayed~%Options:~%  --old Old option~%"))
               (fetch-count 0)
               (fetch-started (sb-thread:make-semaphore :count 0))
               (release-fetch (sb-thread:make-semaphore :count 0))
               (release-signaled-p nil)
               (nshell.presentation::*completion-help-command-info-function*
                 (lambda (command)
                   (declare (ignore command))
                   (list resolved-path mtime)))
               (nshell.presentation::*completion-help-cache-directory-override*
                 cache-directory)
               (nshell.presentation::*completion-help-fetcher*
                 (lambda (command path)
                   (declare (ignore command path))
                   (incf fetch-count)
                   (when (= fetch-count 1)
                     (sb-thread:signal-semaphore fetch-started)
                     (unless (sb-thread:wait-on-semaphore
                              release-fetch :timeout 3)
                       (error "Timed out waiting to release delayed help fetch")))
                   (when (= fetch-count 4)
                     (error "synthetic help failure"))
                   (values help-text 0))))
          (nshell.domain.completion:kb-add-command-from-help
           nshell.presentation::*kb*
           "zz-delayed"
           (format nil "Usage: zz-delayed~%Options:~%  --static Static option~%"))
          (with-repl-input-state
              (:buffer "zz-delayed --"
               :cursor-pos (length "zz-delayed --"))
            (labels ((flag-texts ()
                       (completion-texts
                        (nshell.domain.completion:complete
                         nshell.presentation::*kb* "zz-delayed --")))
                     (await-result ()
                       (loop repeat 300
                             do (nshell.presentation::%apply-completion-help-results)
                             unless (eq :loading
                                        (getf
                                         (gethash "zz-delayed"
                                                  nshell.presentation::*completion-help-cache*)
                                         :status))
                               return t
                             do (sleep 0.01)
                             finally (return nil)))
                     (release-worker ()
                       (unless release-signaled-p
                         (setf release-signaled-p t)
                         (sb-thread:signal-semaphore release-fetch))))
              (unwind-protect
                   (progn
                     (let ((started-at (get-internal-real-time)))
                       (nshell.presentation::%refresh-completion-session-state
                        nshell.presentation::*input-state*)
                       (expect
                        (< (/ (- (get-internal-real-time) started-at)
                              internal-time-units-per-second)
                           1)
                        :to-be-truthy))
                     (let* ((fetch-started-p
                              (sb-thread:wait-on-semaphore
                               fetch-started :timeout 1))
                            (cache-state
                              (gethash
                               "zz-delayed"
                               nshell.presentation::*completion-help-cache*))
                            (channel
                              nshell.presentation::*completion-help-result-channel*)
                            (queued-results
                              (sb-thread:with-mutex
                                  ((nshell.presentation::completion-help-result-channel-mutex
                                    channel))
                                (mapcar
                                 (lambda (result)
                                   (list :status (getf result :status)
                                         :condition (getf result :condition)))
                                 (copy-list
                                  (nshell.presentation::completion-help-result-channel-results
                                   channel))))))
                       (unless fetch-started-p
                         (format *error-output*
                                 "completion help diagnostic: state=~s results=~s~%"
                                 (list :status (getf cache-state :status)
                                       :path (getf cache-state :path)
                                       :mtime (getf cache-state :mtime))
                                 queued-results))
                       (unless fetch-started-p (error "completion help fetch did not start: state=~s results=~s" (list :status (getf cache-state :status) :path (getf cache-state :path) :mtime (getf cache-state :mtime)) queued-results)))
                     (expect :loading :to-be
                       (getf
                        (gethash "zz-delayed"
                                 nshell.presentation::*completion-help-cache*)
                        :status))
                     (assert-texts-include (flag-texts) "--static")
                     (assert-texts-exclude (flag-texts) "--old")
                     (release-worker)
                     (expect t :to-be (await-result))
                     (expect 1 :to-equal fetch-count)
                     (assert-texts-include (flag-texts) "--static" "--old")
                     (setf mtime 2
                           help-text
                           (format nil "Usage: zz-delayed~%Options:~%  --new New option~%"))
                     (nshell.presentation::%refresh-completion-session-state
                      nshell.presentation::*input-state*)
                     (expect t :to-be (await-result))
                     (expect 2 :to-equal fetch-count)
                     (assert-texts-include (flag-texts) "--static" "--new")
                     (assert-texts-exclude (flag-texts) "--old")
                     (setf resolved-path "/test/bin/zz-delayed-v2"
                           help-text
                           (format nil "Usage: zz-delayed~%Options:~%  --third Third option~%"))
                     (nshell.presentation::%refresh-completion-session-state
                      nshell.presentation::*input-state*)
                     (expect t :to-be (await-result))
                     (expect 3 :to-equal fetch-count)
                     (assert-texts-include (flag-texts) "--static" "--third")
                     (assert-texts-exclude (flag-texts) "--new")
                     (setf mtime 3)
                     (nshell.presentation::%refresh-completion-session-state
                      nshell.presentation::*input-state*)
                     (expect t :to-be (await-result))
                     (expect 4 :to-equal fetch-count)
                     (expect :missing :to-be
                       (getf
                        (gethash "zz-delayed"
                                 nshell.presentation::*completion-help-cache*)
                        :status))
                     (assert-texts-include (flag-texts) "--static")
                     (assert-texts-exclude (flag-texts) "--third"))
                (release-worker))))))))

  (it "repl-completion-does-not-fetch-help-for-unavailable-commands"
    (with-repl-completion-help-fetcher
        (fetch-count "Usage: should-not-run"
         :command-available-p
         (function
           (lambda (command)
             (declare (ignore command))
             nil)))
      (repl-test-set-env "NSHELL_COMPLETION_HELP_ALLOWLIST" "zz-unavailable")
      (with-repl-completion-refresh (state candidates "zz-unavailable --")
        (declare (ignore state candidates))
        (expect 0 :to-equal fetch-count))))

  (it "repl-completion-ignores-escaped-command-and-subcommand-tokens"
    (with-repl-completion-help-fetcher
        (fetch-count "Usage: should-not-run")
      (repl-test-set-env "NSHELL_COMPLETION_HELP_ALLOWLIST" "git")
      (let* ((command-info-count 0)
            (nshell.presentation::*completion-help-command-info-function*
              (lambda (name)
                (declare (ignore name))
                (incf command-info-count)
                nil))
            (input
              "git\\ -c\\ alias.foo=!touch\\ foo\\ marker --"))
        (expect "git -c alias.foo=!touch foo marker"
                :to-equal
                (nshell.domain.completion:completion-context-command
                 (nshell.domain.completion:completion-context-for input)))
        (with-repl-completion-refresh (state candidates input)
          (declare (ignore state candidates))
          (expect 0 :to-equal command-info-count)
          (expect 0 :to-equal fetch-count))
        (let ((observed-argument-words nil)
              (resolver-call-count 0)
              (nshell.presentation::*completion-help-command-info-function*
                (lambda (name)
                  (declare (ignore name))
                  nil)))
          (with-temporary-function
              ('nshell.domain.completion:kb-resolve-command-path
               (lambda (knowledge-base command argument-words prefix)
                 (declare (ignore knowledge-base prefix))
                 (setf observed-argument-words argument-words)
                 (incf resolver-call-count)
                 (format nil "~a status" command)))
            (nshell.presentation::%warm-command-completion-help-path
             nshell.presentation::*kb* "git"
             '("status" "origin status") "")
            (expect '("status") :to-equal observed-argument-words)
            (expect 2 :to-equal resolver-call-count)
            (expect 0 :to-equal fetch-count))))))

  (it "repl-completion-hides-common-external-mutually-exclusive-options"
    (with-seeded-completion-knowledge-base (kb)
      (let ((after-quiet (completion-texts
                          (nshell.domain.completion:complete kb "cargo --quiet -"))))
        (assert-texts-exclude after-quiet "--verbose" "-v")
        (assert-texts-include after-quiet "--help"))
      (let ((after-all-namespaces
              (completion-texts
               (nshell.domain.completion:complete kb "kubectl --all-namespaces --"))))
        (assert-texts-exclude after-all-namespaces "--namespace")
        (assert-texts-include after-all-namespaces "--output"))))

  (it "builtin-rule-facts-are-single-sourced-from-catalogs"
    (let ((seen (make-hash-table :test #'equal))
          (duplicates '()))
      (dolist (fact (nshell.domain.completion::builtin-rule-facts))
        (let ((key (prin1-to-string fact)))
          (if (gethash key seen)
              (pushnew key duplicates :test #'string=)
              (setf (gethash key seen) t))))
      (expect duplicates :to-be-null))
    (let ((git-status (completion-texts
                       (nshell.domain.completion:rule-complete
                        nshell.domain.completion::*built-in-rule-knowledge-base*
                        "git st")))
          (type-help (completion-texts
                      (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "type --"))))
      (assert-texts-include git-status "status")
      (assert-texts-include type-help "--help")))

  (it "rule-completion-dedupes-multiple-proof-paths"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'nshell.domain.completion::completes
                                           :args '("git" "status")))
      (nshell.domain.completion:assert-rule!
       kb
       (nshell.domain.completion:make-rule :head '(nshell.domain.completion::completes
                                                   "git"
                                                   "status")
                                           :body '()))
      (let ((candidates (nshell.domain.completion:rule-complete kb "git st")))
        (expect '("status") :to-equal (completion-texts candidates)))))

  (it "complete-uses-provided-rule-knowledge-base"
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'nshell.domain.completion::completes
                                           :args '("zz-only" "--custom")))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'nshell.domain.completion::describes
                                           :args '("zz-only" "custom command")))
      (expect '("zz-only") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "zz-o")))
      (expect '("--custom") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "zz-only --")))
      (expect (nshell.domain.completion:complete kb "git st") :to-be-null)))

  (it "rule-completion-skips-leading-assignment-words"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "FOO=bar git st")))
      (assert-completion-texts-include candidates "status")))

  (it "rule-completion-completes-command-after-leading-assignment-words"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "FOO=bar gi")))
      (assert-completion-texts-include candidates "git")
      (assert-completion-texts-exclude candidates "status")))

  (it "rule-completion-uses-current-pipeline-command"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "echo ready | git st")))
      (assert-completion-texts-include candidates "status")))

  (it "rule-completion-treats-redirection-targets-as-files"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "git > st")))
      (expect 1 :to-equal (length candidates))
      (expect "st" :to-equal (nshell.domain.completion:candidate-text (first candidates)))
      (expect :file :to-be (nshell.domain.completion:candidate-kind (first candidates)))
      (assert-completion-texts-exclude candidates "status")))

  (it "rule-completion-treats-empty-redirection-targets-as-files"
    (dolist (line '("git >" "git > " "git >> " "git < "))
      (let ((candidates (nshell.domain.completion:rule-complete
                         nshell.domain.completion::*built-in-rule-knowledge-base*
                         line)))
        (expect 1 :to-equal (length candidates))
        (expect :file :to-be (nshell.domain.completion:candidate-kind (first candidates))))))

  (it "complete-redirection-targets-from-filesystem"
    (with-test-file-filesystem
        ((lambda (dir)
           (declare (ignore dir))
           (list #p"stderr.log" #p"stdout.txt" #p"notes.txt"))
         (lambda (dir)
           (declare (ignore dir))
           (list #p"staging/")))
      (let* ((candidates (nshell.domain.completion:complete
                          nshell.domain.completion::*built-in-rule-knowledge-base*
                          "echo > st"
                          :filesystem *completion-test-filesystem*))
             (texts (completion-texts candidates))
             (kinds (mapcar #'nshell.domain.completion:candidate-kind candidates)))
        (expect '("staging/" "stderr.log" "stdout.txt") :to-equal texts)
        (expect '(:directory :file :file) :to-equal kinds))))

  (it "complete-cd-targets-from-filesystem-directories-only"
    (with-test-file-filesystem
        ((lambda (dir)
           (declare (ignore dir))
           (list #p"src.log"))
         (lambda (dir)
           (declare (ignore dir))
           (list #p"src/" #p"sandbox/")))
      (let* ((candidates (nshell.domain.completion:complete
                          nshell.domain.completion::*built-in-rule-knowledge-base*
                          "cd s"
                          :filesystem *completion-test-filesystem*))
             (texts (completion-texts candidates))
             (kinds (mapcar #'nshell.domain.completion:candidate-kind candidates)))
        (expect '("sandbox/" "src/") :to-equal texts)
        (expect (every (lambda (kind) (eq kind :directory)) kinds) :to-be-truthy))))

  (it "complete-path-like-command-arguments-from-filesystem"
    (with-test-file-filesystem
        ((lambda (dir)
           (declare (ignore dir))
           (list #p".env" #p"~config" #p"main.lisp"))
         (lambda (dir)
           (declare (ignore dir))
           (list #p"module/")))
      (let ((slash-texts
              (completion-texts
               (nshell.domain.completion:complete
                nshell.domain.completion::*built-in-rule-knowledge-base*
                "echo src/m"
                :filesystem *completion-test-filesystem*)))
            (dot-texts
              (completion-texts
               (nshell.domain.completion:complete
                nshell.domain.completion::*built-in-rule-knowledge-base*
                "echo .e"
                :filesystem *completion-test-filesystem*)))
            (tilde-texts
              (completion-texts
               (nshell.domain.completion:complete
                nshell.domain.completion::*built-in-rule-knowledge-base*
                "echo ~c"
                :filesystem *completion-test-filesystem*))))
        (expect '("src/module/" "src/main.lisp") :to-equal slash-texts)
        (expect '(".env") :to-equal dot-texts)
        (expect '("~config") :to-equal tilde-texts))))

  (it "complete-source-targets-from-filesystem"
    (with-test-file-filesystem
        ((lambda (dir)
           (declare (ignore dir))
           (list #p"init.lisp" #p"install.sh" #p"readme.md"))
         (lambda (dir)
           (declare (ignore dir))
           (list #p"included/")))
      (dolist (line '("source in" ". in"))
        (let ((texts (completion-texts
                      (nshell.domain.completion:complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       line
                       :filesystem *completion-test-filesystem*))))
          (expect '("included/" "init.lisp" "install.sh") :to-equal texts)))))

  (it "complete-source-targets-from-filesystem-after-trailing-space"
    (with-test-file-filesystem
        ((lambda (dir)
           (declare (ignore dir))
           (list #p"init.lisp" #p"install.sh" #p"readme.md"))
         (lambda (dir)
           (declare (ignore dir))
           (list #p"included/")))
      (dolist (line '("source " ". "))
        (let ((texts (completion-texts
                      (nshell.domain.completion:complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       line
                       :filesystem *completion-test-filesystem*))))
          (expect '("included/" "init.lisp" "install.sh" "readme.md") :to-equal texts)))))

  (it "rule-completion-keeps-quoted-arguments-out-of-prefix"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "git commit -m \"hello world\" --")))
      (assert-completion-texts-include candidates "--help")))

  (it "rule-completion-keeps-escaped-arguments-out-of-prefix"
    (let ((candidates (nshell.domain.completion:rule-complete
                       nshell.domain.completion::*built-in-rule-knowledge-base*
                       "git add my\\ file st")))
      (assert-completion-texts-include candidates "status")))

  (it "rule-completion-preserves-descriptions-for-multiple-candidates"
    (let ((kb (make-empty-rule-kb)))
      (dolist (command (quote ("git" "gitk")))
        (nshell.domain.completion:assert-fact!
          kb
          (nshell.domain.completion:make-fact
            :predicate (quote nshell.domain.completion:completes)
            :args (list command ""))))
      (nshell.domain.completion:assert-fact!
        kb
        (nshell.domain.completion:make-fact
          :predicate (quote nshell.domain.completion:describes)
          :args (quote ("git" "version control"))))
      (nshell.domain.completion:assert-fact!
        kb
        (nshell.domain.completion:make-fact
          :predicate (quote nshell.domain.completion:describes)
          :args (quote ("gitk" "graphical history browser"))))
      (let ((candidates (nshell.domain.completion:rule-complete kb "git")))
        (expect (quote ("git" "gitk")) :to-equal (completion-texts candidates))
        (expect "version control" :to-equal
          (nshell.domain.completion:candidate-description (first candidates)))
        (expect "graphical history browser" :to-equal
          (nshell.domain.completion:candidate-description (second candidates))))))
  (it "completion-help-worker-lifecycle-prevents-overlapping-learning"
  (with-repl-test-state
    (repl-test-set-env "NSHELL_COMPLETION_HELP_ALLOWLIST" "zz-worker-overlap")
    (host-kit:with-temporary-directory (cache-directory)
      (let* ((resolved-path "/test/bin/zz-worker-overlap")
             (mtime 1)
             (fetch-count 0)
             (fetch-count-lock (sb-thread:make-mutex :name "completion help fetch count"))
             (fetch-started (sb-thread:make-semaphore :count 0))
             (release-fetch (sb-thread:make-semaphore :count 0))
             (nshell.presentation::*completion-help-command-info-function*
               (lambda (command)
                 (declare (ignore command))
                 (list resolved-path mtime)))
             (nshell.presentation::*completion-help-cache-directory-override*
               cache-directory)
             (nshell.presentation::*completion-help-fetcher*
               (lambda (command path)
                 (declare (ignore command path))
                 (sb-thread:with-mutex (fetch-count-lock)
                   (incf fetch-count))
                 (sb-thread:signal-semaphore fetch-started)
                 (unless (sb-thread:wait-on-semaphore release-fetch :timeout 3)
                   (error "Timed out waiting to release completion help worker"))
                 (values (format nil "Usage: zz-worker-overlap~%Options:~%  --sample Sample option~%") 0))))
        (labels ((worker-threads ()
                   (remove-if-not
                    (lambda (thread)
                      (string= "nshell completion help zz-worker-overlap"
                               (sb-thread:thread-name thread)))
                    (sb-thread:list-all-threads)))
                 (fetch-count-value ()
                   (sb-thread:with-mutex (fetch-count-lock)
                     fetch-count)))
          (unwind-protect
               (progn
                 (nshell.presentation::%warm-command-completion-help
                  "zz-worker-overlap")
                 (expect (sb-thread:wait-on-semaphore fetch-started :timeout 1) :to-be-truthy)
                 (expect 1 :to-equal (fetch-count-value))
                 (let ((state
                         (gethash "zz-worker-overlap"
                                  nshell.presentation::*completion-help-cache*)))
                   (expect :loading :to-be (getf state :status))
                   (expect 1 :to-equal (getf state :mtime)))
                 (setf mtime 2)
                 (nshell.presentation::%warm-command-completion-help
                  "zz-worker-overlap")
                 (expect nil :to-be
                   (sb-thread:wait-on-semaphore fetch-started :timeout 0.1))
                 (expect 1 :to-equal (fetch-count-value))
                 (let ((state
                         (gethash "zz-worker-overlap"
                                  nshell.presentation::*completion-help-cache*)))
                   (expect :loading :to-be (getf state :status))
                   (expect 1 :to-equal (getf state :mtime))))
            (sb-thread:signal-semaphore release-fetch)
            (sb-thread:signal-semaphore release-fetch)
            (dolist (thread (worker-threads))
              (sb-thread:join-thread thread))
            (nshell.presentation::%completion-help-drain-results)))))))
  (it "completion-help-worker-lifecycle-waits-for-worker-on-repl-exit"
  (with-repl-test-state
    (repl-test-set-env "NSHELL_COMPLETION_HELP_ALLOWLIST" "zz-worker-exit")
    (host-kit:with-temporary-directory (cache-directory)
      (let* ((fetch-count 0)
             (fetch-count-lock (sb-thread:make-mutex :name "completion help exit fetch count"))
             (worker-started (sb-thread:make-semaphore :count 0))
             (release-fetch (sb-thread:make-semaphore :count 0))
             (exit-finished (sb-thread:make-semaphore :count 0))
             (nshell.presentation::*completion-help-command-info-function*
               (lambda (name)
                 (declare (ignore name))
                 (list "/test/bin/zz-worker-exit" 1)))
             (nshell.presentation::*completion-help-cache-directory-override*
               cache-directory)
             (nshell.presentation::*completion-help-fetcher*
               (lambda (name path)
                 (declare (ignore name path))
                 (sb-thread:with-mutex (fetch-count-lock)
                   (incf fetch-count))
                 (sb-thread:signal-semaphore worker-started)
                 (unless (sb-thread:wait-on-semaphore release-fetch :timeout 3)
                   (error "Timed out waiting to release completion help worker"))
                 (values (format nil "Usage: zz-worker-exit~%Options:~%  --sample Sample option~%") 0))))
        (let ((worker nil)
              (exit-thread nil)
              (exit-result :not-returned))
          (unwind-protect
               (progn
                 (nshell.presentation::%warm-command-completion-help
                  "zz-worker-exit")
                 (expect (sb-thread:wait-on-semaphore worker-started :timeout 1) :to-be-truthy)
                 (expect 1 :to-equal
                   (sb-thread:with-mutex (fetch-count-lock)
                     fetch-count))
                 (let ((state
                         (gethash "zz-worker-exit"
                                  nshell.presentation::*completion-help-cache*)))
                   (expect :loading :to-be (getf state :status))
                   (expect 1 :to-equal (getf state :mtime)))
                 (setf worker
                       (find-if
                        (lambda (thread)
                          (string= "nshell completion help zz-worker-exit"
                                   (sb-thread:thread-name thread)))
                        (sb-thread:list-all-threads)))
                 (expect t :to-be (and worker (sb-thread:thread-alive-p worker)))
                 (setf exit-thread
                       (sb-thread:make-thread
                        (lambda ()
                          (setf exit-result
                                (handler-case
                                    (nshell.presentation::run-repl
                                     :load-config-p nil :history-p nil)
                                  (error (condition) condition)))
                          (sb-thread:signal-semaphore exit-finished))
                        :name "nshell test completion help exit"))
                 (let ((exit-finished-before-release
                         (sb-thread:wait-on-semaphore exit-finished :timeout 0.1)))
                   (expect nil :to-be exit-finished-before-release)
                   (expect t :to-be (sb-thread:thread-alive-p worker))
                   (sb-thread:signal-semaphore release-fetch)
                   (unless exit-finished-before-release
                     (expect (sb-thread:wait-on-semaphore exit-finished :timeout 2) :to-be-truthy)))
                 (sb-thread:join-thread exit-thread)
                 (expect 1 :to-equal exit-result)
                 (expect nil :to-be (sb-thread:thread-alive-p worker)))
            (sb-thread:signal-semaphore release-fetch)
            (when exit-thread
              (sb-thread:join-thread exit-thread))
            (when worker
              (sb-thread:join-thread worker))
            (nshell.presentation::%completion-help-drain-results)))))))
)

