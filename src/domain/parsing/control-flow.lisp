(in-package #:nshell.domain.parsing)

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
                 (multiple-value-bind (parsed rest)
                     (%group-control-flow-next remaining)
                   (push parsed body)
                   (setf remaining rest))))
    (values (nreverse body) remaining stop)))

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
                (multiple-value-bind (new-clauses rest)
                    (funcall clause-parser remaining)
                  (dolist (clause new-clauses)
                    (push clause clauses))
                  (setf remaining rest)))))
    (values (nreverse clauses) remaining)))

(defun %group-control-flow-with-end-body (nodes builder)
  (multiple-value-bind (body rest)
      (%group-control-flow-body (rest nodes) '("end"))
    (values (funcall builder body)
            (%consume-control-flow-terminator rest "end"))))

(defun %group-control-flow-else-if (condition then-branch rest)
  (multiple-value-bind (else-if after-else-if)
      (%group-control-flow-if
       (cons (%command-from-header-args (first rest))
             (rest rest)))
    (values (make-if-node condition then-branch (list else-if))
            after-else-if)))

(defun %group-control-flow-if-else (condition then-branch rest)
  (if (%else-if-header-p (first rest))
      (%group-control-flow-else-if condition then-branch rest)
      (multiple-value-bind (else-branch after-else)
          (%group-control-flow-body (rest rest) '("end"))
        (values (make-if-node condition then-branch else-branch)
                (%consume-control-flow-terminator after-else "end")))))

(defun %group-control-flow-if (nodes)
  (let* ((header (first nodes))
         (condition (%command-from-header-args header)))
    (multiple-value-bind (then-branch rest stop)
        (%group-control-flow-body (rest nodes) '("else" "end"))
      (cond
        ((and stop (string= stop "else"))
         (%group-control-flow-if-else condition then-branch rest))
        ((and stop (string= stop "end"))
         (values (make-if-node condition then-branch)
                 (%consume-control-flow-terminator rest "end")))
        (t (values (make-if-node condition then-branch) rest))))))

(defun %group-control-flow-for (nodes)
  (let* ((header (first nodes))
         (args (command-node-args header))
         (var-name (%command-first-arg-value header))
         (in-pos (position "in" args :test (lambda (item arg)
                                             (string= item (arg-value arg)))))
         (in-values (if in-pos (subseq args (1+ in-pos)) (rest args))))
    (%group-control-flow-with-end-body
     nodes
     (lambda (body)
       (make-for-node var-name in-values body)))))

(defun %group-control-flow-while (nodes)
  (let ((condition (%command-from-header-args (first nodes))))
    (%group-control-flow-with-end-body
     nodes
     (lambda (body)
       (make-while-node condition body)))))

(defun %group-control-flow-case (nodes)
  (let* ((header (first nodes))
         (value (%command-first-arg-value header)))
    (multiple-value-bind (clauses remaining)
        (%group-control-flow-clauses
         nodes
         (lambda (nodes)
           (let ((pattern (%command-first-arg-value (first nodes) "*")))
             (multiple-value-bind (body rest)
                 (%group-control-flow-body (rest nodes) '("end"))
               (values (list (cons pattern body)) rest)))))
      (values (make-case-node value clauses) remaining))))

(defun %control-flow-grouper (keyword)
  (cdr (assoc keyword +control-flow-grouper-specs+ :test #'string=)))

(defun %group-control-flow-switch (nodes)
  (let* ((header (first nodes))
         (value (%command-first-arg-value header)))
    (multiple-value-bind (clauses remaining)
        (%group-control-flow-clauses
         nodes
         (lambda (nodes)
           (let* ((header (first nodes))
                  (keyword (%command-keyword header)))
             (if (and keyword (string= keyword "case"))
                 (let ((patterns (or (command-node-arg-values header)
                                     '("*"))))
                   (multiple-value-bind (body rest)
                       (%group-control-flow-body (rest nodes) '("case" "end"))
                     (values (mapcar (lambda (pattern)
                                       (cons pattern body))
                                     patterns)
                             rest)))
                 (multiple-value-bind (body rest)
                     (%group-control-flow-body nodes '("case" "end"))
                   (values (list (cons "*" body)) rest))))))
      (values (make-case-node value clauses) remaining))))

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
          (values (group-control-flow node) (rest nodes))))))

(defun %group-control-flow-sequence (commands separators)
  (let ((grouped-commands '())
        (grouped-separators '())
        (remaining commands)
        (start-index 0))
    (loop while remaining
          do (let ((before remaining))
               (multiple-value-bind (parsed rest)
                   (%group-control-flow-next remaining)
                 (let* ((consumed (- (length before) (length rest)))
                        (separator-index (+ start-index consumed -1))
                        (separator (nth separator-index separators)))
                   (push parsed grouped-commands)
                   (when separator
                     (push separator grouped-separators))
                   (incf start-index consumed)
                   (setf remaining rest)))))
    (values (nreverse grouped-commands)
            (nreverse grouped-separators))))

(defun group-control-flow (ast)
  (cond
    ((sequence-node-p ast)
     (multiple-value-bind (commands separators)
         (%group-control-flow-sequence (sequence-node-commands ast)
                                       (sequence-node-separators ast))
         (if (and (= (length commands) 1)
                  (not (eq :amp (first separators))))
             (first commands)
             (make-sequence-node commands separators))))
    ((pipeline-node-p ast)
     (make-pipeline-node (mapcar #'group-control-flow (pipeline-node-commands ast))))
    (t ast)))
