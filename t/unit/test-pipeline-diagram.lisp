(in-package #:nshell/test)

(defun %diagram-node-names (graph)
  (cl-dataflow-kit:graph-node-names graph))

(defun %diagram-source-names (graph)
  (mapcar #'cl-dataflow-kit:node-name (cl-dataflow-kit:graph-source-nodes graph)))

(defun %diagram-sink-names (graph)
  (mapcar #'cl-dataflow-kit:node-name (cl-dataflow-kit:graph-sink-nodes graph)))

(describe "pipeline-diagram-tests"
  (it "pipeline-plan-translates-to-linear-dataflow-graph"
    "A three-stage pipeline becomes three nodes joined by two producer->consumer edges."
    (let* ((plan (nshell.application::%command-line->pipeline-plan "a | b x | c"))
           (graph (nshell.application::pipeline-plan->dataflow-graph plan)))
      (expect '("0:a" "1:b" "2:c") :to-equal (%diagram-node-names graph))
      (expect '("0:a") :to-equal (%diagram-source-names graph))
      (expect '("2:c") :to-equal (%diagram-sink-names graph))
      ;; A well-wired linear pipeline is a valid, acyclic dataflow graph.
      (expect (cl-dataflow-kit:validate-graph graph) :to-be-truthy)))

  (it "pipeline-plan-keeps-duplicate-commands-distinct"
    "Repeated command names stay separate nodes via the stage-index prefix."
    (let* ((plan (nshell.application::%command-line->pipeline-plan "a | a | a"))
           (graph (nshell.application::pipeline-plan->dataflow-graph plan)))
      (expect '("0:a" "1:a" "2:a") :to-equal (%diagram-node-names graph))
      (expect (cl-dataflow-kit:validate-graph graph) :to-be-truthy)))

  (it "single-command-pipeline-has-one-node-and-no-edges"
    "A bare command produces a one-node graph."
    (let* ((plan (nshell.application::%command-line->pipeline-plan "ls -la"))
           (graph (nshell.application::pipeline-plan->dataflow-graph plan)))
      (expect '("0:ls") :to-equal (%diagram-node-names graph))
      (expect (null (cl-dataflow-kit:graph-edges graph)) :to-be-truthy)))

  (it "pipeline-graph-builtin-renders-dot"
    "The pipeline-graph builtin returns exit 0 and DOT naming every stage."
    (multiple-value-bind (output code)
        (nshell.application::%builtin-pipeline-graph nil (list "a" "|" "b" "|" "c"))
      (expect 0 :to-equal code)
      (expect (search "digraph pipeline" output) :to-be-truthy)
      (expect (search "\"0:a\"" output) :to-be-truthy)
      (expect (search "\"1:b\"" output) :to-be-truthy)
      (expect (search "\"2:c\"" output) :to-be-truthy)))
  (it "pipeline-graph-builtin-rejects-non-pipeline-input"
    "Non-pipeline parse outcomes return a diagnostic instead of a graph."
    (expect (nshell.application::%command-line->pipeline-plan "") :to-be-null)
    (expect (nshell.application::%command-line->pipeline-plan "echo |") :to-be-null)
    (expect (nshell.application::%command-line->pipeline-plan "(") :to-be-null)
    (expect (nshell.application::%command-line->pipeline-plan "echo && pwd") :to-be-null)
    (multiple-value-bind (output code)
        (nshell.application::%builtin-pipeline-graph nil (list "echo" "&&" "pwd"))
      (expect 2 :to-equal code)
      (expect (search "not a simple pipeline" output) :to-be-truthy)))

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
      (expect (search "usage" output) :to-be-truthy))))
