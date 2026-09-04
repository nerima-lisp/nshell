(in-package #:nshell.domain.completion)

(defun %knowledge-base-command-candidates (kb path command filesystem)
  (%merge-candidates
    (knowledge-base-command-candidates kb command)
    (%command-candidates-from-path path command filesystem)
    (builtin-command-candidates command)))

(defun %knowledge-base-argument-candidates
    (kb command arg-prefix argument-words filesystem)
  (or
   (let ((kind (knowledge-base-option-value-kind kb command argument-words arg-prefix)))
     (when kind
       (filesystem-candidates-for-value-kind kind arg-prefix filesystem)))
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
         (when (and (stringp name) (%starts-with-p prefix name))
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

(defun %knowledge-base-candidates (kb query path)
  (let ((command (completion-query-command query))
        (arg-prefix (completion-query-arg-prefix query))
        (filesystem (completion-query-filesystem query)))
    (%query-candidates query
      (lambda () (%knowledge-base-command-candidates kb path command filesystem))
      (lambda () (%knowledge-base-argument-candidates kb command arg-prefix
                                                       (completion-query-argument-words query)
                                                       filesystem)))))

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

(defun %completion-candidates (kb query path alias-table function-table)
  (let ((candidates (cond
                      ((%completion-query-redirection-target-p query)
                       (%redirection-target-candidates query))
                      (t (typecase kb
                           (knowledge-base (%knowledge-base-candidates kb query path))
                           (rule-knowledge-base (%rule-knowledge-base-candidates kb query))
                           (t (%fallback-candidates query path)))))))
    (if (and (%completion-query-command-position-p query)
             (not (%completion-query-redirection-target-p query)))
        (%merge-candidates candidates
                           (%runtime-command-candidates alias-table function-table
                                                         (completion-query-command query)))
        candidates)))

(defun %completion-ranking-prefix (query)
  (if (%completion-query-command-position-p query) (completion-query-command query)
      (completion-query-arg-prefix query)))
