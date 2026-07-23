;;; Dataflow diagnostics: render shell pipelines and the job lifecycle through
;;; cl-dataflow.
;;;
;;; nshell already models a pipeline as a linear PIPELINE-PLAN and a job as a
;;; small state machine embedded in the monitor.  cl-dataflow provides a
;;; general computation-graph and state-machine toolkit with structural
;;; validation and deterministic DOT/Mermaid export.  This module bridges the
;;; two: it translates a pipeline plan into a cl-dataflow graph (gaining free
;;; acyclicity/wiring validation and visualization) and describes the job
;;; lifecycle as a cl-dataflow state machine for analysis and diagrams.
;;;
;;; Everything here is additive and read-only — no existing execution or job
;;; path is altered.  The job-lifecycle machine is a *specification*, not a
;;; runtime enforcer: nshell's own JOB-STATE-TRANSITION remains authoritative.
(in-package #:nshell.application)

;;; --- Pipeline plan -> cl-dataflow graph --------------------------------

(defun %pipeline-stage-node-name (index command)
  "Unique, human-readable node name for the stage at INDEX running COMMAND.
The index prefix keeps duplicate command names (e.g. `a | a`) distinct."
  (format nil "~D:~A" index (nshell.domain.execution:command-name command)))

(defun pipeline-plan->dataflow-graph (plan)
  "Translate a nshell PIPELINE-PLAN into a cl-dataflow graph: one node per
stage, one edge per producer->consumer pipe.  Each node carries the stage's
full command as :command metadata."
  (let* ((graph (cl-dataflow:make-graph))
         (commands (nshell.domain.execution:pipeline-plan-commands plan))
         (names (loop for command in commands
                      for index from 0
                      collect (%pipeline-stage-node-name index command))))
    (loop for command in commands
          for name in names
          do (cl-dataflow:add-node
              graph
              (cl-dataflow:make-node
               name
               :inputs '("value")
               :outputs '("value")
               :metadata (list :command
                               (nshell.domain.execution:command-to-list command)))))
    (loop for (from to) on names
          while to
          do (cl-dataflow:add-edge graph from to
                                   :from-port "value" :to-port "value"))
    graph))

(defun pipeline-plan->dot (plan &key (name "pipeline"))
  "Render PLAN as a Graphviz DOT digraph string, validating its wiring first."
  (let ((graph (pipeline-plan->dataflow-graph plan)))
    (cl-dataflow:validate-graph graph)
    (cl-dataflow:graph->dot graph :name name)))

(defun pipeline-plan->mermaid (plan &key (direction "LR"))
  "Render PLAN as a Mermaid flowchart string."
  (cl-dataflow:graph->mermaid (pipeline-plan->dataflow-graph plan)
                              :direction direction))

;;; --- Command line -> pipeline plan -------------------------------------

(defun %command-node->command (command-node)
  "Build an execution COMMAND from a parsed COMMAND-NODE."
  (nshell.domain.execution:make-command
   (nshell.domain.parsing:command-node-command command-node)
   (nshell.domain.parsing:command-node-arg-values command-node)))

(defun %command-line->pipeline-plan (command-string)
  "Parse COMMAND-STRING and build a PIPELINE-PLAN, or signal on non-pipelines.
Returns NIL for input that is not a plain command or `|`-pipeline."
  (nshell.domain.parsing:with-parsed-command-line-case (result ast command-string)
    (:complete
     (let ((command-nodes
             (cond ((nshell.domain.parsing:pipeline-node-p ast)
                    (nshell.domain.parsing:pipeline-node-commands ast))
                   ((nshell.domain.parsing:command-node-p ast)
                    (list ast))
                   (t nil))))
       (when command-nodes
         (nshell.domain.execution:make-pipeline-plan
          (apply #'nshell.domain.execution:make-pipeline
                 (mapcar #'%command-node->command command-nodes))))))
    (:incomplete nil)
    (:error nil)
    (:empty nil)))

;;; --- Job lifecycle -> cl-dataflow state machine ------------------------
;;;
;;; States and events mirror nshell's job model (job.lisp / monitor.lisp).
;;; cl-dataflow normalizes keyword states/events to upcased strings and matches
;;; case-insensitively, so nshell's own keywords pass straight through.

(defun job-lifecycle-machine ()
  "A cl-dataflow state machine describing the nshell job lifecycle.
Transitions correspond to the monitor's real state changes plus the terminal
reap step (:completed -> :done)."
  (cl-dataflow:define-state-machine (:initial-state :created)
    (:created    :start      :running)
    (:running    :stop       :stopped)
    (:stopped    :continue   :running)
    (:running    :background :background)
    (:background :foreground :running)
    (:stopped    :foreground :running)
    (:running    :exit       :completed)
    (:stopped    :exit       :completed)
    (:background :exit       :completed)
    (:completed  :reap       :done)))

(defun job-lifecycle->dot (&key (name "job"))
  "Render the job lifecycle as a Graphviz DOT string."
  (cl-dataflow:state-machine->dot (job-lifecycle-machine) :name name))

(defun job-lifecycle->mermaid ()
  "Render the job lifecycle as a Mermaid stateDiagram-v2 string."
  (cl-dataflow:state-machine->mermaid (job-lifecycle-machine)))

(defun job-lifecycle-analysis ()
  "Return a plist summarizing the job lifecycle machine's structure."
  (let ((machine (job-lifecycle-machine)))
    (list :states (cl-dataflow:state-machine-states machine)
          :terminal (cl-dataflow:state-machine-terminal-states machine)
          :unreachable (cl-dataflow:state-machine-unreachable-states machine)
          :deterministic (cl-dataflow:state-machine-deterministic-p machine))))

;;; --- `pipeline-graph` builtin ------------------------------------------

(defun %builtin-pipeline-graph (context args)
  "Render the pipeline described by ARGS as a Graphviz DOT graph.

Usage: pipeline-graph 'CMD | CMD ...'
       pipeline-graph --mermaid 'CMD | CMD ...'

Quote the pipeline so the shell passes it as a single argument instead of
executing it.  This is a diagnostic: it parses the given command line and
visualizes its pipeline structure without executing anything."
  (declare (ignore context))
  (let* ((mermaid (and args (string= (first args) "--mermaid")))
         (tokens (if mermaid (rest args) args))
         (command-string (format nil "~{~A~^ ~}" tokens)))
    (if (zerop (length (string-trim '(#\Space #\Tab) command-string)))
        (values (format nil "pipeline-graph: usage: pipeline-graph [--mermaid] CMD [| CMD ...]~%") 2)
        (let ((plan (%command-line->pipeline-plan command-string)))
          (if plan
              (values (format nil "~A~%"
                              (if mermaid
                                  (pipeline-plan->mermaid plan)
                                  (pipeline-plan->dot plan)))
                      0)
              (values (format nil "pipeline-graph: not a simple pipeline: ~A~%"
                              command-string)
                      2))))))
