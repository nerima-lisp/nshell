(in-package #:nshell.domain.parsing)

(declaim (ftype (function (list) t)
                %group-control-flow-next
                %group-control-flow-if)
         (ftype (function (t) t)
                group-control-flow))

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
  (let ((scan (%group-control-flow-body (rest nodes) '("end"))))
    (%make-control-flow-node-grouping
     (funcall builder
              (%control-flow-body-scan-body scan))
     (%consume-control-flow-terminator
      (%control-flow-body-scan-rest scan)
      "end"))))

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
      (let ((scan (%group-control-flow-body (rest rest) '("end"))))
        (%make-control-flow-node-grouping
         (make-if-node condition
                       then-branch
                       (%control-flow-body-scan-body scan))
         (%consume-control-flow-terminator
          (%control-flow-body-scan-rest scan)
          "end")))))

(defun %group-control-flow-if (nodes)
  (let* ((header (first nodes))
         (condition (%command-from-header-args header)))
    (let ((scan (%group-control-flow-body (rest nodes) '("else" "end"))))
      (let ((then-branch (%control-flow-body-scan-body scan))
            (rest (%control-flow-body-scan-rest scan))
            (terminator (%control-flow-body-scan-terminator scan)))
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
            rest)))))))

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
    (let ((scan
            (%group-control-flow-clauses
             nodes
             (lambda (nodes)
               (let ((pattern (%command-first-arg-value (first nodes) "*")))
                 (let ((scan (%group-control-flow-body (rest nodes) '("end"))))
                   (%make-control-flow-clause-parse-result
                    (list (cons pattern
                                (%control-flow-body-scan-body scan)))
                    (%control-flow-body-scan-rest scan))))))))
      (%make-control-flow-node-grouping
       (make-case-node value
                       (%control-flow-clause-scan-clauses scan))
       (%control-flow-clause-scan-rest scan)))))

(defstruct (%control-flow-switch-case-patterns
            (:constructor %make-control-flow-switch-case-patterns
                (values)))
  (values nil :type list :read-only t))

(defun %control-flow-switch-case-patterns-from-header (header)
  (%make-control-flow-switch-case-patterns
   (or (command-node-arg-values header) '("*"))))

(defstruct (%control-flow-grouping-route
            (:constructor %make-control-flow-grouping-route (keyword grouper)))
  (keyword nil :type (or null string) :read-only t)
  (grouper nil :read-only t))

(defun %control-flow-grouping-route (keyword)
  (let ((grouper (cdr (assoc keyword +control-flow-grouper-specs+ :test #'string=))))
    (when grouper
      (%make-control-flow-grouping-route keyword grouper))))

(defun %control-flow-grouper (keyword)
  (let ((route (%control-flow-grouping-route keyword)))
    (and route
         (%control-flow-grouping-route-grouper route))))

(defun %group-control-flow-switch (nodes)
  (let* ((header (first nodes))
         (value (%command-first-arg-value header)))
    (let ((scan
            (%group-control-flow-clauses
             nodes
             (lambda (nodes)
               (let* ((header (first nodes))
                      (keyword (%command-keyword header)))
                 (if (and keyword (string= keyword "case"))
                     (let ((patterns
                             (%control-flow-switch-case-patterns-values
                              (%control-flow-switch-case-patterns-from-header
                               header))))
                       (let ((scan (%group-control-flow-body
                                    (rest nodes)
                                    '("case" "end"))))
                         (%make-control-flow-clause-parse-result
                          (mapcar (lambda (pattern)
                                    (cons pattern
                                          (%control-flow-body-scan-body scan)))
                                  patterns)
                          (%control-flow-body-scan-rest scan))))
                     (let ((scan (%group-control-flow-body
                                  nodes
                                  '("case" "end"))))
                       (%make-control-flow-clause-parse-result
                        (list (cons "*"
                                    (%control-flow-body-scan-body scan)))
                        (%control-flow-body-scan-rest scan)))))))))
      (%make-control-flow-node-grouping
       (make-case-node value
                       (%control-flow-clause-scan-clauses scan))
       (%control-flow-clause-scan-rest scan)))))

(defun %group-control-flow-begin (nodes)
  (%group-control-flow-with-end-body
   nodes
   (lambda (body)
     (make-begin-end-node body))))

(defun %group-control-flow-next (nodes)
  (let* ((node (first nodes))
         (keyword (%command-keyword node)))
    (let ((grouper (%control-flow-grouper keyword)))
      (if grouper
          (funcall grouper nodes)
          (%make-control-flow-node-grouping
           (group-control-flow node)
           (rest nodes))))))

(defstruct (%control-flow-boundary-consumption
            (:constructor %make-control-flow-boundary-consumption
                (separator rest-separators)))
  (separator nil :read-only t)
  (rest-separators nil :type list :read-only t))

(defun %control-flow-boundary-consumption-from-consumed-commands
    (commands rest separators)
  (let ((command-cursor commands)
        (separator-cursor separators)
        (boundary nil))
    (loop while (and command-cursor
                     (not (eq command-cursor rest)))
          do (setf boundary (first separator-cursor)
                   command-cursor (rest command-cursor)
                   separator-cursor (rest separator-cursor)))
    (%make-control-flow-boundary-consumption boundary separator-cursor)))

(defstruct (%control-flow-sequence-step
            (:constructor %make-control-flow-sequence-step
                (grouped-command boundary-separator rest-commands rest-separators)))
  (grouped-command nil :read-only t)
  (boundary-separator nil :read-only t)
  (rest-commands nil :type list :read-only t)
  (rest-separators nil :type list :read-only t))

(defun %control-flow-sequence-step-result (commands separators)
  (let* ((grouping (%group-control-flow-next commands))
         (rest (%control-flow-node-grouping-rest grouping)))
    (let ((consumption
            (%control-flow-boundary-consumption-from-consumed-commands
             commands rest separators)))
      (%make-control-flow-sequence-step
       (%control-flow-node-grouping-node grouping)
       (%control-flow-boundary-consumption-separator consumption)
       rest
       (%control-flow-boundary-consumption-rest-separators consumption)))))

(defstruct (%control-flow-sequence
            (:constructor %make-control-flow-sequence
                (commands separators)))
  (commands nil :type list :read-only t)
  (separators nil :type list :read-only t))

(defun %control-flow-sequence-from-node (node)
  (%make-control-flow-sequence
   (sequence-node-commands node)
   (sequence-node-separators node)))

(defun %control-flow-sequence-single-command-p (sequence)
  (and (%control-flow-sequence-commands sequence)
       (null (rest (%control-flow-sequence-commands sequence)))))

(defun %control-flow-sequence-background-p (sequence)
  (eq :amp (first (%control-flow-sequence-separators sequence))))

(defun %collapse-control-flow-sequence (sequence)
  (let ((commands (%control-flow-sequence-commands sequence))
        (separators (%control-flow-sequence-separators sequence)))
    (if (and (%control-flow-sequence-single-command-p sequence)
             (not (%control-flow-sequence-background-p sequence)))
        (first commands)
        (make-sequence-node commands separators))))

(defun %group-control-flow-sequence (commands separators)
  (let ((grouped-commands '())
        (grouped-separators '())
        (remaining-commands commands)
        (remaining-separators separators))
    (loop while remaining-commands
          do (let ((step (%control-flow-sequence-step-result remaining-commands
                                                             remaining-separators)))
               (push (%control-flow-sequence-step-grouped-command step)
                     grouped-commands)
               (when (%control-flow-sequence-step-boundary-separator step)
                 (push (%control-flow-sequence-step-boundary-separator step)
                       grouped-separators))
               (setf remaining-commands
                     (%control-flow-sequence-step-rest-commands step)
                     remaining-separators
                     (%control-flow-sequence-step-rest-separators step))))
    (%make-control-flow-sequence
     (nreverse grouped-commands)
     (nreverse grouped-separators))))

(defun group-control-flow (ast)
  (cond
    ((sequence-node-p ast)
      (let ((sequence (%control-flow-sequence-from-node ast)))
        (%collapse-control-flow-sequence
         (%group-control-flow-sequence
          (%control-flow-sequence-commands sequence)
          (%control-flow-sequence-separators sequence)))))
    ((pipeline-node-p ast)
     (make-pipeline-node (mapcar #'group-control-flow (pipeline-node-commands ast))))
    (t ast)))
