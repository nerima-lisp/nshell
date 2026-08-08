(in-package #:nshell/test)

(describe "completion-rules-tests"
  (it "knowledge-base-option-value-completion-dedupes-duplicates"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :flags '("--mode")
       :option-values '(("--mode" "auto" "auto" "always" "always" "never")))
      (expect '("--mode=always" "--mode=auto") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode=a")))
      (expect '("always" "auto") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode a")))))

  (it "knowledge-base-option-value-completion-merges-duplicate-option-specs"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :flags '("--mode")
       :option-values '(("--mode" "auto")
                        ("--mode" "always" "auto")
                        ("--other" "ignored")))
      (expect '("--mode=always" "--mode=auto") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode=a")))
      (expect '("always" "auto") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode a")))))

  (it "knowledge-base-option-values-can-be-added-incrementally"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "tool")
      (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                              :values '("fast" "safe"))
      (expect '("--mode=fast") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode=f")))))

  (it "knowledge-base-add-option-creates-command-entry"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                              :values '("fast" "safe"))
      (expect '("--mode") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --")))
      (expect '("--mode=fast") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode=f")))))

  (it "knowledge-base-add-option-merges-repeated-values"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "tool")
      (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                              :values '("fast" "safe"))
      (nshell.domain.completion:kb-add-option kb "tool" "--mode"
                                              :values '("safe" "slow"))
      (expect '("--mode=fast") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode=f")))
      (expect '("safe" "slow") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode s")))))

  (it "knowledge-base-add-command-merges-repeated-command-facts"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :subcommands '("run")
       :flags '("--mode")
       :option-values '(("--mode" "fast"))
       :description "first source")
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :subcommands '("test" "run")
       :flags '("--verbose" "--mode")
       :option-values '(("--mode" "safe" "fast")
                        ("--format" "json")))
      (expect '("--mode" "--verbose" "run" "test") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool ")))
      (expect '("--mode=fast") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode=f")))
      (expect '("safe") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --mode s")))
      (expect '("--format=json") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --format=j")))
      (let ((candidate (completion-candidate-by-text
                        "tool"
                        (nshell.domain.completion:complete kb "to"))))
        (expect (null candidate) :to-be-falsy)
        (expect "first source" :to-equal (nshell.domain.completion:candidate-description candidate)))))

  (it "knowledge-base-completion-resolves-longest-hierarchical-command"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "git"
       :subcommands '("status" "switch")
       :flags '("--global"))
      (nshell.domain.completion:kb-add-command
       kb "git status"
       :subcommands '("show")
       :flags '("--branch" "--porcelain"))
      (let ((top-level (completion-texts
                        (nshell.domain.completion:complete kb "git"))))
        (expect '("git") :to-equal top-level)
        (expect (member "git status" top-level :test #'string=) :to-be-falsy))
      (expect '("status" "switch") :to-equal
              (completion-texts (nshell.domain.completion:complete kb "git s")))
      (expect '("--branch" "--porcelain" "show") :to-equal
              (completion-texts
               (nshell.domain.completion:complete kb "git status ")))
      (expect '("--porcelain") :to-equal
              (completion-texts
               (nshell.domain.completion:complete kb "git status --p")))))

  (it "knowledge-base-add-command-updates-description-when-provided"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "tool" :description "first source")
      (nshell.domain.completion:kb-add-command kb "tool" :description "second source")
      (let ((candidate (completion-candidate-by-text
                        "tool"
                        (nshell.domain.completion:complete kb "to"))))
        (expect (null candidate) :to-be-falsy)
        (expect "second source" :to-equal (nshell.domain.completion:candidate-description candidate)))))

  (it "knowledge-base-add-command-merges-exclusive-option-groups"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :exclusive-options '(("--json" "--yaml" "--json")
                            ("--single")))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :exclusive-options '(("--json" "--yaml")
                            ("--compact" "--pretty")))
      (expect '(("--json" "--yaml")
                   ("--compact" "--pretty")) :to-equal (nshell.domain.completion:kb-command-exclusive-options
                  kb "tool"))))

  (it "knowledge-base-hides-mutually-exclusive-options-after-selection"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :flags '("--color" "--no-color" "--verbose")
       :exclusive-options '(("--color" "--no-color")))
      (expect '("--color" "--no-color" "--verbose") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --")))
      (expect '("--verbose") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --color --")))
      (expect '("--verbose") :to-equal (completion-texts
                  (nshell.domain.completion:complete kb "tool --color=always --")))))

  (it "knowledge-base-command-completion-carries-description"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "deploy" :description "release service")
      (let ((candidate (completion-candidate-by-text
                        "deploy"
                        (nshell.domain.completion:complete kb "dep"))))
        (expect (null candidate) :to-be-falsy)
        (expect "release service" :to-equal (nshell.domain.completion:candidate-description candidate)))))

  (it "path-command-completion-merges-with-kb-and-path-candidates"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "cargo")
      (with-path-command-adapters
          ((lambda (directory)
             (declare (ignore directory))
             (list #p"/mock/cat" #p"/mock/cargo" #p"/mock/readme"))
           (lambda (entry)
             (not (string= "readme" (file-namestring entry)))))
        (let ((texts (completion-texts
                      (nshell.domain.completion:complete kb "c" :path "/mock:/other"))))
          (expect '("cd" "complete" "contains" "count" "cargo" "cat") :to-equal texts)))))

  (it "path-command-cache-reuses-entries-and-rechecks-executable-status"
    (let ((directory-reads 0)
          (executable-p t))
      (nshell.domain.completion::%invalidate-path-command-cache)
      (let ((nshell.domain.completion::*path-command-directory-stamp-fn*
              (constantly 1))
            (nshell.domain.completion::*path-command-cache-clock-fn*
              (constantly 0d0)))
        (with-path-command-adapters
            ((lambda (directory)
               (declare (ignore directory))
               (incf directory-reads)
               (list #p"/mock/cache-tool"))
             (lambda (entry)
               (declare (ignore entry))
               executable-p))
          (expect '("cache-tool") :to-equal
                  (completion-texts
                   (nshell.domain.completion::%command-candidates-from-path
                    "/mock" "cache-")))
          (setf executable-p nil)
          (expect (nshell.domain.completion::%command-candidates-from-path
                   "/mock" "cache-")
                  :to-be-null)
          (expect 1 :to-equal directory-reads)))))

  (it "path-command-cache-retains-empty-directory-results"
    (let ((directory-reads 0))
      (nshell.domain.completion::%invalidate-path-command-cache)
      (let ((nshell.domain.completion::*path-command-directory-stamp-fn*
              (constantly 1))
            (nshell.domain.completion::*path-command-cache-clock-fn*
              (constantly 0d0)))
        (with-path-command-adapters
            ((lambda (directory)
               (declare (ignore directory))
               (incf directory-reads)
               nil)
             (constantly t))
          (nshell.domain.completion::%command-candidates-from-path "/empty" "x")
          (nshell.domain.completion::%command-candidates-from-path "/empty" "x")
          (expect 1 :to-equal directory-reads)))))

  #+sb-thread
  (it "path-command-cache-coalesces-concurrent-cold-misses-for-the-same-key"
    (let ((directory-reads 0)
          (results (make-array 2))
          (reads-lock (sb-thread:make-mutex :name "path-cache-test-reads"))
          (scan-entered (sb-thread:make-semaphore :count 0))
          (release-scan (sb-thread:make-semaphore :count 0))
          (key-lock-entered (sb-thread:make-semaphore :count 0))
          (start-second (sb-thread:make-semaphore :count 0))
          (allow-key-lock (sb-thread:make-semaphore :count 0))
          (original-key-lock
            (symbol-function
             'nshell.domain.completion::%path-command-directory-key-lock))
          (first nil)
          (second nil))
      (labels ((wait-for-semaphore (semaphore)
                 (unless (sb-thread:wait-on-semaphore semaphore :timeout 2)
                   (error "Timed out waiting for test semaphore")))
               (directory-files (directory)
                 (declare (ignore directory))
                 (sb-thread:with-mutex (reads-lock)
                   (incf directory-reads))
                 (sb-thread:signal-semaphore scan-entered)
                 (wait-for-semaphore release-scan)
                 (list #p"/mock/single-flight-tool"))
               (worker (index)
                 (when (= index 1) (wait-for-semaphore start-second))
                 (let ((nshell.domain.completion::*path-command-directory-files-fn* #'directory-files)
                       (nshell.domain.completion::*path-command-executable-p-fn* (constantly t))
                       (nshell.domain.completion::*path-command-directory-stamp-fn* (constantly 1))
                       (nshell.domain.completion::*path-command-cache-clock-fn* (constantly 0d0)))
                   (setf (aref results index)
                         (nshell.domain.completion::%list-path-command-directory "/mock"))))
               (release-waiters ()
                 (sb-thread:signal-semaphore release-scan)
                 (sb-thread:signal-semaphore release-scan)
                 (sb-thread:signal-semaphore allow-key-lock)
                 (sb-thread:signal-semaphore allow-key-lock))
               (reap-thread (thread)
                 (when thread
                   (ignore-errors (sb-thread:join-thread thread :timeout 1 :default nil))
                   (when (sb-thread:thread-alive-p thread)
                     (sb-thread:terminate-thread thread)
                     (ignore-errors
                       (sb-thread:join-thread thread :timeout 1 :default nil))))))
        (nshell.domain.completion::%invalidate-path-command-cache)
        (unwind-protect
             (progn
               (setf (symbol-function 'nshell.domain.completion::%path-command-directory-key-lock)
                     (lambda (key)
                       (let ((record (funcall original-key-lock key)))
                         (when (eq sb-thread:*current-thread* second)
                           (sb-thread:signal-semaphore key-lock-entered)
                           (wait-for-semaphore allow-key-lock))
                         record)))
               (setf first (sb-thread:make-thread (lambda () (worker 0))))
               (wait-for-semaphore scan-entered)
               (setf second (sb-thread:make-thread (lambda () (worker 1))))
               (sb-thread:signal-semaphore start-second)
               (wait-for-semaphore key-lock-entered)
               (sb-thread:signal-semaphore release-scan)
               (sb-thread:signal-semaphore allow-key-lock)
               (let ((timeout (gensym "THREAD-TIMEOUT")))
                 (expect (eq timeout (sb-thread:join-thread first :timeout 2 :default timeout))
                         :to-be-null)
                 (expect (eq timeout (sb-thread:join-thread second :timeout 2 :default timeout))
                         :to-be-null))
               (expect (list #p"/mock/single-flight-tool") :to-equal (aref results 0))
               (expect (list #p"/mock/single-flight-tool") :to-equal (aref results 1))
               (expect 1 :to-equal directory-reads))
          (setf (symbol-function 'nshell.domain.completion::%path-command-directory-key-lock)
                original-key-lock)
          (release-waiters)
          (reap-thread first)
          (reap-thread second)))))

  #+sb-thread
  (it "path-command-cache-does-not-reinsert-a-scan-invalidated-in-flight"
    (let ((directory-reads 0)
          (first-result nil)
          (scan-entered (sb-thread:make-semaphore :count 0))
          (release-scan (sb-thread:make-semaphore :count 0))
          (scanner nil))
      (labels ((wait-for-semaphore (semaphore)
                 (unless (sb-thread:wait-on-semaphore semaphore :timeout 2)
                   (error "Timed out waiting for test semaphore")))
               (directory-files (directory)
                 (declare (ignore directory))
                 (incf directory-reads)
                 (if (= directory-reads 1)
                     (progn
                       (sb-thread:signal-semaphore scan-entered)
                       (wait-for-semaphore release-scan)
                       (list #p"/mock/stale-tool"))
                     (list #p"/mock/fresh-tool")))
               (reap-scanner ()
                 (when scanner
                   (ignore-errors
                     (sb-thread:join-thread scanner :timeout 1 :default nil))
                   (when (sb-thread:thread-alive-p scanner)
                     (sb-thread:terminate-thread scanner)
                     (ignore-errors
                       (sb-thread:join-thread scanner :timeout 1 :default nil))))))
        (nshell.domain.completion::%invalidate-path-command-cache)
        (let ((nshell.domain.completion::*path-command-directory-files-fn*
                #'directory-files)
              (nshell.domain.completion::*path-command-executable-p-fn*
                (constantly t))
              (nshell.domain.completion::*path-command-directory-stamp-fn*
                (constantly 1))
              (nshell.domain.completion::*path-command-cache-clock-fn*
                (constantly 0d0)))
          (unwind-protect
               (progn
                 (setf scanner
                       (sb-thread:make-thread
                        (lambda ()
                          (let ((nshell.domain.completion::*path-command-directory-files-fn*
                                  #'directory-files)
                                (nshell.domain.completion::*path-command-executable-p-fn*
                                  (constantly t))
                                (nshell.domain.completion::*path-command-directory-stamp-fn*
                                  (constantly 1))
                                (nshell.domain.completion::*path-command-cache-clock-fn*
                                  (constantly 0d0)))
                            (setf first-result
                                  (nshell.domain.completion::%list-path-command-directory
                                   "/mock"))))))
                 (wait-for-semaphore scan-entered)
                 (nshell.domain.completion::%invalidate-path-command-cache)
                 (sb-thread:signal-semaphore release-scan)
                 (let ((timeout (gensym "THREAD-TIMEOUT")))
                   (expect (eq timeout
                               (sb-thread:join-thread
                                scanner :timeout 2 :default timeout))
                           :to-be-null))
                 (expect (list #p"/mock/stale-tool") :to-equal first-result)
                 (expect (list #p"/mock/fresh-tool")
                         :to-equal
                         (nshell.domain.completion::%list-path-command-directory
                          "/mock"))
                 (expect (list #p"/mock/fresh-tool")
                         :to-equal
                         (nshell.domain.completion::%list-path-command-directory
                          "/mock"))
                 (expect 2 :to-equal directory-reads))
            (sb-thread:signal-semaphore release-scan)
            (reap-scanner))))))

  (it "path-command-cache-invalidates-on-stamp-ttl-hook-and-explicit-reset"
    (let ((directory-reads 0)
          (stamp 1)
          (now 0d0))
      (nshell.domain.completion::%invalidate-path-command-cache)
      (let ((nshell.domain.completion::*path-command-directory-stamp-fn*
              (lambda (directory)
                (declare (ignore directory))
                stamp))
            (nshell.domain.completion::*path-command-cache-clock-fn*
              (lambda () now)))
        (flet ((directory-files (directory)
                 (declare (ignore directory))
                 (incf directory-reads)
                 (list #p"/mock/cache-tool")))
          (with-path-command-adapters (#'directory-files (constantly t))
            (nshell.domain.completion::%command-candidates-from-path "/mock" "cache-")
            (setf stamp 2)
            (nshell.domain.completion::%command-candidates-from-path "/mock" "cache-")
            (setf now 0.3d0)
            (nshell.domain.completion::%command-candidates-from-path "/mock" "cache-")
            (nshell.domain.completion::%invalidate-path-command-cache)
            (nshell.domain.completion::%command-candidates-from-path "/mock" "cache-")
            (expect 4 :to-equal directory-reads)))
        (with-path-command-adapters
            ((lambda (directory)
               (declare (ignore directory))
               (incf directory-reads)
               (list #p"/mock/cache-other"))
             (constantly t))
          (expect '("cache-other") :to-equal
                  (completion-texts
                   (nshell.domain.completion::%command-candidates-from-path
                    "/mock" "cache-")))
          (expect 5 :to-equal directory-reads)))))

  (it "path-command-cache-isolates-request-local-adapters"
    (let* ((directory-reads 0)
          (files-fn
            (lambda (directory)
              (declare (ignore directory))
              (incf directory-reads)
              (if (= directory-reads 1)
                  (list #p"/mock/cache-first")
                  (list #p"/mock/cache-second"))))
          (stamp-one
            (lambda (directory)
              (declare (ignore directory))
              1))
          (stamp-two
            (lambda (directory)
              (declare (ignore directory))
              1))
          (clock-one (lambda () 0d0))
          (clock-two (lambda () 0d0)))
      (unwind-protect
           (progn
             (nshell.domain.completion::%invalidate-path-command-cache)
             (let ((nshell.domain.completion::*path-command-directory-files-fn*
                     files-fn)
                   (nshell.domain.completion::*path-command-executable-p-fn*
                     (constantly t))
                   (nshell.domain.completion::*path-command-directory-stamp-fn*
                     stamp-one)
                   (nshell.domain.completion::*path-command-cache-clock-fn*
                     clock-one))
               (expect '("cache-first") :to-equal
                       (completion-texts
                        (nshell.domain.completion::%command-candidates-from-path
                         "/mock" "cache-"))))
             (let ((nshell.domain.completion::*path-command-directory-files-fn*
                     files-fn)
                   (nshell.domain.completion::*path-command-executable-p-fn*
                     (constantly t))
                   (nshell.domain.completion::*path-command-directory-stamp-fn*
                     stamp-two)
                   (nshell.domain.completion::*path-command-cache-clock-fn*
                     clock-two))
               (expect '("cache-second") :to-equal
                       (completion-texts
                        (nshell.domain.completion::%command-candidates-from-path
                         "/mock" "cache-"))))
             (expect 2 :to-equal directory-reads))
        (nshell.domain.completion::%invalidate-path-command-cache))))

  (it "command-completion-ranks-exact-match-first"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "git")
      (nshell.domain.completion:kb-add-command kb "gitk")
      (nshell.domain.completion:kb-add-command kb "gist")
      (let ((texts (completion-texts
                    (nshell.domain.completion:complete kb "git"))))
        (expect '("git" "gitk") :to-equal texts))))

  (it "command-completion-ranks-case-sensitive-prefix-before-case-folded-match"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "ZZCase-tool")
      (nshell.domain.completion:kb-add-command kb "zzcase-tool")
      (let ((texts (completion-texts
                    (nshell.domain.completion:complete kb "zzcase"))))
        (expect '("zzcase-tool" "ZZCase-tool") :to-equal texts))))

  (it "command-completion-keeps-best-duplicate-metadata"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "tool" :description "managed command")
      (with-path-command-adapters
          ((lambda (directory)
             (declare (ignore directory))
             (list #p"/mock/tool"))
           (constantly t))
        (let ((candidates (nshell.domain.completion:complete kb "to" :path "/mock")))
          (expect 1 :to-equal (length candidates))
          (expect "tool" :to-equal (nshell.domain.completion:candidate-text (first candidates)))
          (expect "managed command" :to-equal (nshell.domain.completion:candidate-description
                        (first candidates)))))))

  (it "path-command-completion-ignores-argument-position"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-path-command-adapters
          ((lambda (directory)
             (declare (ignore directory))
             (list #p"/mock/git"))
           (constantly t))
        (expect (nshell.domain.completion:complete kb "echo g" :path "/mock") :to-be-null))))

  (it "path-command-completion-skips-directory-prefixed-commands"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-path-command-adapters
          ((lambda (directory)
             (declare (ignore directory))
             (list #p"/mock/git"))
           (constantly t))
        (expect (nshell.domain.completion:complete kb "./g" :path "/mock") :to-be-null))))

  (it "unique-string-values-deduplicates-preserving-first-occurrence"
    "unique-string-values keeps first occurrence and drops later duplicates."
    (flet ((uniq (&rest vals)
             (nshell.domain.completion::%unique-string-values vals)))
      (expect (uniq) :to-be-null)
      (expect '("a") :to-equal (uniq "a" "a" "a"))
      (expect '("a" "b" "c") :to-equal (uniq "a" "b" "a" "c" "b"))))

  (it "merge-string-values-combines-and-deduplicates"
    "merge-string-values appends two lists and deduplicates."
    (flet ((merge* (a b)
             (nshell.domain.completion::%merge-string-values a b)))
      (expect (merge* nil nil) :to-be-null)
      (expect '("a" "b") :to-equal (merge* nil '("a" "b")))
      (expect '("a" "b" "c") :to-equal (merge* '("a" "b") '("b" "c")))))

  (it "merge-kb-command-facts-preserves-and-merges-entry-policy"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :subcommands '("run")
       :flags '("--mode")
       :option-values '(("--mode" "fast"))
       :exclusive-options '(("--json" "--yaml"))
       :description "catalog")
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :subcommands '("test" "run")
       :flags '("--mode" "--verbose")
       :option-values '(("--mode" "safe" "fast")
                        ("--format" "json"))
       :exclusive-options '(("--json" "--yaml")
                            ("--compact" "--pretty")))
      (expect '("run" "test") :to-equal (nshell.domain.completion:kb-command-subcommands kb "tool"))
      (expect '("--mode" "--verbose") :to-equal (nshell.domain.completion:kb-command-flags kb "tool"))
      (expect '(("--format" "json")
                   ("--mode" "fast" "safe")) :to-equal (nshell.domain.completion:kb-command-option-values kb "tool"))
      (expect '(("--json" "--yaml")
                   ("--compact" "--pretty")) :to-equal (nshell.domain.completion:kb-command-exclusive-options
                  kb "tool"))
      (expect "catalog" :to-equal (nshell.domain.completion:kb-command-description
                    kb "tool"))))

  (it "merge-kb-command-facts-updates-description-when-present"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "tool" :description "catalog")
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :description "dynamic loader")
      (expect "dynamic loader" :to-equal (nshell.domain.completion:kb-command-description
                    kb "tool"))))

  (it "add-kb-command-entry-option-merges-through-entry-boundary"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :flags '("--mode")
       :option-values '(("--mode" "fast")))
      (nshell.domain.completion:kb-add-option
       kb "tool" "--mode" :values '("safe" "fast"))
      (expect '("--mode") :to-equal (nshell.domain.completion:kb-command-flags kb "tool"))
      (expect '(("--mode" "fast" "safe")) :to-equal (nshell.domain.completion:kb-command-option-values
                  kb "tool"))))

  (it "completion-help-command-facts-are-private-values"
    (let ((facts (nshell.domain.completion::%completion-help-command-facts
                  (format nil "Commands:~%  run   execute the tool~%  test  verify behavior~%~%  --format=(json|yaml)~%  --verbose~%  -h, --help"))))
      (assert-symbol-boundaries
          :present (nshell.domain.completion::%make-completion-help-command-facts)
          :absent (nshell.domain.completion::make-completion-help-command-facts))
      (assert-completion-help-command-facts
          facts
        :subcommands '("run" "test")
        :flags '("--format" "--verbose" "-h" "--help")
        :option-values '(("--format" "json" "yaml")))))

  (it "add-command-from-help-projects-help-facts-through-public-kb-api"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command-from-help
       kb "tool"
       (format nil "Commands:~%  run   execute the tool~%  test  verify behavior~%~%  --format=(json|yaml)~%  --verbose~%  --mode=(fast|safe)")
       :description "parsed help")
      (expect '("run" "test") :to-equal (nshell.domain.completion:kb-command-subcommands kb "tool"))
      (expect '("--format" "--verbose" "--mode") :to-equal (nshell.domain.completion:kb-command-flags kb "tool"))
      (expect '(("--format" "json" "yaml")
                   ("--mode" "fast" "safe")) :to-equal (nshell.domain.completion:kb-command-option-values kb "tool"))
      (expect "parsed help" :to-equal (nshell.domain.completion:kb-command-description
                    kb "tool"))))

  (it "knowledge-base-query-api-does-not-expose-entry-plist"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "tool"
       :subcommands '("run")
       :flags '("--mode")
       :option-values '(("--mode" "fast"))
       :exclusive-options '(("--json" "--yaml"))
       :description "tool command")
      (assert-symbol-boundaries
          :absent (nshell.domain.completion::kb-query))
      (expect (nshell.domain.completion:kb-command-present-p kb "tool") :to-be-truthy)
      (expect (nshell.domain.completion:kb-command-present-p kb "missing") :to-be-falsy)
      (expect '("run") :to-equal (nshell.domain.completion:kb-command-subcommands kb "tool"))
      (expect '("--mode") :to-equal (nshell.domain.completion:kb-command-flags kb "tool"))
      (expect '(("--mode" "fast")) :to-equal (nshell.domain.completion:kb-command-option-values kb "tool"))
      (expect '(("--json" "--yaml")) :to-equal (nshell.domain.completion:kb-command-exclusive-options
                  kb "tool"))
      (expect "tool command" :to-equal (nshell.domain.completion:kb-command-description
                    kb "tool"))))

  (it "normalize-kb-exclusive-option-groups-filters-singletons-and-deduplicates"
    "normalize drops singleton groups and deduplicates values within each group."
    (flet ((norm (groups)
             (nshell.domain.completion::%normalize-kb-exclusive-option-groups groups)))
      (expect (norm nil) :to-be-null)
      ;; singleton ("--a") is dropped; ("--a" "--b") is kept
      (expect '(("--a" "--b")) :to-equal (norm '(("--a" "--b") ("--a"))))
      ;; duplicates within group: ("--c" "--d" "--c") → ("--c" "--d")
      (expect '(("--c" "--d")) :to-equal (norm '(("--c" "--d" "--c")))))))
