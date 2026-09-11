(in-package #:nshell.domain.completion)

(defun completion-query-for (partial-input &optional filesystem &key home-directory)
  (let* ((context (completion-context-for partial-input))
         (arg-prefix (completion-context-argument-prefix context))
         (filesystem-mode (completion-filesystem-mode context)))
    (%make-completion-query partial-input context
                            (completion-context-command context)
                            arg-prefix
                            (completion-context-argument-words context)
                            filesystem
                            (when filesystem-mode
                              (filesystem-candidates-for-mode filesystem-mode arg-prefix filesystem
                                                              :home-directory home-directory)))))

(defun complete (kb partial-input &key path filesystem alias-table function-table
                                        variable-names directory home-directory)
  (let ((query (completion-query-for partial-input filesystem :home-directory home-directory)))
    (%rank-candidates (%completion-ranking-prefix query)
                      (%completion-candidates kb query path alias-table function-table
                                              :variable-names variable-names
                                              :directory directory
                                              :home-directory home-directory))))
