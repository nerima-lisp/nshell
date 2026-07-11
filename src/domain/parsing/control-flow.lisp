(in-package #:nshell.domain.parsing)

(declaim (ftype (function (list) t)
                %group-control-flow-if))

(defstruct (%control-flow-body-scan
            (:constructor %make-control-flow-body-scan
                (body rest terminator)))
  (body nil :type list :read-only t)
  (rest nil :type list :read-only t)
  (terminator nil :type (or null string) :read-only t))

(defstruct (%control-flow-node-grouping
            (:constructor %make-control-flow-node-grouping
                (node rest)))
  (node nil :read-only t)
  (rest nil :type list :read-only t))

(defmacro %with-control-flow-body-scan ((body rest terminator)
                                        nodes
                                        terminators
                                        &body forms)
  (let ((scan (gensym "SCAN")))
    `(let* ((,scan (%group-control-flow-body ,nodes ,terminators))
            (,body (%control-flow-body-scan-body ,scan))
            (,rest (%control-flow-body-scan-rest ,scan))
       (,terminator (%control-flow-body-scan-terminator ,scan)))
       ,@forms)))

(defmacro %with-control-flow-clause-body-scan ((body rest terminator)
                                               nodes
                                               terminators
                                               &body forms)
  `(%with-control-flow-body-scan (,body ,rest ,terminator)
       ,nodes
       ,terminators
     (declare (ignore ,terminator))
     ,@forms))

(defun %group-control-flow-body (nodes terminators)
  (let ((body nil)
        (remaining nodes)
        (stop nil))
    (loop while remaining
          for node = (first remaining)
          for keyword = (%command-keyword node)
           do (if (and keyword (member keyword terminators :test #'string=))
                  (progn
                    (setf stop keyword)
                    (return))
                  (let ((grouping (%group-control-flow-next remaining)))
                    (push (%control-flow-node-grouping-node grouping) body)
                    (setf remaining
                          (%control-flow-node-grouping-rest grouping)))))
    (%make-control-flow-body-scan (nreverse body) remaining stop)))

(defstruct (%control-flow-clause-parse-result
            (:constructor %make-control-flow-clause-parse-result
                (clauses rest)))
  (clauses nil :type list :read-only t)
  (rest nil :type list :read-only t))

(defstruct (%control-flow-clause-scan
            (:constructor %make-control-flow-clause-scan
                (clauses rest)))
  (clauses nil :type list :read-only t)
  (rest nil :type list :read-only t))

(defun %group-control-flow-clauses (nodes clause-parser)
  (let ((clauses nil)
        (remaining (rest nodes)))
    (loop while remaining
          for keyword = (%command-keyword (first remaining))
          do (cond
                ((and keyword (string= keyword "end"))
                 (setf remaining (rest remaining))
                 (return))
                (t
                 (let ((result (funcall clause-parser remaining)))
                   (dolist (clause
                            (%control-flow-clause-parse-result-clauses result))
                     (push clause clauses))
                   (setf remaining
                         (%control-flow-clause-parse-result-rest result))))))
    (%make-control-flow-clause-scan (nreverse clauses) remaining)))

(defun %group-control-flow-with-end-body (nodes builder)
  (%with-control-flow-body-scan (body rest terminator)
      (rest nodes)
      '("end")
    (declare (ignore terminator))
    (%make-control-flow-node-grouping
     (funcall builder body)
     (%consume-control-flow-terminator rest "end"))))

(defun %group-control-flow-else-if (condition then-branch rest)
  (let ((else-if
          (%group-control-flow-if
           (cons (%command-from-header-args (first rest))
                 (rest rest)))))
    (%make-control-flow-node-grouping
     (make-if-node condition
                   then-branch
                   (list (%control-flow-node-grouping-node else-if)))
     (%control-flow-node-grouping-rest else-if))))

(defun %group-control-flow-if-else (condition then-branch rest)
  (if (%else-if-header-p (first rest))
      (%group-control-flow-else-if condition then-branch rest)
      (%with-control-flow-body-scan (body scan-rest scan-terminator)
          (rest rest)
          '("end")
        (declare (ignore scan-terminator))
        (%make-control-flow-node-grouping
         (make-if-node condition then-branch body)
         (%consume-control-flow-terminator scan-rest "end")))))

(defun %group-control-flow-if (nodes)
  (let* ((header (first nodes))
         (condition (%command-from-header-args header)))
    (%with-control-flow-body-scan (then-branch rest terminator)
        (rest nodes)
        '("else" "end")
      (cond
        ((and terminator (string= terminator "else"))
         (%group-control-flow-if-else condition then-branch rest))
        ((and terminator (string= terminator "end"))
         (%make-control-flow-node-grouping
          (make-if-node condition then-branch)
          (%consume-control-flow-terminator rest "end")))
        (t
         (%make-control-flow-node-grouping
          (make-if-node condition then-branch)
          rest))))))

(defun %control-flow-case-clause-parse-result (nodes)
  (let ((pattern (%command-first-arg-value (first nodes) "*")))
    (%with-control-flow-clause-body-scan (body rest terminator)
        (rest nodes)
        '("end")
      (%make-control-flow-clause-parse-result
       (list (make-case-clause pattern body))
       rest))))

(defstruct (%control-flow-for-header-binding
            (:constructor %make-control-flow-for-header-binding
                (var-name in-values)))
  (var-name "" :type string :read-only t)
  (in-values nil :type list :read-only t))

(defun %control-flow-for-header-binding-from-header (header)
  (let* ((args (command-node-args header))
         (in-pos (position "in" args :test (lambda (item arg)
                                             (string= item (arg-value arg)))))
         (in-values (if in-pos (subseq args (1+ in-pos)) (rest args))))
    (%make-control-flow-for-header-binding
     (%command-first-arg-value header)
     in-values)))

(defun %group-control-flow-for (nodes)
  (let* ((header (first nodes))
         (binding (%control-flow-for-header-binding-from-header header)))
    (%group-control-flow-with-end-body
     nodes
     (lambda (body)
       (make-for-node
        (%control-flow-for-header-binding-var-name binding)
        (%control-flow-for-header-binding-in-values binding)
        body)))))

(defun %group-control-flow-while (nodes)
  (let ((condition (%command-from-header-args (first nodes))))
    (%group-control-flow-with-end-body
     nodes
     (lambda (body)
       (make-while-node condition body)))))

(defun %group-control-flow-case (nodes)
  (let* ((header (first nodes))
         (value (%command-first-arg-value header)))
    (%group-control-flow-case-node-grouping
     value
     (%group-control-flow-clauses
      nodes
      #'%control-flow-case-clause-parse-result))))

(defstruct (%control-flow-switch-case-patterns
            (:constructor %make-control-flow-switch-case-patterns
                (values)))
  (values nil :type list :read-only t))

(defun %control-flow-switch-case-patterns-from-header (header)
  (%make-control-flow-switch-case-patterns
   (or (command-node-arg-values header) '("*"))))

(defun %control-flow-switch-case-clause-parse-result (header nodes)
  (let ((patterns (%control-flow-switch-case-patterns-values
                   (%control-flow-switch-case-patterns-from-header
                    header))))
    (%with-control-flow-clause-body-scan (body rest terminator)
        (rest nodes)
        '("case" "end")
      (%make-control-flow-clause-parse-result
       (mapcar (lambda (pattern)
                 (make-case-clause pattern body))
               patterns)
       rest))))

(defun %control-flow-switch-default-clause-parse-result (nodes)
  (%with-control-flow-clause-body-scan (body rest terminator)
      nodes
      '("case" "end")
    (%make-control-flow-clause-parse-result
     (list (make-case-clause "*" body))
     rest)))

(defun %group-control-flow-case-node-grouping (value scan)
  (%make-control-flow-node-grouping
   (make-case-node value
                   (%control-flow-clause-scan-clauses scan))
   (%control-flow-clause-scan-rest scan)))

(defun %group-control-flow-switch (nodes)
  (let* ((header (first nodes))
         (value (%command-first-arg-value header)))
    (%group-control-flow-case-node-grouping
     value
     (%group-control-flow-clauses
      nodes
      (lambda (nodes)
        (let* ((header (first nodes))
               (keyword (%command-keyword header)))
          (if (and keyword (string= keyword "case"))
              (%control-flow-switch-case-clause-parse-result header nodes)
              (%control-flow-switch-default-clause-parse-result nodes))))))))

(defun %group-control-flow-begin (nodes)
  (%group-control-flow-with-end-body
   nodes
   (lambda (body)
     (make-begin-end-node body))))
