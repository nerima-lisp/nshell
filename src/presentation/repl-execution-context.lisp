(in-package #:nshell.presentation)

(defparameter +repl-filesystem-fns+
  (list :cwd #'host-kit:getcwd
        :list-dir (lambda (dir) (host-kit:directory-files dir))
        :chdir #'host-kit:chdir
        :stat #'probe-file
        :file-exists-p (lambda (path)
                         (let ((pathname (probe-file path)))
                           (and pathname
                                (not (host-kit:directory-pathname-p pathname)))))
        :directory-exists-p (lambda (path)
                              (not (null (host-kit:directory-exists-p path))))))

(defparameter +repl-process-fns+
  (list :run-external
        (lambda (command args)
          (nshell.infrastructure.acl:run-external command args))
        :run-external-capture
        (lambda (command args)
          (nshell.infrastructure.acl:run-external-capture command args))))

(defparameter +repl-redirect-fns+
  (list :redirect-output #'nshell.infrastructure.acl:redirect-output
        :redirect-error #'nshell.infrastructure.acl:redirect-error
        :redirect-output-error #'nshell.infrastructure.acl:redirect-output-and-error
        :redirect-output-to-error #'nshell.infrastructure.acl:redirect-output-to-error
        :redirect-error-to-output #'nshell.infrastructure.acl:redirect-error-to-output
        :redirect-input #'nshell.infrastructure.acl:redirect-input
        :redirect-input-document #'nshell.infrastructure.acl:redirect-input-document
        :redirect-input-string #'nshell.infrastructure.acl:redirect-input-string
        :restore #'nshell.infrastructure.acl:restore-redirects))

(defun %make-repl-shell-context ()
  (nshell.application:make-shell-context
   :history *history*
   :config *config*
   :knowledge-base *kb*
   :environment (ensure-environment)
   :dispatcher nil
   :job-monitor nshell.application:*job-monitor*
   :alias-table *aliases*
   :abbreviation-table *abbreviations*
   :function-table *functions*
   :function-source-table *function-sources*
   :filesystem-fns +repl-filesystem-fns+
   :process-fns +repl-process-fns+
   :redirect-fns +repl-redirect-fns+
   :terminal-fns nil
   :running *running*
   :pipefail-p *pipefail*
   :last-exit-code *last-exit-code*
   :input-state *input-state*
   :process-registry *proc-registry*))

(defun %repl-external-command-available-p (command)
  (multiple-value-bind (kind path)
      (nshell.application:resolve-command-path
       (%make-repl-shell-context) command)
    (and (eq kind :path) path)))

(defun %sync-repl-shell-context (context code)
  (setf *environment* (nshell.application:shell-context-environment context)
        *aliases* (nshell.application:shell-context-alias-table context)
        *abbreviations* (nshell.application:shell-context-abbreviation-table context)
        *functions* (nshell.application:shell-context-function-table context)
        *function-sources* (nshell.application:shell-context-function-source-table context)
        *running* (nshell.application:shell-context-running context)
        *pipefail* (nshell.application:shell-context-pipefail-p context)
        *last-exit-code* code
        *input-state* (nshell.application:shell-context-input-state context))
  code)

(defun %execute-with-repl-shell-context (thunk)
  (let ((context (%make-repl-shell-context)))
    (multiple-value-bind (output code)
        (funcall thunk context)
      (%sync-repl-shell-context context (or code 0))
      (when output
        (write-string output))
      (values output (or code 0)))))
