(in-package #:nshell/test)

(def-suite integration-tests
  :description "Integration tests for nshell"
  :in nshell-tests)

(in-suite integration-tests)

(test parse-and-execute-roundtrip
  (with-complete-ast (ast "echo hello")
    (is (nshell.domain.parsing:command-node-p ast))))

(test source-loads-real-file-and-registers-function
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
        (is (= 0 code))
        (is (string= (format nil "from-file~%after-file~%") output))
        (is (equal '("echo from-file")
                   (gethash "greet"
                            (nshell.application:shell-context-function-table
                             context))))))))

(test pipeline-parsing
  (with-complete-ast (ast "ls | grep foo")
    (is (nshell.domain.parsing:pipeline-node-p ast))
    (is (= 2 (length (nshell.domain.parsing:pipeline-node-commands ast))))))

(test history-search-and-persistence
  (let ((h (nshell.domain.history:make-command-history :max-entries 100)))
    (nshell.domain.history:history-add h "git status")
    (nshell.domain.history:history-add h "git push origin main")
    (nshell.domain.history:history-add h "ls -la")
    (let ((results (nshell.domain.history:history-search h "git" :mode :prefix)))
      (is (= 2 (length results))))
    (let ((results (nshell.domain.history:history-search h "ls" :mode :prefix)))
      (is (= 1 (length results))))))

(test unification-backtracking-integration
  (let* ((x (nshell.domain.parsing:make-var "X"))
         (y (nshell.domain.parsing:make-var "Y"))
         (goal1 (lambda (b) (nshell.domain.parsing:unify x 'command b)))
         (goal2 (lambda (b) (nshell.domain.parsing:unify y 'ls b)))
         (result (nshell.domain.parsing:backtrack (list goal1 goal2))))
    (is (not (null result)))
    (is (eq 'command (nshell.domain.parsing:walk x result)))
    (is (eq 'ls (nshell.domain.parsing:walk y result)))))

(test completion-knowledge-base-integration
  (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "git" :subcommands '("status") :flags '("-m"))
    (is (nshell.domain.completion:kb-command-present-p kb "git"))))

(test path-command-completion-uses-directory-adapter-integration
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
             (is (member "nshell-cmd" texts :test #'string=))))
      (setf nshell.domain.completion:*path-command-directory-files-fn* old-directory-files-fn)
      (setf nshell.domain.completion:*path-command-executable-p-fn* old-executable-p-fn)
      (handler-case
          (when (probe-file root)
            (uiop:delete-directory-tree root :validate t))
        (error ())))))

(test cps-trampoline-execution
  (let ((results '()))
    (nshell.presentation:trampoline
     (lambda ()
       (push 1 results)
       (lambda ()
         (push 2 results)
         (lambda ()
           (push 3 results)
           nil))))
    (is (equal '(3 2 1) results))))

(test tokenizer-parser-ast-roundtrip
  (let ((inputs '("ls" "echo hello" "git status" "ls -la | grep foo")))
    (dolist (input inputs)
      (with-complete-command-line (result ast input)
        (declare (ignore ast))
        (is (nshell.domain.parsing:parse-complete-p result))
        (is (not (null (nshell.domain.parsing:parse-result-ast result))))))))
