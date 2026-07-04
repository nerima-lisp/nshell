;;; Shell context - dependency container for the running shell.
;;;
;;; This struct is intentionally a simple composition data object.  The
;;; composition root builds it from infrastructure and domain services; callers
;;; receive the context instead of constructing dependencies themselves.
(in-package #:nshell.application)

(defstruct shell-context
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

(defun %store-shell-function-definition (context name body-lines source-path)
  (setf (gethash name (shell-context-function-table context)) body-lines)
  (if source-path
      (setf (gethash name (shell-context-function-source-table context))
            source-path)
      (remhash name (shell-context-function-source-table context)))
  body-lines)

(defun %store-shell-process-registry-entry (context job-id processes)
  (setf (gethash job-id (shell-context-process-registry context)) processes)
  processes)

(defmethod nshell.domain.completion:completion-filesystem-fns ((context shell-context))
  "Return filesystem adapter functions used by domain completion."
  (shell-context-filesystem-fns context))
