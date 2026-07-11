(in-package #:nshell.domain.parsing)

(defstruct (%parse-result
            (:constructor %make-parse-result
                (ast &optional errors incomplete))
            (:copier nil)
            (:conc-name %parse-result-))
  (ast nil :type (or null ast-node) :read-only t)
  (errors nil :type list :read-only t)
  (incomplete nil :type boolean :read-only t))

(defun %make-normalized-parse-result (ast &optional errors incomplete)
  (%make-parse-result ast
                      (or errors '())
                      (not (null incomplete))))

(defstruct (%parse-diagnostic
            (:constructor %make-parse-diagnostic
                (kind message start end &optional token))
            (:copier nil)
            (:conc-name %parse-diagnostic-))
  (kind :error :type keyword :read-only t)
  (message "" :type string :read-only t)
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t)
  (token nil :read-only t))

(defun parse-result-ast (result)
  (%parse-result-ast result))

(defun parse-result-errors (result)
  (copy-list (%parse-result-errors result)))

(defun parse-result-incomplete (result)
  (%parse-result-incomplete result))

(defun parse-errors (result)
  (parse-result-errors result))

(defun parse-diagnostic-kind (diagnostic)
  (%parse-diagnostic-kind diagnostic))

(defun parse-diagnostic-message (diagnostic)
  (%parse-diagnostic-message diagnostic))

(defun parse-diagnostic-start (diagnostic)
  (%parse-diagnostic-start diagnostic))

(defun parse-diagnostic-end (diagnostic)
  (%parse-diagnostic-end diagnostic))

(defun parse-diagnostic-token (diagnostic)
  (%parse-diagnostic-token diagnostic))

(defstruct (%parse-result-facts
            (:constructor %make-parse-result-facts
                (ast errors incomplete))
            (:copier nil))
  (ast nil :read-only t)
  (errors nil :type list :read-only t)
  (incomplete nil :type boolean :read-only t))

(defun %parse-result-facts-from-result (result)
  (%make-parse-result-facts
   (parse-result-ast result)
   (parse-errors result)
   (parse-result-incomplete result)))

(defun %parse-result-facts-complete-p (facts)
  (and (%parse-result-facts-ast facts)
       (null (%parse-result-facts-errors facts))
       (not (%parse-result-facts-incomplete facts))))

(defun %parse-result-facts-empty-p (facts)
  (and (null (%parse-result-facts-ast facts))
       (null (%parse-result-facts-errors facts))
       (not (%parse-result-facts-incomplete facts))))

(defun %parse-result-facts-state (facts)
  (cond
    ((%parse-result-facts-complete-p facts) :complete)
    ((%parse-result-facts-incomplete facts) :incomplete)
    ((%parse-result-facts-errors facts) :error)
    ((%parse-result-facts-empty-p facts) :empty)))

(defun parse-complete-p (result)
  (%parse-result-facts-complete-p
   (%parse-result-facts-from-result result)))

(defun parse-result-state (result)
  (%parse-result-facts-state
   (%parse-result-facts-from-result result)))

(defun parse-error-messages (result)
  (mapcar #'parse-diagnostic-message (parse-errors result)))

(defun format-parse-error-messages (result)
  (format nil "~{~a~^; ~}" (parse-error-messages result)))

(defun parse-diagnostic-kind-p (result kind)
  (not (null (find kind (parse-errors result)
                   :key #'parse-diagnostic-kind))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct (%parsed-command-line-case-clause
              (:constructor %make-parsed-command-line-case-clause (keyword body)))
    (keyword nil :type keyword :read-only t)
    (body nil :type list :read-only t))

  (defun %parsed-command-line-case-clause (keyword clauses)
    (let ((body (cdr (assoc keyword clauses))))
      (when body
        (%make-parsed-command-line-case-clause keyword body))))

  (defmacro with-parsed-command-line ((result line) &body body)
    `(let ((,result (parse-command-line ,line)))
       (declare (ignorable ,result))
       ,@body))

  (defun %parsed-command-line-case-branch (keyword clauses result ast parsed-result)
    (let ((clause (%parsed-command-line-case-clause keyword clauses)))
      (when clause
        `((,(%parsed-command-line-case-clause-keyword clause)
           (let ((,result ,parsed-result)
                 (,ast (parse-result-ast ,parsed-result)))
             (declare (ignorable ,result ,ast))
             ,@(%parsed-command-line-case-clause-body clause)))))))

  (defmacro with-parsed-command-line-case ((result ast line) &body clauses)
    (let ((parsed-result (gensym "PARSE-RESULT-")))
      `(let ((,parsed-result (parse-command-line ,line)))
         (case (parse-result-state ,parsed-result)
           ,@(%parsed-command-line-case-branch
              :complete clauses result ast parsed-result)
           ,@(%parsed-command-line-case-branch
              :incomplete clauses result ast parsed-result)
           ,@(%parsed-command-line-case-branch
              :error clauses result ast parsed-result)
           ,@(%parsed-command-line-case-branch
              :empty clauses result ast parsed-result)))))

  (defmacro with-complete-command-line ((result ast line) &body body)
    (let ((parsed-result (gensym "PARSE-RESULT-")))
      `(let ((,parsed-result (parse-command-line ,line)))
         (when (parse-complete-p ,parsed-result)
           (let ((,result ,parsed-result)
                 (,ast (parse-result-ast ,parsed-result)))
             (declare (ignorable ,result ,ast))
             ,@body))))))

(defun %token-diagnostic (kind message token)
  (%make-parse-diagnostic kind message
                          (token-start token)
                          (token-end token)
                          token))
