(in-package #:nshell.domain.parsing)

(defun %single-command-p (commands)
  (and commands (null (rest commands))))

(defun %pipeline-or-command-node (commands)
  (if (%single-command-p commands)
      (first commands)
      (make-pipeline-node commands)))

(defstruct (%pipeline-group
            (:constructor %make-pipeline-group (commands)))
  (commands nil :type list :read-only t))

(defun %pipeline-group-from-reversed (commands)
  (%make-pipeline-group (nreverse commands)))

(defun %pipeline-group-ast (group)
  (%pipeline-or-command-node
   (%pipeline-group-commands group)))

(defun %command-list-commands (command-list)
  (mapcar #'first command-list))

(defun %command-list-separators (command-list)
  (mapcar #'second command-list))

(defun %command-boundary-separators (separators)
  (butlast separators))

(defun %trailing-command-separator (separators)
  (car (last separators)))

(defstruct (%command-list-assembly
            (:constructor %make-command-list-assembly
                (commands separators last-separator)))
  (commands nil :type list :read-only t)
  (separators nil :type list :read-only t)
  (last-separator nil :read-only t))

(defun %command-list-assembly-from-list (command-list)
  (let ((separators (%command-list-separators command-list)))
    (%make-command-list-assembly
     (%command-list-commands command-list)
     separators
     (%trailing-command-separator separators))))

(defun %command-list-assembly-single-command (assembly)
  (first (%command-list-assembly-commands assembly)))

(defun %command-list-assembly-background-p (assembly)
  (%background-separator-p
   (%command-list-assembly-last-separator assembly)))

(defun %background-separator-p (separator)
  (eq separator :amp))

(defun %pipeline-boundary-separator-p (separator)
  (eq separator :pipe))

(defun %sequence-boundary-separator-p (separator)
  (and separator (not (%pipeline-boundary-separator-p separator))))

(defun %all-command-boundaries-p (separators predicate)
  (every (lambda (separator)
           (funcall predicate separator))
         (%command-boundary-separators separators)))

(defun %pipeline-separators-p (separators)
  (%all-command-boundaries-p separators #'%pipeline-boundary-separator-p))

(defun %sequence-separators-p (separators)
  (%all-command-boundaries-p separators #'%sequence-boundary-separator-p))

(defun %plain-sequence-separators (separators)
  (if (%background-separator-p (%trailing-command-separator separators))
      separators
      (%command-boundary-separators separators)))

(defstruct (%command-separator-pair
            (:constructor %make-command-separator-pair
                (command separator)))
  (command nil :read-only t)
  (separator nil :read-only t))

(defun %command-separator-pairs (commands separators)
  (let ((remaining-separators (copy-list separators)))
    (loop for command in commands
          collect (%make-command-separator-pair
                   command
                   (pop remaining-separators)))))

(defstruct (%mixed-sequence-assembly
            (:constructor %make-mixed-sequence-assembly
                (commands separators)))
  (commands nil :type list :read-only t)
  (separators nil :type list :read-only t))

(defun %mixed-sequence-assembly-from-command-list-assembly (assembly)
  (%make-mixed-sequence-assembly
   (%command-list-assembly-commands assembly)
   (%command-list-assembly-separators assembly)))

(defun %mixed-sequence-assembly-pairs (assembly)
  (%command-separator-pairs
   (%mixed-sequence-assembly-commands assembly)
   (%mixed-sequence-assembly-separators assembly)))

(defstruct (%mixed-sequence-pipe-flush
            (:constructor %make-mixed-sequence-pipe-flush
                (sequence-commands pipe-group)))
  (sequence-commands nil :type list :read-only t)
  (pipe-group nil :type list :read-only t))

(defun %flush-mixed-sequence-pipe-group (sequence-commands pipe-group)
  (if pipe-group
      (%make-mixed-sequence-pipe-flush
       (cons (%pipeline-group-ast
              (%pipeline-group-from-reversed pipe-group))
             sequence-commands)
       nil)
      (%make-mixed-sequence-pipe-flush sequence-commands pipe-group)))

(defun %build-mixed-sequence (assembly)
  (let ((sequence-commands nil)
        (sequence-separators nil)
        (pipe-group nil))
    (loop for pair in (%mixed-sequence-assembly-pairs assembly)
          for command = (%command-separator-pair-command pair)
          for separator = (%command-separator-pair-separator pair)
          do (push command pipe-group)
             (when (%sequence-boundary-separator-p separator)
               (let ((flush (%flush-mixed-sequence-pipe-group
                             sequence-commands
                             pipe-group)))
                 (setf sequence-commands
                       (%mixed-sequence-pipe-flush-sequence-commands flush)
                       pipe-group
                       (%mixed-sequence-pipe-flush-pipe-group flush)))
               (push separator sequence-separators)))
    (let ((flush (%flush-mixed-sequence-pipe-group
                  sequence-commands
                  pipe-group)))
      (setf sequence-commands
            (%mixed-sequence-pipe-flush-sequence-commands flush)
            pipe-group
            (%mixed-sequence-pipe-flush-pipe-group flush)))
    (make-sequence-node (nreverse sequence-commands)
                        (nreverse sequence-separators))))

(defun %single-command-ast (assembly)
  (let ((command (%command-list-assembly-single-command assembly)))
    (if (%command-list-assembly-background-p assembly)
        (make-sequence-node (list command) '(:amp))
        command)))

(defun %pipeline-command-list-ast (assembly)
  (let* ((commands (%command-list-assembly-commands assembly))
         (node (make-pipeline-node commands)))
    (if (%command-list-assembly-background-p assembly)
        (make-sequence-node (list node) '(:amp))
        node)))

(defun %sequence-command-list-ast (assembly)
  (let ((commands (%command-list-assembly-commands assembly))
        (separators (%command-list-assembly-separators assembly)))
    (make-sequence-node commands (%plain-sequence-separators separators))))

(defun %command-list-assembly-policy (assembly)
  (let ((commands (%command-list-assembly-commands assembly))
        (separators (%command-list-assembly-separators assembly)))
    (cond
      ((null commands) :empty)
      ((%single-command-p commands) :single-command)
      ((%pipeline-separators-p separators) :pipeline)
      ((%sequence-separators-p separators) :sequence)
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

(defun %build-ast-from-command-list (command-list)
  (%command-list-assembly-ast
   (%command-list-assembly-from-list command-list)))
