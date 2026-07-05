;;; Shell context - dependency container for the running shell.
;;;
;;; This struct is intentionally a simple composition data object.  The
;;; composition root builds it from infrastructure and domain services; callers
;;; receive the context instead of constructing dependencies themselves.
(in-package #:nshell.application)

(defstruct (shell-context
            (:constructor %allocate-shell-context
                (&key history config knowledge-base environment dispatcher
                      job-monitor alias-table abbreviation-table function-table
                      function-source-table filesystem-fns process-fns terminal-fns
                      signal-fns redirect-fns history-fns git-fns
                      execution-strategy running last-exit-code input-state
                      process-registry terminal-rows terminal-cols))
            (:copier nil))
  "Dependency container for one nshell session."
  (history nil)
  (config nil)
  (knowledge-base nil)
  (environment nil)
  (dispatcher nil)
  (job-monitor nil)
  (alias-table (make-hash-table :test #'equal) :type hash-table)
  (abbreviation-table (make-hash-table :test #'equal) :type hash-table)
  (function-table (make-hash-table :test #'equal) :type hash-table)
  (function-source-table (make-hash-table :test #'equal) :type hash-table)
  (filesystem-fns nil :type list)
  (process-fns nil :type list)
  (terminal-fns nil :type list)
  (signal-fns nil :type list)
  (redirect-fns nil :type list)
  (history-fns nil :type list)
  (git-fns nil :type list)
  (execution-strategy :cps :type (member :cps :os-pipes))
  (running nil :type boolean)
  (last-exit-code 0 :type integer)
  (input-state nil)
  (process-registry (make-hash-table :test #'eql) :type hash-table)
  (terminal-rows 24 :type integer)
  (terminal-cols 80 :type integer))

(defun %shell-context-hash-table (value)
  (check-type value hash-table)
  value)

(defun %shell-context-adapter-list (value)
  (check-type value list)
  value)

(defun make-shell-context (&key
                             history
                             config
                             knowledge-base
                             environment
                             dispatcher
                             job-monitor
                             (alias-table (make-hash-table :test #'equal))
                             (abbreviation-table (make-hash-table :test #'equal))
                             (function-table (make-hash-table :test #'equal))
                             (function-source-table (make-hash-table :test #'equal))
                             filesystem-fns
                             process-fns
                             terminal-fns
                             signal-fns
                             redirect-fns
                             history-fns
                             git-fns
                             (execution-strategy :cps)
                             (running nil)
                             (last-exit-code 0)
                             input-state
                             (process-registry (make-hash-table :test #'eql))
                             (terminal-rows 24)
                             (terminal-cols 80))
  "Build the application shell context through the composition boundary."
  (check-type execution-strategy (member :cps :os-pipes))
  (check-type running boolean)
  (check-type last-exit-code integer)
  (check-type terminal-rows (integer 1 *))
  (check-type terminal-cols (integer 1 *))
  (%allocate-shell-context
   :history history
   :config config
   :knowledge-base knowledge-base
   :environment environment
   :dispatcher dispatcher
   :job-monitor job-monitor
   :alias-table (%shell-context-hash-table alias-table)
   :abbreviation-table (%shell-context-hash-table abbreviation-table)
   :function-table (%shell-context-hash-table function-table)
   :function-source-table (%shell-context-hash-table function-source-table)
   :filesystem-fns (%shell-context-adapter-list filesystem-fns)
   :process-fns (%shell-context-adapter-list process-fns)
   :terminal-fns (%shell-context-adapter-list terminal-fns)
   :signal-fns (%shell-context-adapter-list signal-fns)
   :redirect-fns (%shell-context-adapter-list redirect-fns)
   :history-fns (%shell-context-adapter-list history-fns)
   :git-fns (%shell-context-adapter-list git-fns)
   :execution-strategy execution-strategy
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

(defmethod nshell.domain.completion:completion-filesystem-fns ((context shell-context))
  "Return filesystem adapter functions used by domain completion."
  (shell-context-filesystem-fns context))
