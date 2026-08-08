(in-package #:nshell.domain.completion)

(defstruct (completion-query
             (:constructor %make-completion-query
                 (partial-input context command arg-prefix argument-words filesystem-candidates)))
  (partial-input "" :type string :read-only t)
  (context nil :read-only t)
  (command "" :type string :read-only t)
  (arg-prefix "" :type string :read-only t)
  (argument-words nil :type list :read-only t)
  (filesystem-candidates nil :type list :read-only t))

(defun completion-query-for (partial-input)
  (let* ((context (completion-context-for partial-input))
         (arg-prefix (completion-context-argument-prefix context))
         (filesystem-mode (completion-filesystem-mode context)))
    (%make-completion-query partial-input
                            context
                            (completion-context-command context)
                            arg-prefix
                            (completion-context-argument-words context)
                            (when filesystem-mode
                              (filesystem-candidates-for-mode filesystem-mode arg-prefix)))))

(defun %rule-solution-value (variable solution)
  (cdr (assoc variable solution)))

(defun %first-rule-solution-value (variable solutions)
  (let ((solution (first solutions)))
    (when solution
      (%rule-solution-value variable solution))))

(defun %completion-description (kb-rules value)
  (when (stringp value)
    (let* ((solutions (prove-all kb-rules (list 'describes value '?description)))
           (description (%first-rule-solution-value '?description solutions)))
      (when (stringp description)
        description))))

(defun %candidates-from-rule-solutions (solutions variable kind &key (prefix "") description-fn)
  (sort (%merge-candidates
         (loop for solution in solutions
               for value = (%rule-solution-value variable solution)
               for description = (and description-fn
                                      (funcall description-fn value))
               when (and (stringp value) (%starts-with-p prefix value))
                 collect (make-candidate value
                                         :kind kind
                                         :description (or description ""))))
        #'string<
         :key #'candidate-text))

(defun %rule-complete-query (kb-rules query)
  (let* ((context (completion-query-context query))
         (command (completion-query-command query))
         (arg-prefix (completion-query-arg-prefix query))
         (argument-position-p (%completion-query-argument-position-p query)))
    (flet ((candidate-description-for (value)
             (%completion-description kb-rules value)))
      (cond
        ((completion-context-redirection-target-p context)
         (list (make-candidate arg-prefix :kind :file :description "file")))
        ((and argument-position-p
              (prove-all kb-rules (list 'suggests-dir command)))
         (list (make-candidate "" :kind :directory :description "directory")))
        ((and argument-position-p
              (prove-all kb-rules (list 'suggests-file command)))
         (list (make-candidate "" :kind :file :description "file")))
        (argument-position-p
         (%candidates-from-rule-solutions
          (prove-all kb-rules (list 'completes command '?completion))
          '?completion
          :option
          :prefix arg-prefix
          :description-fn #'candidate-description-for))
        (t
         (%candidates-from-rule-solutions
           (prove-all kb-rules '(completes ?command ?completion))
           '?command
           :command
           :prefix command
           :description-fn #'candidate-description-for))))))

(defun rule-complete (kb-rules partial-input)
  (%rule-complete-query kb-rules (completion-query-for partial-input)))

(defun %runtime-command-candidates (prefix alias-table function-table)
  (let ((names nil))
    (dolist (table (list alias-table function-table))
      (when (hash-table-p table)
        (maphash (lambda (name value)
                   (declare (ignore value))
                   (when (and (stringp name)
                              (%starts-with-p prefix name))
                     (push name names)))
                 table)))
    (mapcar (lambda (name)
              (make-candidate name :kind :command))
            (sort (remove-duplicates names :test #'string=) #'string<))))

(defun %knowledge-base-command-candidates (kb path command alias-table function-table)
  (%merge-candidates
   (knowledge-base-command-candidates kb command)
   (%command-candidates-from-path path command)
   (builtin-command-candidates command)
   (%runtime-command-candidates command alias-table function-table)))

(defun %knowledge-base-argument-candidates (kb command arg-prefix argument-words)
  (knowledge-base-argument-candidates kb command arg-prefix
                                      :argument-words argument-words))

(defun %completion-query-command-position-p (query)
  (completion-context-command-position-p (completion-query-context query)))

(defun %completion-query-argument-position-p (query)
  (not (%completion-query-command-position-p query)))

(defun %completion-query-redirection-target-p (query)
  (completion-context-redirection-target-p (completion-query-context query)))

(defun %query-candidates (query command-candidates-fn argument-candidates-fn)
  (cond
    ((%completion-query-command-position-p query)
     (funcall command-candidates-fn))
    ((completion-query-filesystem-candidates query)
     (completion-query-filesystem-candidates query))
    (t
     (funcall argument-candidates-fn))))

(defun %knowledge-base-candidates (kb query path alias-table function-table)
  (let ((command (completion-query-command query))
        (arg-prefix (completion-query-arg-prefix query)))
    (%query-candidates
     query
     (lambda ()
       (%knowledge-base-command-candidates kb path command alias-table function-table))
     (lambda ()
       (%knowledge-base-argument-candidates
        kb
        command
        arg-prefix
        (completion-query-argument-words query))))))

(defun %rule-knowledge-base-candidates (kb query alias-table function-table)
  (labels ((rule-candidates ()
             (%rule-complete-query kb query))
           (command-candidates ()
             (%merge-candidates
              (rule-candidates)
              (%runtime-command-candidates
               (completion-query-command query)
               alias-table
               function-table))))
    (%query-candidates query #'command-candidates #'rule-candidates)))

(defun %fallback-candidates (query path alias-table function-table)
  (%query-candidates query
                     (lambda ()
                       (%merge-candidates
                        (%command-candidates-from-path path
                                                        (completion-query-command query))
                        (%runtime-command-candidates
                         (completion-query-command query)
                         alias-table
                         function-table)))
                     (lambda ()
                       nil)))

(defun %redirection-target-candidates (query)
  (or (completion-query-filesystem-candidates query)
      (list (make-candidate (completion-query-arg-prefix query)
                            :kind :file
                            :description "file"))))

(defun %completion-candidates (kb query path alias-table function-table)
  (cond
   ((%completion-query-redirection-target-p query)
    (%redirection-target-candidates query))
    (t
     (typecase kb
       (knowledge-base
        (%knowledge-base-candidates kb query path alias-table function-table))
       (rule-knowledge-base
        (%rule-knowledge-base-candidates kb query alias-table function-table))
       (t
        (%fallback-candidates query path alias-table function-table))))))

(defun %completion-ranking-prefix (query)
  (if (%completion-query-command-position-p query)
      (completion-query-command query)
      (completion-query-arg-prefix query)))

(defun complete (kb partial-input &key path alias-table function-table)
  (let ((query (completion-query-for partial-input)))
    (%rank-candidates (%completion-ranking-prefix query)
                      (%completion-candidates kb query path alias-table function-table))))
