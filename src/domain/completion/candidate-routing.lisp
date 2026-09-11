(in-package #:nshell.domain.completion)

;;; DYNAMIC-SOURCES.LISP loads after this file (see nshell.asd), so its
;;; functions are forward-declared here rather than called blind -- the same
;;; pattern SEARCH-HISTORY.LISP uses for a later-loaded file's functions.
(declaim (ftype function %variable-completion-word-prefix
                %variable-completion-candidates
                %git-dynamic-candidates))

(defun %knowledge-base-command-candidates (kb path command filesystem)
  (%merge-candidates
    (knowledge-base-command-candidates kb command)
    (%command-candidates-from-path path command filesystem)
    (builtin-command-candidates command)))

(defun %knowledge-base-argument-candidates
    (kb command arg-prefix argument-words filesystem &key home-directory)
  (or
   (let ((kind (knowledge-base-option-value-kind kb command argument-words arg-prefix)))
     (when kind
       (filesystem-candidates-for-value-kind kind arg-prefix filesystem
                                             :home-directory home-directory)))
   (knowledge-base-argument-candidates kb command arg-prefix :argument-words argument-words)))

(defun %completion-query-command-position-p (query)
  (completion-context-command-position-p (completion-query-context query)))

(defun %completion-query-argument-position-p (query)
  (not (%completion-query-command-position-p query)))

(defun %completion-query-redirection-target-p (query)
  (completion-context-redirection-target-p (completion-query-context query)))

(defun %runtime-name-candidates (table prefix description)
  (let ((candidates nil))
    (when (hash-table-p table)
      (maphash
       (lambda (name definition)
         (declare (ignore definition))
         (when (and (stringp name) (%candidate-matches-prefix-policy-p prefix name))
           (push (make-candidate name :kind :command :description description) candidates)))
       table))
    (sort candidates (function string<) :key (function candidate-text))))

(defun %runtime-command-candidates (alias-table function-table prefix)
  (%merge-candidates
   (%runtime-name-candidates alias-table prefix "alias")
   (%runtime-name-candidates function-table prefix "function")))

(defun %query-candidates (query command-candidates-fn argument-candidates-fn)
  (cond
    ((%completion-query-command-position-p query) (funcall command-candidates-fn))
    ((completion-query-filesystem-candidates query) (completion-query-filesystem-candidates query))
    (t (funcall argument-candidates-fn))))

(defun %knowledge-base-candidates (kb query path &key home-directory)
  (let ((command (completion-query-command query))
        (arg-prefix (completion-query-arg-prefix query))
        (filesystem (completion-query-filesystem query)))
    (%query-candidates query
      (lambda () (%knowledge-base-command-candidates kb path command filesystem))
      (lambda () (%knowledge-base-argument-candidates kb command arg-prefix
                                                       (completion-query-argument-words query)
                                                       filesystem
                                                       :home-directory home-directory)))))

(defun %rule-knowledge-base-candidates (kb query)
  (labels ((rule-candidates () (%rule-complete-query kb query)))
    (%query-candidates query #'rule-candidates #'rule-candidates)))

(defun %fallback-candidates (query path)
  (%query-candidates query
    (lambda () (%command-candidates-from-path path (completion-query-command query)
                                               (completion-query-filesystem query)))
    (lambda () nil)))

(defun %redirection-target-candidates (query)
  (or (completion-query-filesystem-candidates query)
      (list (make-candidate (completion-query-arg-prefix query) :kind :file :description "file"))))

(defun %completion-ranking-prefix (query)
  (if (%completion-query-command-position-p query) (completion-query-command query)
      (completion-query-arg-prefix query)))

(defun %completion-candidates
    (kb query path alias-table function-table &key variable-names directory home-directory)
  (let ((active-word (%completion-ranking-prefix query)))
    (if (%variable-completion-word-prefix active-word)
        (%variable-completion-candidates active-word variable-names)
        (let* ((redirection-p (%completion-query-redirection-target-p query))
               (command-position-p (%completion-query-command-position-p query))
               (candidates (cond
                             (redirection-p (%redirection-target-candidates query))
                             (t (typecase kb
                                  (knowledge-base (%knowledge-base-candidates
                                                    kb query path :home-directory home-directory))
                                  (rule-knowledge-base (%rule-knowledge-base-candidates kb query))
                                  (t (%fallback-candidates query path)))))))
          (cond
            ((and command-position-p (not redirection-p))
             (%merge-candidates candidates
                                (%runtime-command-candidates alias-table function-table
                                                              (completion-query-command query))))
            ((and (not command-position-p) (not redirection-p))
             (%merge-candidates candidates
                                (%git-dynamic-candidates (completion-query-command query)
                                                          (completion-query-argument-words query)
                                                          (completion-query-arg-prefix query)
                                                          directory)))
            (t candidates))))))
