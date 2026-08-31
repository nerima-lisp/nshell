;;; Shell context - dependency container for the running shell.
;;;
;;; This struct is intentionally a simple composition data object.  The
;;; composition root builds it from infrastructure and domain services; callers
;;; receive the context instead of constructing dependencies themselves.
(in-package #:nshell.application)

(defstruct (shell-context
            (:constructor %allocate-shell-context
                (&key history config knowledge-base environment filesystem
                      job-monitor alias-table abbreviation-table function-table
                      function-source-table execution-strategy pipefail-p running last-exit-code input-state
                      process-registry terminal-rows terminal-cols))
            (:copier nil))
  "Dependency container for one nshell session."
  (history)
  (config)
  (knowledge-base)
  (environment)
  (filesystem)
  (job-monitor)
  (alias-table nil :type hash-table)
  (abbreviation-table nil :type hash-table)
  (function-table nil :type hash-table)
  (function-source-table nil :type hash-table)
  (execution-strategy nil :type (member :cps :os-pipes))
  (pipefail-p nil :type boolean)
  (running nil :type boolean)
  (last-exit-code nil :type integer)
  (input-state)
  (process-registry nil :type hash-table)
  (terminal-rows nil :type integer)
  (terminal-cols nil :type integer))

(defun %shell-context-hash-table (value)
  (check-type value hash-table)
  value)

(defun make-shell-context (&key
                             history
                             config
                             knowledge-base
                             environment
                             filesystem
                             job-monitor
                             (alias-table (make-hash-table :test #'equal))
                             (abbreviation-table (make-hash-table :test #'equal))
                             (function-table (make-hash-table :test #'equal))
                             (function-source-table (make-hash-table :test #'equal))
                             (execution-strategy :cps)
                             (pipefail-p nil)
                             (running nil)
                             (last-exit-code 0)
                             input-state
                             (process-registry (make-hash-table :test #'eql))
                             (terminal-rows 24)
                             (terminal-cols 80))
  "Build the application shell context through the composition boundary."
  (check-type execution-strategy (member :cps :os-pipes))
  (check-type pipefail-p boolean)
  (check-type running boolean)
  (check-type last-exit-code integer)
  (check-type terminal-rows (integer 1 *))
  (check-type terminal-cols (integer 1 *))
  (%allocate-shell-context
   :history history
   :config config
   :knowledge-base knowledge-base
   :environment environment
   :filesystem filesystem
   :job-monitor job-monitor
   :alias-table (%shell-context-hash-table alias-table)
   :abbreviation-table (%shell-context-hash-table abbreviation-table)
   :function-table (%shell-context-hash-table function-table)
   :function-source-table (%shell-context-hash-table function-source-table)
   :execution-strategy execution-strategy
   :pipefail-p pipefail-p
   :running running
   :last-exit-code last-exit-code
   :input-state input-state
   :process-registry (%shell-context-hash-table process-registry)
   :terminal-rows terminal-rows
   :terminal-cols terminal-cols))

(defun %store-shell-function-definition (context name body-lines source-path)
  (setf (gethash name (shell-context-function-table context)) body-lines)
  (if source-path
      (setf (gethash name (shell-context-function-source-table context))
            source-path)
      (remhash name (shell-context-function-source-table context)))
  body-lines)

(defun %remove-shell-function-definition (context name)
  (remhash name (shell-context-function-table context))
  (remhash name (shell-context-function-source-table context))
  context)

(defun %store-shell-process-registry-entry (context job-id processes)
  (setf (gethash job-id (shell-context-process-registry context)) processes)
  processes)

(defun shell-context-job-processes (context job-id)
  "Return registered process objects for JOB-ID in CONTEXT."
  (gethash job-id (shell-context-process-registry context)))

(defun %stop-shell-context (context)
  (setf (shell-context-running context) nil)
  context)
