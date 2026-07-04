(in-package #:nshell.domain.parsing)

(defstruct (%command-list-cardinality
            (:constructor %make-command-list-cardinality
                (single-command single-command-p)))
  (single-command nil :read-only t)
  (single-command-p nil :type boolean :read-only t))

(defun %command-list-cardinality (commands)
  (if (and commands (null (rest commands)))
      (%make-command-list-cardinality (first commands) t)
      (%make-command-list-cardinality nil nil)))

(defun %single-command-p (commands)
  (%command-list-cardinality-single-command-p
   (%command-list-cardinality commands)))

(defun %pipeline-or-command-node (commands)
  (let ((cardinality (%command-list-cardinality commands)))
    (if (%command-list-cardinality-single-command-p cardinality)
        (%command-list-cardinality-single-command cardinality)
        (make-pipeline-node commands))))

(defstruct (%pipeline-group
            (:constructor %make-pipeline-group (commands)))
  (commands nil :type list :read-only t))

(defun %pipeline-group-from-reversed (commands)
  (%make-pipeline-group (nreverse commands)))

(defun %pipeline-group-ast (group)
  (%pipeline-or-command-node
   (%pipeline-group-commands group)))

(defstruct (%command-list-entry
            (:constructor %make-command-list-entry
                (command separator)))
  (command nil :read-only t)
  (separator nil :read-only t))

(defun %command-list-entry-from-reduced-entry (entry)
  (%make-command-list-entry
   (%reduced-command-entry-command entry)
   (%reduced-command-entry-separator entry)))

(defun %command-list-entries-from-reduced-entries (entries)
  (mapcar #'%command-list-entry-from-reduced-entry entries))

(defun %command-list-commands (entries)
  (mapcar #'%command-list-entry-command entries))

(defun %command-list-separators (entries)
  (mapcar #'%command-list-entry-separator entries))

(defstruct (%command-list-separator-layout
            (:constructor %make-command-list-separator-layout
                (separators boundary-separators trailing-separator)))
  (separators nil :type list :read-only t)
  (boundary-separators nil :type list :read-only t)
  (trailing-separator nil :read-only t))

(defun %command-list-separator-layout-from-separators (separators)
  (%make-command-list-separator-layout
   separators
   (butlast separators)
   (car (last separators))))

(defstruct (%command-list-assembly
            (:constructor %make-command-list-assembly
                (commands separator-layout)))
  (commands nil :type list :read-only t)
  (separator-layout nil :read-only t))

(defun %command-list-assembly-from-entries (entries)
  (let ((separators (%command-list-separators entries)))
    (%make-command-list-assembly
     (%command-list-commands entries)
     (%command-list-separator-layout-from-separators separators))))

(defun %command-list-assembly-from-reduced-entries (entries)
  (%command-list-assembly-from-entries
   (%command-list-entries-from-reduced-entries entries)))

(defun %command-list-assembly-single-command (assembly)
  (%command-list-cardinality-single-command
   (%command-list-cardinality
    (%command-list-assembly-commands assembly))))

(defun %command-list-assembly-background-p (assembly)
  (%background-separator-p
   (%command-list-separator-layout-trailing-separator
    (%command-list-assembly-separator-layout assembly))))

(defun %background-separator-p (separator)
  (eq separator :amp))

(defun %pipeline-boundary-separator-p (separator)
  (eq separator :pipe))

(defun %sequence-boundary-separator-p (separator)
  (and separator (not (%pipeline-boundary-separator-p separator))))

(defun %all-command-boundaries-p (layout predicate)
  (every (lambda (separator)
           (funcall predicate separator))
         (%command-list-separator-layout-boundary-separators layout)))

(defun %pipeline-separators-p (layout)
  (%all-command-boundaries-p layout #'%pipeline-boundary-separator-p))

(defun %sequence-separators-p (layout)
  (%all-command-boundaries-p layout #'%sequence-boundary-separator-p))

(defun %plain-sequence-separators (layout)
  (if (%background-separator-p
       (%command-list-separator-layout-trailing-separator layout))
      (%command-list-separator-layout-separators layout)
      (%command-list-separator-layout-boundary-separators layout)))

(defstruct (%command-separator-pair
            (:constructor %make-command-separator-pair
                (command separator)))
  (command nil :read-only t)
  (separator nil :read-only t))

(defstruct (%command-separator-pair-source
            (:constructor %make-command-separator-pair-source
                (commands separators)))
  (commands nil :type list :read-only t)
  (separators nil :type list :read-only t))

(defun %command-separator-pairs (source)
  (loop for command in (%command-separator-pair-source-commands source)
        for separator in (%command-separator-pair-source-separators source)
        collect (%make-command-separator-pair command separator)))

(defstruct (%mixed-sequence-assembly
            (:constructor %make-mixed-sequence-assembly
                (commands separator-layout)))
  (commands nil :type list :read-only t)
  (separator-layout nil :read-only t))

(defun %mixed-sequence-assembly-from-command-list-assembly (assembly)
  (%make-mixed-sequence-assembly
   (%command-list-assembly-commands assembly)
   (%command-list-assembly-separator-layout assembly)))

(defun %mixed-sequence-assembly-pairs (assembly)
  (%command-separator-pairs
   (%make-command-separator-pair-source
    (%mixed-sequence-assembly-commands assembly)
    (%command-list-separator-layout-separators
     (%mixed-sequence-assembly-separator-layout assembly)))))

(defstruct (%pending-pipeline-group
            (:constructor %make-pending-pipeline-group
                (commands)))
  (commands nil :type list :read-only t))

(defun %empty-pending-pipeline-group ()
  (%make-pending-pipeline-group nil))

(defun %pending-pipeline-group-empty-p (group)
  (null (%pending-pipeline-group-commands group)))

(defun %pending-pipeline-group-push (group command)
  (%make-pending-pipeline-group
   (cons command (%pending-pipeline-group-commands group))))

(defun %pending-pipeline-group-ast (group)
  (%pipeline-group-ast
   (%pipeline-group-from-reversed
    (%pending-pipeline-group-commands group))))

(defstruct (%mixed-sequence-pipe-flush
            (:constructor %make-mixed-sequence-pipe-flush
                (sequence-commands pipe-group)))
  (sequence-commands nil :type list :read-only t)
  (pipe-group nil :read-only t))

(defun %flush-mixed-sequence-pipe-group (sequence-commands pipe-group)
  (if (not (%pending-pipeline-group-empty-p pipe-group))
      (%make-mixed-sequence-pipe-flush
       (cons (%pending-pipeline-group-ast pipe-group) sequence-commands)
       (%empty-pending-pipeline-group))
      (%make-mixed-sequence-pipe-flush sequence-commands pipe-group)))

(defstruct (%mixed-sequence-build-state
            (:constructor %make-mixed-sequence-build-state
                (sequence-commands sequence-separators pipe-group)))
  (sequence-commands nil :type list :read-only t)
  (sequence-separators nil :type list :read-only t)
  (pipe-group nil :read-only t))

(defun %empty-mixed-sequence-build-state ()
  (%make-mixed-sequence-build-state nil nil (%empty-pending-pipeline-group)))

(defun %mixed-sequence-build-state-push-command (state command)
  (%make-mixed-sequence-build-state
   (%mixed-sequence-build-state-sequence-commands state)
   (%mixed-sequence-build-state-sequence-separators state)
   (%pending-pipeline-group-push
    (%mixed-sequence-build-state-pipe-group state)
    command)))

(defun %mixed-sequence-build-state-flush-pipe-group (state)
  (let ((flush (%flush-mixed-sequence-pipe-group
                (%mixed-sequence-build-state-sequence-commands state)
                (%mixed-sequence-build-state-pipe-group state))))
    (%make-mixed-sequence-build-state
     (%mixed-sequence-pipe-flush-sequence-commands flush)
     (%mixed-sequence-build-state-sequence-separators state)
     (%mixed-sequence-pipe-flush-pipe-group flush))))

(defun %mixed-sequence-build-state-record-separator (state separator)
  (%make-mixed-sequence-build-state
   (%mixed-sequence-build-state-sequence-commands state)
   (cons separator (%mixed-sequence-build-state-sequence-separators state))
   (%mixed-sequence-build-state-pipe-group state)))

(defun %mixed-sequence-build-state-accept-pair (state pair)
  (let* ((after-command
           (%mixed-sequence-build-state-push-command
            state
            (%command-separator-pair-command pair)))
         (separator (%command-separator-pair-separator pair)))
    (if (%sequence-boundary-separator-p separator)
        (%mixed-sequence-build-state-record-separator
         (%mixed-sequence-build-state-flush-pipe-group after-command)
         separator)
        after-command)))

(defun %mixed-sequence-build-state-ast (state)
  (let ((final-state (%mixed-sequence-build-state-flush-pipe-group state)))
    (make-sequence-node
     (nreverse (%mixed-sequence-build-state-sequence-commands final-state))
     (nreverse (%mixed-sequence-build-state-sequence-separators final-state)))))

(defun %build-mixed-sequence (assembly)
  (let ((state (%empty-mixed-sequence-build-state)))
    (loop for pair in (%mixed-sequence-assembly-pairs assembly)
          do (setf state (%mixed-sequence-build-state-accept-pair state pair)))
    (%mixed-sequence-build-state-ast state)))

(defun %background-command-list-ast (command)
  (make-sequence-node (list command) '(:amp)))

(defun %single-command-ast (assembly)
  (let ((command (%command-list-assembly-single-command assembly)))
    (if (%command-list-assembly-background-p assembly)
        (%background-command-list-ast command)
        command)))

(defun %pipeline-command-list-ast (assembly)
  (let* ((commands (%command-list-assembly-commands assembly))
         (node (make-pipeline-node commands)))
    (if (%command-list-assembly-background-p assembly)
        (%background-command-list-ast node)
        node)))

(defun %sequence-command-list-ast (assembly)
  (let ((commands (%command-list-assembly-commands assembly))
        (layout (%command-list-assembly-separator-layout assembly)))
    (make-sequence-node commands (%plain-sequence-separators layout))))

(defun %command-list-assembly-policy (assembly)
  (let ((commands (%command-list-assembly-commands assembly))
        (layout (%command-list-assembly-separator-layout assembly)))
    (cond
      ((null commands) :empty)
      ((%single-command-p commands) :single-command)
      ((%pipeline-separators-p layout) :pipeline)
      ((%sequence-separators-p layout) :sequence)
      (t :mixed-sequence))))

(defstruct (%command-list-assembly-decision
            (:constructor %make-command-list-assembly-decision
                (assembly policy)))
  (assembly nil :read-only t)
  (policy nil :read-only t))

(defun %command-list-assembly-decision-from-assembly (assembly)
  (%make-command-list-assembly-decision
   assembly
   (%command-list-assembly-policy assembly)))

(defun %command-list-assembly-decision-ast (decision)
  (let ((assembly (%command-list-assembly-decision-assembly decision)))
    (case (%command-list-assembly-decision-policy decision)
      (:empty nil)
      (:single-command (%single-command-ast assembly))
      (:pipeline (%pipeline-command-list-ast assembly))
      (:sequence (%sequence-command-list-ast assembly))
      (:mixed-sequence
       (%build-mixed-sequence
        (%mixed-sequence-assembly-from-command-list-assembly
         assembly))))))

(defun %command-list-assembly-ast (assembly)
  (%command-list-assembly-decision-ast
   (%command-list-assembly-decision-from-assembly assembly)))

(defun %build-ast-from-reduced-entries (entries)
  (%command-list-assembly-ast
   (%command-list-assembly-from-reduced-entries entries)))
