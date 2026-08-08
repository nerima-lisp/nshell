(in-package #:nshell.domain.completion)

(defstruct (completion-query
    (:constructor
      %make-completion-query
      (partial-input context command arg-prefix argument-words filesystem-candidates))) (partial-input "" :type string :read-only t)
  (context nil :read-only t)
  (command "" :type string :read-only t)
  (arg-prefix "" :type string :read-only t)
  (argument-words nil :type list :read-only t)
  (filesystem-candidates nil :type list :read-only t))

(defun completion-query-for (partial-input)
  (let* ((context (completion-context-for partial-input))
         (arg-prefix (completion-context-argument-prefix context))
         (filesystem-mode (completion-filesystem-mode context)))
    (%make-completion-query
      partial-input
      context
      (completion-context-command context)
      arg-prefix
      (completion-context-argument-words context)
      (when filesystem-mode
        (filesystem-candidates-for-mode filesystem-mode arg-prefix)))))

(defun %rule-solution-value (variable solution)
  (cdr (assoc variable solution)))

(defun %completion-descriptions (rulebase)
  (let ((descriptions (make-hash-table :test (function equal))))
    (dolist (solution
             (%prove-rulebase rulebase (quote (describes ?completion ?description)))
             descriptions)
      (let ((completion (%rule-solution-value (quote ?completion) solution))
            (description (%rule-solution-value (quote ?description) solution)))
        (when (and (stringp completion) (stringp description))
          (multiple-value-bind (existing present-p)
              (gethash completion descriptions)
            (declare (ignore existing))
            (unless present-p
              (setf (gethash completion descriptions) description))))))))

(defun %candidates-from-rule-solutions (solutions variable kind &key (prefix "") descriptions)
  (sort (%merge-candidates
         (loop for solution in solutions
               for value = (%rule-solution-value variable solution)
               for description = (and (stringp value)
                                      descriptions
                                      (gethash value descriptions))
               when (and (stringp value) (%starts-with-p prefix value))
                 collect (make-candidate value
                                         :kind kind
                                         :description (or description ""))))
        (function string<)
        :key (function candidate-text)))

(defun %rule-complete-query (kb-rules query)
  (let* ((context (completion-query-context query))
         (command (completion-query-command query))
         (arg-prefix (completion-query-arg-prefix query))
         (argument-position-p (%completion-query-argument-position-p query)))
    (if (completion-context-redirection-target-p context)
        (list (make-candidate arg-prefix :kind :file :description "file"))
        (let ((rulebase (completion-rulebase kb-rules)))
          (flet ((query-all (goal)
                   (%prove-rulebase rulebase goal)))
            (cond
              ((and argument-position-p
                    (query-all (list (quote suggests-dir) command)))
               (list (make-candidate "" :kind :directory :description "directory")))
              ((and argument-position-p
                    (query-all (list (quote suggests-file) command)))
               (list (make-candidate "" :kind :file :description "file")))
              (argument-position-p
               (%candidates-from-rule-solutions
                (query-all (list (quote completes) command (quote ?completion)))
                (quote ?completion)
                :option
                :prefix arg-prefix
                :descriptions (%completion-descriptions rulebase)))
              (t
               (%candidates-from-rule-solutions
                (query-all (quote (completes ?command ?completion)))
                (quote ?command)
                :command
                :prefix command
                :descriptions (%completion-descriptions rulebase)))))))))

(defun rule-complete (kb-rules partial-input)
  (%rule-complete-query kb-rules (completion-query-for partial-input)))

(defun %knowledge-base-command-candidates (kb path command)
  (%merge-candidates
    (knowledge-base-command-candidates kb command)
    (%command-candidates-from-path path command)
    (builtin-command-candidates command)))

(defun %knowledge-base-argument-candidates (kb command arg-prefix argument-words)
  (knowledge-base-argument-candidates
    kb
    command
    arg-prefix
    :argument-words
    argument-words))

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
         (when (and (stringp name)
                    (%starts-with-p prefix name))
           (push (make-candidate name
                                 :kind :command
                                 :description description)
                 candidates)))
       table))
    (sort candidates
          (function string<)
          :key (function candidate-text))))

(defun %runtime-command-candidates (alias-table function-table prefix)
  (%merge-candidates
   (%runtime-name-candidates alias-table prefix "alias")
   (%runtime-name-candidates function-table prefix "function")))

(defun %query-candidates (query command-candidates-fn argument-candidates-fn)
  (cond
    ((%completion-query-command-position-p query) (funcall command-candidates-fn))
    ((completion-query-filesystem-candidates query)
      (completion-query-filesystem-candidates query))
    (t (funcall argument-candidates-fn))))

(defun %knowledge-base-candidates (kb query path)
  (let ((command (completion-query-command query))
        (arg-prefix (completion-query-arg-prefix query)))
    (%query-candidates
      query
      (lambda ()
        (%knowledge-base-command-candidates kb path command))
      (lambda ()
        (%knowledge-base-argument-candidates
          kb
          command
          arg-prefix
          (completion-query-argument-words query))))))

(defun %rule-knowledge-base-candidates (kb query)
  (labels ((rule-candidates ()
             (%rule-complete-query kb query)))
    (%query-candidates query #'rule-candidates #'rule-candidates)))

(defun %fallback-candidates (query path)
  (%query-candidates
    query
    (lambda ()
      (%command-candidates-from-path path (completion-query-command query)))
    (lambda ()
      nil)))

(defun %redirection-target-candidates (query)
  (or
    (completion-query-filesystem-candidates query)
    (list
      (make-candidate
        (completion-query-arg-prefix query)
        :kind
        :file
        :description
        "file"))))

(defun %completion-candidates (kb query path alias-table function-table)
  (let ((candidates
          (cond
            ((%completion-query-redirection-target-p query)
              (%redirection-target-candidates query))
            (t
              (typecase kb
                (knowledge-base (%knowledge-base-candidates kb query path))
                (rule-knowledge-base (%rule-knowledge-base-candidates kb query))
                (t (%fallback-candidates query path)))))))
    (if (and (%completion-query-command-position-p query)
             (not (%completion-query-redirection-target-p query)))
        (%merge-candidates
         candidates
         (%runtime-command-candidates
          alias-table
          function-table
          (completion-query-command query)))
        candidates)))

(defun %completion-ranking-prefix (query)
  (if (%completion-query-command-position-p query) (completion-query-command query)
    (completion-query-arg-prefix query)))

(defun complete (kb partial-input &key path alias-table function-table)
  (let ((query (completion-query-for partial-input)))
    (%rank-candidates
      (%completion-ranking-prefix query)
      (%completion-candidates kb query path alias-table function-table))))
