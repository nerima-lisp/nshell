(in-package #:nshell.application)

(define-condition command-failed (error)
  ((command :initarg :command :reader command-failed-command)
   (status :initarg :status :reader command-failed-status)
   (pipeline-status :initarg :pipeline-status :initform nil
                    :reader command-failed-pipeline-status)
   (stage-statuses :initarg :stage-statuses :reader command-failed-stage-statuses)
   (signal :initarg :signal :reader command-failed-signal)))

(defvar *interactive-top-level-p* nil)

(defvar *command-test-position-p* nil)
(defvar *command-failure-handler-active-p* nil)

(defvar *errexit-p* nil)
(defvar *command-pipefail-p* nil)
(declaim (ftype (function (t function) (values t integer)) call-with-command-failure-policy))
(defun call-with-command-failure-policy (command-ast thunk)
  (multiple-value-bind (value status pipeline-result)
      (funcall thunk)
    (check-type status integer)
    (unless (pipeline-execution-result-p pipeline-result)
      (error "Command evaluation returned no pipeline execution result."))
    (let* ((stages
             (cond
               ((nshell.domain.parsing:pipeline-node-p command-ast)
                (nshell.domain.parsing:pipeline-node-commands command-ast))
               ((nshell.domain.parsing:command-node-p command-ast)
                (list command-ast))
               (t
                (error "Expected a command or pipeline AST, got ~S."
                       command-ast))))
           (stage-count (length stages))
           (stage-statuses
             (pipeline-execution-result-stage-statuses pipeline-result))
           (stage-signals
             (pipeline-execution-result-stage-signals pipeline-result)))
      (unless (and (plusp stage-count)
                   (listp stage-statuses)
                   (listp stage-signals)
                   (= (length stage-statuses) stage-count)
                   (= (length stage-signals) stage-count)
                   (every (function integerp) stage-statuses)
                   (every (lambda (signal)
                            (or (null signal)
                                (and (integerp signal) (plusp signal))))
                          stage-signals))
        (error "Malformed pipeline execution result for ~d command stages."
               stage-count))
      (let* ((expected-status
               (if *command-pipefail-p*
                   (or (find-if (lambda (stage-status)
                                  (not (zerop stage-status)))
                                stage-statuses)
                       0)
                   (or (car (last stage-statuses)) 0)))
             (pipeline-status
               (pipeline-execution-result-status pipeline-result)))
        (unless (and (= status expected-status)
                     (= pipeline-status expected-status))
          (error "Inconsistent command status: evaluator ~d, pipeline ~d, expected ~d."
                 status pipeline-status expected-status))
        (let ((failure
                (loop for stage in stages
                      for stage-status in stage-statuses
                      for stage-signal in stage-signals
                      for index from 0
                      when (and (not (zerop stage-status))
                                (or (= index (1- stage-count))
                                    *command-pipefail-p*)
                                (not (and (< index (1- stage-count))
                                          (eql stage-signal sb-unix:sigpipe))))
                        return (list stage stage-status stage-signal))))
          (if (and failure
                   (not *command-test-position-p*)
                   (or *errexit-p* (not *interactive-top-level-p*)))
              (destructuring-bind (stage failure-status failure-signal) failure
                (restart-case
                    (error 'command-failed
                           :command
                           (nshell.domain.parsing:command-node-command stage)
                           :status failure-status
                           :pipeline-status pipeline-status
                           :stage-statuses stage-statuses
                           :signal failure-signal)
                  (continue-command-failure ()
                    :report "Ignore and continue."
                    (values nil status))))
              (values value status))))))
)
