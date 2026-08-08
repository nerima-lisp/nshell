(in-package #:nshell/test)

(describe "integration-tests"
  (it "parse-and-execute-roundtrip"
    (with-complete-ast (ast "echo hello")
      (expect (nshell.domain.parsing:command-node-p ast) :to-be-truthy)))

  (it "quoted-here-document-skips-parameter-and-command-expansion"
    "Quoted here-document bodies are passed literally to external commands."
    (with-complete-ast (ast (format nil "cat << \"EOF\"~%$HOME $(printf substituted)~%EOF"))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (expect 0 :to-equal code)
        (expect (format nil "$HOME $(printf substituted)~%") :to-equal output))))

  (it "unquoted-here-document-expands-command-substitution"
    "Unquoted here-document bodies continue to expand command substitutions."
    (with-complete-ast (ast (format nil "cat << EOF~%$(printf substituted)~%EOF"))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (expect 0 :to-equal code)
        (expect (format nil "substituted~%") :to-equal output))))

  (it "source-loads-real-file-and-registers-function"
    (with-builtins-context (context)
      (with-test-source-file (source nil :prefix "nshell-source-integration")
        (write-test-lines source
                          '("function greet"
                            "echo from-file"
                            "end"
                            "greet"
                            "echo after-file"))
        (multiple-value-bind (output code)
            (call-source-file context source)
          (expect 0 :to-equal code)
          (expect (format nil "from-file~%after-file~%") :to-equal output)
          (expect '("echo from-file") :to-equal (gethash "greet"
                              (nshell.application:shell-context-function-table
                               context)))))))

  (it "pipeline-parsing"
    (with-complete-ast (ast "ls | grep foo")
      (expect (nshell.domain.parsing:pipeline-node-p ast) :to-be-truthy)
      (expect 2 :to-equal (length (nshell.domain.parsing:pipeline-node-commands ast)))))

  (it "history-search-and-persistence"
    (let ((h (nshell.domain.history:make-command-history :max-entries 100)))
      (nshell.domain.history:history-add h "git status")
      (nshell.domain.history:history-add h "git push origin main")
      (nshell.domain.history:history-add h "ls -la")
      (let ((results (nshell.domain.history:history-search h "git" :mode :prefix)))
        (expect 2 :to-equal (length results)))
      (let ((results (nshell.domain.history:history-search h "ls" :mode :prefix)))
        (expect 1 :to-equal (length results)))))

  (it "completion-knowledge-base-integration"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "git" :subcommands '("status") :flags '("-m"))
      (expect (nshell.domain.completion:kb-command-present-p kb "git") :to-be-truthy)))

  (it "hierarchical-completion-uses-subcommand-metadata"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "git"
       :subcommands '("status" "switch"))
      (nshell.domain.completion:kb-add-command
       kb "git status"
       :flags '("--branch" "--porcelain" "--short"))
      (expect (completion-texts
               (nshell.domain.completion:complete kb "git s"))
              :to-equal '("status" "switch"))
      (expect (completion-texts
              (nshell.domain.completion:complete kb "git status --"))
              :to-equal '("--branch" "--porcelain" "--short"))))

  (it "catalogued-subcommand-metadata-roundtrips-through-completion-api"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (dolist (spec (nshell.domain.completion:external-subcommand-completion-command-specs))
        (destructuring-bind (command &key subcommands flags &allow-other-keys)
            spec
          (nshell.domain.completion:kb-add-command
           kb command :subcommands subcommands :flags flags)))
      (expect (completion-texts
               (nshell.domain.completion:complete kb "git diff --stage"))
              :to-equal '("--staged"))
      (expect (completion-texts
               (nshell.domain.completion:complete kb "docker compose u"))
              :to-equal '("up"))
      (expect (completion-texts
               (nshell.domain.completion:complete kb "kubectl apply --dr"))
              :to-equal '("--dry-run"))))

  (it "path-command-completion-uses-directory-adapter-integration"
    (let* ((root (merge-pathnames (format nil "nshell-path-completion-~a/" (gensym))
                                  (host-kit:temporary-directory)))
           (command-path (merge-pathnames "nshell-cmd" root))
           (old-directory-files-fn nshell.domain.completion:*path-command-directory-files-fn*)
           (old-executable-p-fn nshell.domain.completion:*path-command-executable-p-fn*))
      (unwind-protect
           (progn
             (ensure-directories-exist root)
             (with-open-file (stream command-path
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (write-line "echo ok" stream))
             (setf nshell.domain.completion:*path-command-directory-files-fn*
                   (lambda (directory) (host-kit:directory-files directory)))
             (setf nshell.domain.completion:*path-command-executable-p-fn*
                   (lambda (entry) (probe-file entry)))
             (let ((texts (completion-texts
                           (nshell.domain.completion:complete
                            (nshell.domain.completion:make-empty-knowledge-base)
                            "nshell-c"
                            :path (namestring root)))))
               (expect (member "nshell-cmd" texts :test #'string=) :to-be-truthy)))
        (setf nshell.domain.completion:*path-command-directory-files-fn* old-directory-files-fn)
        (setf nshell.domain.completion:*path-command-executable-p-fn* old-executable-p-fn)
        (handler-case
            (when (probe-file root)
              (host-kit:delete-directory-tree root :validate t))
          (error ())))))

  (it "path-command-completion-cck-preserves-dynamic-adapters"
    (let* ((directories
             (loop for index below 8
                   collect (format nil "/fixture/cck-~D/" index)))
           (directory-files-fn
             (lambda (directory)
               (let ((suffix (car (last (pathname-directory directory)))))
                 (list (pathname (format nil "/fixture/nshell-~A" (subseq suffix (length "cck-"))))))))
           (executable-p-fn
             (lambda (entry)
               (declare (ignore entry))
               t))
           (directory-stamp-fn
             (lambda (directory)
               (declare (ignore directory))
               0))
           (expected
             (loop for index below 8
                   collect (format nil "nshell-~D" index))))
      (expect
        (eq nshell.domain.completion:*path-command-directory-map-fn*
            #'nshell.infrastructure.acl::%map-path-command-directories-with-cck)
        :to-be-truthy)
      (let ((nshell.domain.completion:*path-command-directory-files-fn*
              directory-files-fn)
            (nshell.domain.completion:*path-command-executable-p-fn*
              executable-p-fn)
            (nshell.domain.completion::*path-command-directory-stamp-fn*
              directory-stamp-fn))
        (unwind-protect
             (progn
               (nshell.domain.completion::%invalidate-path-command-cache)
               (let ((texts
                       (completion-texts
                        (nshell.domain.completion::%command-candidates-from-path
                         (format nil "~{~A~^:~}" directories)
                         "nshell-"))))
                 (expect expected :to-equal texts)))
          (nshell.domain.completion::%invalidate-path-command-cache))))

  (it "cps-trampoline-execution"
    (let ((results '()))
      (nshell.presentation:trampoline
       (lambda ()
         (push 1 results)
         (lambda ()
           (push 2 results)
           (lambda ()
             (push 3 results)
             nil))))
      (expect '(3 2 1) :to-equal results)))

  (it "tokenizer-parser-ast-roundtrip"
    (let ((inputs '("ls" "echo hello" "git status" "ls -la | grep foo")))
      (dolist (input inputs)
        (with-complete-command-line (result ast input)
          (declare (ignore ast))
          (expect (nshell.domain.parsing:parse-complete-p result) :to-be-truthy)
          (expect (null (nshell.domain.parsing:parse-result-ast result)) :to-be-falsy))))))
)
