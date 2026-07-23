(in-package #:nshell/test)

;;; Tests for the cl-dataflow diagnostics module (src/application/pipeline-diagram):
;;; pipeline plans translated into cl-dataflow graphs, and the job lifecycle
;;; described as a cl-dataflow state machine.

(defun %diagram-node-names (graph)
  (cl-dataflow:graph-node-names graph))

(defun %diagram-source-names (graph)
  (mapcar #'cl-dataflow:node-name (cl-dataflow:graph-source-nodes graph)))

(defun %diagram-sink-names (graph)
  (mapcar #'cl-dataflow:node-name (cl-dataflow:graph-sink-nodes graph)))

(describe "pipeline-diagram-tests"
  (it "pipeline-plan-translates-to-linear-dataflow-graph"
    "A three-stage pipeline becomes three nodes joined by two producer->consumer edges."
    (let* ((plan (nshell.application::%command-line->pipeline-plan "a | b x | c"))
           (graph (nshell.application::pipeline-plan->dataflow-graph plan)))
      (expect '("0:a" "1:b" "2:c") :to-equal (%diagram-node-names graph))
      (expect '("0:a") :to-equal (%diagram-source-names graph))
      (expect '("2:c") :to-equal (%diagram-sink-names graph))
      ;; A well-wired linear pipeline is a valid, acyclic dataflow graph.
      (expect (cl-dataflow:validate-graph graph) :to-be-truthy)))

  (it "pipeline-plan-keeps-duplicate-commands-distinct"
    "Repeated command names stay separate nodes via the stage-index prefix."
    (let* ((plan (nshell.application::%command-line->pipeline-plan "a | a | a"))
           (graph (nshell.application::pipeline-plan->dataflow-graph plan)))
      (expect '("0:a" "1:a" "2:a") :to-equal (%diagram-node-names graph))
      (expect (cl-dataflow:validate-graph graph) :to-be-truthy)))

  (it "single-command-pipeline-has-one-node-and-no-edges"
    "A bare command produces a one-node graph."
    (let* ((plan (nshell.application::%command-line->pipeline-plan "ls -la"))
           (graph (nshell.application::pipeline-plan->dataflow-graph plan)))
      (expect '("0:ls") :to-equal (%diagram-node-names graph))
      (expect (null (cl-dataflow:graph-edges graph)) :to-be-truthy)))

  (it "pipeline-graph-builtin-renders-dot"
    "The pipeline-graph builtin returns exit 0 and DOT naming every stage."
    (multiple-value-bind (output code)
        (nshell.application::%builtin-pipeline-graph nil (list "a" "|" "b" "|" "c"))
      (expect 0 :to-equal code)
      (expect (search "digraph pipeline" output) :to-be-truthy)
      (expect (search "\"0:a\"" output) :to-be-truthy)
      (expect (search "\"1:b\"" output) :to-be-truthy)
      (expect (search "\"2:c\"" output) :to-be-truthy)))

  (it "pipeline-graph-builtin-renders-mermaid"
    "The --mermaid flag switches the renderer to a Mermaid flowchart."
    (multiple-value-bind (output code)
        (nshell.application::%builtin-pipeline-graph nil (list "--mermaid" "a" "|" "b"))
      (expect 0 :to-equal code)
      (expect (search "flowchart" output) :to-be-truthy)))

  (it "pipeline-graph-builtin-reports-usage-on-empty-input"
    "With no command line, the builtin reports usage and a non-zero code."
    (multiple-value-bind (output code)
        (nshell.application::%builtin-pipeline-graph nil nil)
      (expect 2 :to-equal code)
      (expect (search "usage" output) :to-be-truthy)))

  (it "job-lifecycle-machine-is-well-formed"
    "Every job state is reachable, DONE is the only terminal state, and the
machine is deterministic."
    (let ((analysis (nshell.application::job-lifecycle-analysis)))
      (expect '("DONE") :to-equal (getf analysis :terminal))
      (expect (null (getf analysis :unreachable)) :to-be-truthy)
      (expect (getf analysis :deterministic) :to-be-truthy)))

  (it "job-lifecycle-machine-covers-the-real-monitor-transitions"
    "The documented machine admits every transition the job monitor performs,
guarding the spec against runtime drift."
    (let ((machine (nshell.application::job-lifecycle-machine)))
      (dolist (transition '(("CREATED" "START")
                            ("RUNNING" "STOP")
                            ("STOPPED" "CONTINUE")
                            ("RUNNING" "BACKGROUND")
                            ("BACKGROUND" "FOREGROUND")
                            ("RUNNING" "EXIT")))
        (destructuring-bind (state event) transition
          (expect (cl-dataflow:state-machine-transition-for machine state event)
                  :to-be-truthy))))))
