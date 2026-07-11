(in-package #:nshell.domain.parsing)

(declaim (ftype (function (list) t)
                %group-control-flow-next)
         (ftype (function (t) t)
                group-control-flow))

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
          do (let ((step (%control-flow-sequence-step-result
                          remaining-commands
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

(defstruct (%control-flow-grouper-route
            (:constructor %make-control-flow-grouper-route (keyword grouper)))
  (keyword nil :type (or null string) :read-only t)
  (grouper nil :read-only t))

(defun %control-flow-grouper-route (keyword)
  (let ((entry (assoc keyword +control-flow-grouper-specs+ :test #'string=)))
    (when entry
      (%make-control-flow-grouper-route (car entry) (cdr entry)))))

(defun %control-flow-grouper (keyword)
  (let ((route (%control-flow-grouper-route keyword)))
    (and route
         (%control-flow-grouper-route-grouper route))))

(defun %group-control-flow-next (nodes)
  (let* ((node (first nodes))
         (keyword (%command-keyword node)))
    (let ((grouper (%control-flow-grouper keyword)))
      (if grouper
          (funcall grouper nodes)
          (%make-control-flow-node-grouping
           (group-control-flow node)
           (rest nodes))))))

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
