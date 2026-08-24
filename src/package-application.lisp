;;; nshell application package definitions -- see package.lisp for the split's rationale.

(eval-when (:compile-toplevel :load-toplevel :execute)
;; -- Application packages -----------------------------------
(defpackage #:nshell.application
  (:documentation
   "Application: the use cases. Owns the shell context -- the one mutable object
holding history, environment, aliases, functions, and the job monitor -- and
drives the domain over infrastructure through the function tables stored in it.
Executing a pipeline, running a builtin, and fg/bg/jobs/disown live here; this
is the only layer permitted to know both the domain and the ports.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct #:string-prefix-p)
  (:export #:*job-monitor* #:*shell-pgid* #:*foreground-job-pgid*
            #:make-shell-context #:shell-context-p
            #:shell-context-history #:shell-context-config
            #:shell-context-knowledge-base #:shell-context-environment
            #:shell-context-job-monitor
            #:shell-context-alias-table #:shell-context-abbreviation-table
            #:shell-context-function-table #:shell-context-function-source-table
            #:shell-context-filesystem-fns
            #:shell-context-process-fns #:shell-context-terminal-fns
            #:shell-context-redirect-fns
            #:shell-context-execution-strategy #:shell-context-pipefail-p
            #:shell-context-running
            #:shell-context-last-exit-code #:shell-context-input-state
            #:shell-context-job-processes #:shell-context-terminal-rows
            #:shell-context-terminal-cols
            #:lookup-builtin
            #:resolve-command-path
            #:collect-source-lines #:source-lines
            #:execute-command-line #:execute-pipeline-use-case #:execute-pipeline
            #:execute-command-node-in-context
            #:execute-ast-in-context
            #:execute-external
            #:expand-command-alias-node
            #:job-listing #:job-listing-p
            #:job-listing-id #:job-listing-status #:job-listing-command
            #:format-job-listing
            #:fg #:bg #:jobs #:disown #:wait-for-job
            #:history-suggestion #:search-history-use-case
            #:interactive-history-search-use-case))
)
