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

  (it "unquoted-here-document-expands-parameters-without-field-splitting"
    "Unquoted here-document parameters expand while body whitespace remains intact."
    (with-complete-ast (ast (format nil "cat << EOF~%status=$?~%EOF"))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (expect 0 :to-equal code)
        (expect (format nil "status=0~%") :to-equal output))))

  (it "unquoted-here-document-preserves-command-substitution-newlines"
    "Command substitution output keeps internal newlines in an unquoted body."
    (with-complete-ast
        (ast (format nil "cat << EOF~%before $(printf 'left\\nright') after~%EOF"))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (expect 0 :to-equal code)
        (expect (format nil "before left~%right after~%") :to-equal output))))

  (it "unquoted-here-document-honors-backslash-escapes"
    "Unquoted here-document backslash escapes suppress expansion and join lines."
    (with-complete-ast
        (ast (format nil "cat << EOF~%\\$HOME~%joined\\~%line~%EOF"))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (expect 0 :to-equal code)
        (expect (format nil "$HOME~%joinedline~%") :to-equal output))))

  (it "unquoted-here-document-does-not-expand-escaped-command-substitution"
    "A backslash-escaped command substitution remains literal in an unquoted body."
    (with-complete-ast
        (ast (format nil "cat << EOF~%\\$(printf substituted)~%EOF"))
      (multiple-value-bind (output code)
          (call-repl-execute-ast ast)
        (expect 0 :to-equal code)
        (expect (format nil "$(printf substituted)~%") :to-equal output))))

  (it "source-loads-real-file-and-registers-sexp-function"
    (with-builtins-context (context)
      (with-test-source-file (source nil :prefix "nshell-source-integration")
        (write-test-lines
         source
         (list "(define-shell-function greet () (echo from-file))"
               "(greet)"
               "(echo after-file)"))
        (multiple-value-bind (output code)
            (call-source-file context source)
          (expect 0 :to-equal code)
          (expect (format nil "from-file~%after-file~%") :to-equal output)
          (expect t :to-be
                  (nth-value
                   1
                   (nshell.application:lookup-shell-function
                    (nshell.application:context-shell-function-registry context)
                    "greet")))))))

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

  (it "path-command-completion-uses-explicit-filesystem-integration"
    (let* ((root (merge-pathnames (format nil "nshell-path-completion-~a/" (gensym))
                                  (host-kit:temporary-directory)))
           (command-path (merge-pathnames "nshell-cmd" root))
           (filesystem
             (make-test-filesystem
              :directory-files #'host-kit:directory-files
              :executable-p (lambda (entry) (probe-file entry)))))
      (unwind-protect
           (progn
             (ensure-directories-exist root)
             (with-open-file (stream command-path
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (write-line "echo ok" stream))
             (let ((texts (completion-texts
                           (nshell.domain.completion:complete
                            (nshell.domain.completion:make-empty-knowledge-base)
                            "nshell-c"
                            :path (namestring root)
                            :filesystem filesystem))))
               (expect (member "nshell-cmd" texts :test #'string=) :to-be-truthy)))
        (handler-case
            (when (probe-file root)
              (host-kit:delete-directory-tree root :validate t))
          (error ())))))

  (it "path-command-completion-uses-explicit-directory-mapper"
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
                   collect (format nil "nshell-~D" index)))
           (filesystem
             (make-test-filesystem
              :directory-files directory-files-fn
              :executable-p executable-p-fn
              :directory-map #'nshell.infrastructure.acl:map-path-command-directories)))
      (let (
            (nshell.domain.completion::*path-command-directory-stamp-fn*
              directory-stamp-fn))
        (unwind-protect
             (progn
               (nshell.domain.completion::%invalidate-path-command-cache)
               (let ((texts
                       (completion-texts
                        (nshell.domain.completion::%command-candidates-from-path
                         (format nil "~{~A~^:~}" directories)
                         "nshell-"
                         filesystem))))
                 (expect expected :to-equal texts)))
          (nshell.domain.completion::%invalidate-path-command-cache)))))

  (it "path-command-directory-mapper-preserves-order-and-bounds-fanout"
    (flet ((mapped (directories)
             (nshell.infrastructure.acl:map-path-command-directories
              (lambda (directory)
                (list :mapped directory))
              directories)))
      (expect (list (list :mapped :one)
                    (list :mapped :two)
                    (list :mapped :three))
              :to-equal
              (mapped (list :one :two :three)))
      (expect (list (list :mapped :one)
                    (list :mapped :two)
                    (list :mapped :three)
                    (list :mapped :four))
              :to-equal
              (mapped (list :one :two :three :four))))
    (let* ((directories (loop for index below 9 collect index))
           (calls (make-array 9 :initial-element 0))
           (call-lock (sb-thread:make-mutex))
           (spawn-symbol (find-symbol "SPAWN" "CL-CONCURRENT-KIT"))
           (original-spawn (symbol-function spawn-symbol))
           (spawn-count 0)
           (results nil))
      (unwind-protect
           (progn
             (setf (symbol-function spawn-symbol)
                   (lambda (scope task)
                     (incf spawn-count)
                     (funcall original-spawn scope task)))
             (setf results
                   (nshell.infrastructure.acl:map-path-command-directories
                    (lambda (directory)
                      (sb-thread:with-mutex (call-lock)
                        (incf (aref calls directory)))
                      (list :mapped directory))
                    directories)))
        (setf (symbol-function spawn-symbol) original-spawn))
      (expect 4 :to-equal spawn-count)
      (expect (loop for index below 9 collect 1)
              :to-equal
              (loop for index below 9 collect (aref calls index)))
      (expect (loop for index below 9 collect (list :mapped index))
              :to-equal
              results))
    (expect (lambda ()
              (nshell.infrastructure.acl:map-path-command-directories
               (lambda (directory)
                 (when (eql directory :fail)
                   (error "directory mapping failed"))
                 directory)
               (list :one :fail :three :four :five :six :seven :eight)))
            :to-throw
            (find-symbol "SIMPLE-ERROR" "COMMON-LISP")))

  (it "cps-trampoline-execution"
    (let ((results '()))
      (let ((result
              (nshell.presentation:trampoline
               (lambda ()
                 (push 1 results)
                 (lambda ()
                   (push 2 results)
                   (lambda ()
                     (push 3 results)
                     nshell.presentation::+repl-exit+))))))
        (expect nshell.presentation::+repl-exit+ :to-equal result))
      (expect '(3 2 1) :to-equal results)))

  (it "tokenizer-parser-ast-roundtrip"
    (let ((inputs '("ls" "echo hello" "git status" "ls -la | grep foo")))
      (dolist (input inputs)
        (with-complete-command-line (result ast input)
          (declare (ignore ast))
          (expect (nshell.domain.parsing:parse-complete-p result) :to-be-truthy)
          (expect (null (nshell.domain.parsing:parse-result-ast result)) :to-be-falsy))))))

