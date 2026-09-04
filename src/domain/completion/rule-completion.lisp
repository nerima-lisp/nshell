(in-package #:nshell.domain.completion)

(defun %rule-solution-value (variable solution)
  (cdr (assoc variable solution)))

(defun %completion-descriptions (rulebase completions)
  (let ((descriptions (make-hash-table :test (function equal))))
    (when completions
      (dolist (solution
               (%prove-rulebase
                rulebase
                (list
                 (list (quote member) (quote ?completion) completions)
                 (list (quote describes) (quote ?completion) (quote ?description))))
               descriptions)
        (let ((completion (%rule-solution-value (quote ?completion) solution))
              (description (%rule-solution-value (quote ?description) solution)))
          (when (and (stringp completion) (stringp description))
            (multiple-value-bind (existing present-p)
                (gethash completion descriptions)
              (declare (ignore existing))
              (unless present-p
                (setf (gethash completion descriptions) description)))))))))

(defun %matching-rule-solution-values (solutions variable prefix)
  (remove-duplicates
   (loop for solution in solutions
         for value = (%rule-solution-value variable solution)
         when (and (stringp value) (%starts-with-p prefix value))
           collect value)
   :test (function equal)))

(defun %candidates-from-rule-solutions
    (solutions variable kind &key (prefix "") descriptions description-fn)
  (sort (%merge-candidates
         (loop for solution in solutions
               for value = (%rule-solution-value variable solution)
               when (and (stringp value) (%starts-with-p prefix value))
                 collect (make-candidate value
                                         :kind kind
                                         :description
                                         (or (and (functionp description-fn)
                                                  (funcall description-fn value))
                                             (and (hash-table-p descriptions)
                                                  (gethash value descriptions))
                                             ""))))
        #'string<
        :key #'candidate-text))

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
               (let* ((solutions
                        (query-all
                         (list (quote completes) command (quote ?completion))))
                      (matching-values
                        (%matching-rule-solution-values
                         solutions
                         (quote ?completion)
                         arg-prefix)))
                 (%candidates-from-rule-solutions
                  solutions (quote ?completion) :option
                  :prefix arg-prefix
                  :descriptions (%completion-descriptions rulebase matching-values))))
              (t
               (let* ((solutions
                        (query-all (quote (completes ?command ?completion))))
                      (matching-values
                        (%matching-rule-solution-values solutions (quote ?command) command)))
                 (%candidates-from-rule-solutions
                  solutions (quote ?command) :command
                  :prefix command
                  :descriptions (%completion-descriptions rulebase matching-values))))))))))

(defun rule-complete (kb-rules partial-input &optional filesystem)
  (%rule-complete-query kb-rules (completion-query-for partial-input filesystem)))
