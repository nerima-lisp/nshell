(in-package #:nshell.domain.parsing)

(defun %single-command-p (commands)
  (and commands (null (rest commands))))

(defun %pipeline-or-command-node (commands)
  (if (%single-command-p commands)
      (first commands)
      (make-pipeline-node commands)))

(defun %command-list-entry-from-reduced-entry (entry)
  (list (%reduced-command-entry-command entry)
        (%reduced-command-entry-separator entry)))

(defun %command-list-entries-from-reduced-entries (entries)
  (mapcar #'%command-list-entry-from-reduced-entry entries))

(defun %command-list-commands (entries)
  (mapcar #'first entries))

(defun %command-list-separators (entries)
  (mapcar #'second entries))

(defun %command-list-assembly-from-entries (entries)
  (let ((separators (%command-list-separators entries)))
    (cons (%command-list-commands entries)
          separators)))

(defun %command-list-assembly-from-reduced-entries (entries)
  (%command-list-assembly-from-entries
   (%command-list-entries-from-reduced-entries entries)))

(defun %command-list-assembly-single-command (assembly)
  (let ((commands (%command-list-assembly-commands assembly)))
    (if (%single-command-p commands)
        (first commands)
        nil)))

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

(defun %command-list-separator-layout-separators (layout)
  layout)

(defun %command-list-separator-layout-boundary-separators (layout)
  (butlast layout))

(defun %command-list-separator-layout-trailing-separator (layout)
  (car (last layout)))

(defun %command-list-assembly-commands (assembly)
  (car assembly))

(defun %command-list-assembly-separator-layout (assembly)
  (cdr assembly))

(defun %command-separator-pairs (commands separators)
  (loop for command in commands
        for separator in separators
        collect (cons command separator)))

(defun %mixed-sequence-assembly-pairs (assembly)
  (%command-separator-pairs
   (%command-list-assembly-commands assembly)
   (%command-list-separator-layout-separators
    (%command-list-assembly-separator-layout assembly))))

(defun %empty-pending-pipeline-group ()
  nil)

(defun %pending-pipeline-group-empty-p (group)
  (null group))

(defun %pending-pipeline-group-push (group command)
  (cons command group))

(defun %pending-pipeline-group-ast (group)
  (%pipeline-or-command-node (nreverse group)))

(defun %flush-mixed-sequence-pipe-group (sequence-commands pipe-group)
  (if (%pending-pipeline-group-empty-p pipe-group)
      (cons sequence-commands pipe-group)
      (cons (cons (%pending-pipeline-group-ast pipe-group) sequence-commands)
            (%empty-pending-pipeline-group))))

(defstruct (%mixed-sequence-build-state
            (:constructor %make-mixed-sequence-build-state
                (sequence-commands sequence-separators pipe-group))
            (:copier nil))
  (sequence-commands nil :type list :read-only t)
  (sequence-separators nil :type list :read-only t)
  (pipe-group nil :type list :read-only t))

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
     (car flush)
     (%mixed-sequence-build-state-sequence-separators state)
     (cdr flush))))

(defun %mixed-sequence-build-state-record-separator (state separator)
  (%make-mixed-sequence-build-state
   (%mixed-sequence-build-state-sequence-commands state)
   (cons separator (%mixed-sequence-build-state-sequence-separators state))
   (%mixed-sequence-build-state-pipe-group state)))

(defun %mixed-sequence-build-state-accept-pair (state pair)
  (let* ((after-command
           (%mixed-sequence-build-state-push-command state (car pair)))
         (separator (cdr pair)))
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

(defun %command-list-assembly-decision-from-assembly (assembly)
  (list assembly (%command-list-assembly-policy assembly)))

(defun %command-list-assembly-decision-ast (decision)
  (let ((assembly (first decision)))
    (case (second decision)
      (:empty nil)
      (:single-command (%single-command-ast assembly))
      (:pipeline (%pipeline-command-list-ast assembly))
      (:sequence (%sequence-command-list-ast assembly))
      (:mixed-sequence
       (%build-mixed-sequence assembly)))))

(defun %command-list-assembly-ast (assembly)
  (%command-list-assembly-decision-ast
   (%command-list-assembly-decision-from-assembly assembly)))

(defun %build-ast-from-reduced-entries (entries)
  (%command-list-assembly-ast
   (%command-list-assembly-from-reduced-entries entries)))
