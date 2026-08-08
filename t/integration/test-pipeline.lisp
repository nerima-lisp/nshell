(in-package #:nshell/test)

(describe "integration-tests"
  (it "parse-and-execute-roundtrip"
    (with-complete-ast (ast "echo hello")
      (expect (nshell.domain.parsing:command-node-p ast) :to-be-truthy)))

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
    (let ((h (history-kit:make-history :capacity 100)))
      (history-kit:history-add h "git status")
      (history-kit:history-add h "git push origin main")
      (history-kit:history-add h "ls -la")
      (let ((results (history-kit:history-search h "git" :mode :prefix)))
        (expect 2 :to-equal (length results)))
      (let ((results (history-kit:history-search h "ls" :mode :prefix)))
        (expect 1 :to-equal (length results)))))

  (it "completion-knowledge-base-integration"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb "git" :subcommands '("status") :flags '("-m"))
      (expect (nshell.domain.completion:kb-command-present-p kb "git") :to-be-truthy)))

  (it "hierarchical-completion-uses-subcommand-metadata"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command
       kb "git"
       :subcommands '("status")
       :flags '("--global"))
      (nshell.domain.completion:kb-add-command
       kb "git status"
       :flags '("--branch" "--porcelain" "--short"))
      (expect '("--branch" "--porcelain" "--short") :to-equal
              (completion-texts
               (nshell.domain.completion:complete kb "git status --")))))

  (it "path-command-completion-uses-directory-adapter-integration"
    (let* ((root (merge-pathnames (format nil "nshell-path-completion-~a/" (gensym))
                                  (uiop:temporary-directory)))
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
                   (lambda (directory) (uiop:directory-files directory)))
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
              (uiop:delete-directory-tree root :validate t))
          (error ())))))

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
