(in-package #:nshell.domain.parsing)

(defstruct (parse-result (:constructor make-parse-result (ast &optional errors incomplete)))
  (ast nil :type (or null ast-node))
  (errors nil :type list)
  (incomplete nil :type boolean))

(defstruct (parse-diagnostic
            (:constructor make-parse-diagnostic
                (kind message start end &optional token)))
  (kind :error :type keyword :read-only t)
  (message "" :type string :read-only t)
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t)
  (token nil :read-only t))

(defun parse-complete-p (result)
  (and (parse-result-ast result)
       (null (parse-result-errors result))
       (not (parse-result-incomplete result))))

(defun parse-result-state (result)
  (cond
    ((parse-complete-p result) :complete)
    ((parse-result-incomplete result) :incomplete)
    ((parse-errors result) :error)))

(defun parse-errors (result)
  (parse-result-errors result))

(defun parse-error-messages (result)
  (mapcar #'parse-diagnostic-message (parse-errors result)))

(defun format-parse-error-messages (result)
  (format nil "~{~a~^; ~}" (parse-error-messages result)))

(defun parse-diagnostic-kind-p (result kind)
  (not (null (find kind (parse-errors result)
                   :key #'parse-diagnostic-kind))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro with-parsed-command-line ((result line) &body body)
    `(let ((,result (parse-command-line ,line)))
       (declare (ignorable ,result))
       ,@body))

  (defmacro with-parsed-command-line-case ((result ast line) &body clauses)
    (labels ((branch-body (keyword)
               (cdr (assoc keyword clauses))))
      (let ((parsed-result (gensym "PARSE-RESULT-")))
        `(let ((,parsed-result (parse-command-line ,line)))
           (case (parse-result-state ,parsed-result)
             (:complete
              (let ((,result ,parsed-result)
                    (,ast (parse-result-ast ,parsed-result)))
                (declare (ignorable ,result ,ast))
                ,@(branch-body :complete)))
             (:incomplete
              (let ((,result ,parsed-result)
                    (,ast (parse-result-ast ,parsed-result)))
                (declare (ignorable ,result ,ast))
                ,@(branch-body :incomplete)))
             (:error
              (let ((,result ,parsed-result)
                    (,ast (parse-result-ast ,parsed-result)))
                (declare (ignorable ,result ,ast))
                ,@(branch-body :error))))))))

  (defmacro with-complete-command-line ((result ast line) &body body)
    (let ((parsed-result (gensym "PARSE-RESULT-")))
      `(let ((,parsed-result (parse-command-line ,line)))
         (when (parse-complete-p ,parsed-result)
           (let ((,result ,parsed-result)
                 (,ast (parse-result-ast ,parsed-result)))
             (declare (ignorable ,result ,ast))
             ,@body)))))
  )

(defun %token-diagnostic (kind message token)
  (make-parse-diagnostic kind message
                         (token-start token)
                         (token-end token)
                         token))
