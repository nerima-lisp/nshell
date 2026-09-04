(in-package #:nshell.domain.completion)

(defun completion-query-for (partial-input &optional filesystem)
  (let* ((context (completion-context-for partial-input))
         (arg-prefix (completion-context-argument-prefix context))
         (filesystem-mode (completion-filesystem-mode context)))
    (%make-completion-query partial-input context
                            (completion-context-command context)
                            arg-prefix
                            (completion-context-argument-words context)
                            filesystem
                            (when filesystem-mode
                              (filesystem-candidates-for-mode filesystem-mode arg-prefix filesystem)))))

(defun complete (kb partial-input &key path filesystem alias-table function-table)
  (let ((query (completion-query-for partial-input filesystem)))
    (%rank-candidates (%completion-ranking-prefix query)
                      (%completion-candidates kb query path alias-table function-table))))
