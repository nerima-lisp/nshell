
(in-package #:nshell.application)

(defvar *pipeline-stage-environments* nil
  "NIL, or one exported-environment string list per pipeline stage, in source
order. Bound while a pipeline whose stages carry their own prefix assignments
spawns, so a stage's assignment reaches that stage's process alone.")


;; -- Internal vs external dispatch -------------------------------------------

(defun %shell-internal-command-p (context command-node)
  (let ((command (nshell.domain.parsing:command-node-command command-node)))
    (or (lookup-builtin command)
        (nth-value 1 (gethash command (shell-context-function-table context))))))

(defun %source-pipeline-required-p (context commands)
  "Return true when COMMANDS must use the source/CPS execution path."
  (or (eq :cps (shell-context-execution-strategy context))
      (not (null
            (some (lambda (command)
                    (%shell-internal-command-p context command))
                  commands)))))

;; -- Clean command node execution --------------------------------------------

(defun %execute-clean-command-node-in-context (context clean-command redirects)
  (let* ((command (nshell.domain.parsing:command-node-command clean-command))
         (args (%line-command-args clean-command))
         (redirect-output-p (nshell.domain.parsing:redirect-output-p redirects))
         (*foreground-terminal-runner* (and (null redirects)
                                           *foreground-terminal-runner*)))
    (unwind-protect
         (let ((redirect-error
                 (when redirects
                   (handler-case
                       (progn
                         (%apply-context-redirects context redirects)
                         nil)
                     (error (condition)
                       condition)))))
           (if redirect-error
               (progn
                 (format *error-output* "nshell: ~a: ~a~%"
                         command redirect-error)
                 (values nil 1))
               (multiple-value-bind (output code)
                   (%execute-command-by-name-in-context context command args)
                 (when (and redirect-output-p output)
                   (write-string output))
                 (values (and (not redirect-output-p) output) code))))
      (when redirects
        (%restore-context-redirects context)))))

(defun %execute-os-pipeline-with-process-substitutions
    (clean-commands redirects resources &optional (pipefail-p nil))
  (let ((spawned-p nil))
    (unwind-protect
         (handler-case
             (let ((exit-code 0)
                   (pipeline-statuses nil))
               (values
                (with-output-to-string (*standard-output*)
                  (multiple-value-bind (status statuses)
                      (nshell.infrastructure.acl:spawn-pipeline
                       clean-commands
                       :redirects redirects
                       :pipefail-p pipefail-p
                       :preserve-fds
                       (%process-substitution-resource-fds resources)
                       :after-spawn
                       (lambda ()
                         (setf spawned-p t)
                         (%release-process-substitution-resources
                          resources)))
                    (setf exit-code (or status 0)
                          pipeline-statuses (or statuses
                                                (list exit-code)))))
                exit-code
                pipeline-statuses))
           (error (condition)
             (values (format nil "nshell: ~a~%" condition) 127 (list 127))))
      (if spawned-p
          (%finish-process-substitution-resources resources)
          (%abort-process-substitution-resources resources)))))

(defun %execute-plain-command-node-in-context (context command-node)
  (multiple-value-bind (expanded error resources)
      (%expand-command-node-in-context context command-node)
    (when error
      (%abort-process-substitution-resources resources)
      (return-from %execute-plain-command-node-in-context (values error 127)))
    (let* ((redirect-split (%extract-command-redirects expanded))
           (clean-command
             (nshell.domain.parsing:command-redirect-split-result-clean-command
              redirect-split))
           (redirects
             (nshell.domain.parsing:command-redirect-split-result-redirects
              redirect-split)))
      (if resources
          (if (%shell-internal-command-p context clean-command)
              (progn
                (%abort-process-substitution-resources resources)
                (values
                 (%process-substitution-error
                  "requires an external command")
                 127))
          (%execute-external-pipeline-stage
               clean-command nil redirects resources))
          (if (and (not (%shell-internal-command-p context clean-command))
                   (nshell.domain.parsing:redirects-require-shell-wrapper-p
                    redirects))
              (%execute-external-pipeline-stage
               clean-command nil redirects)
              (%execute-clean-command-node-in-context
               context clean-command redirects))))))

;; -- Pipeline node execution --------------------------------------------------

(defun %execute-plain-pipeline-node-in-context (context commands)
  (let ((terminal-runner *foreground-terminal-runner*)
        (*foreground-terminal-runner* nil))
    (multiple-value-bind (expanded-commands error resources)
        (%expand-command-nodes-in-context context commands)
      (when error
        (%abort-process-substitution-resources resources)
        (return-from %execute-plain-pipeline-node-in-context (values error 127)))
      (let* ((redirect-split (%extract-pipeline-redirects expanded-commands))
             (clean-commands
              (nshell.domain.parsing:command-list-redirect-split-result-clean-commands
               redirect-split))
             (redirects
              (nshell.domain.parsing:command-list-redirect-split-result-redirects
               redirect-split)))
        (if resources
            (if (%source-pipeline-required-p context clean-commands)
                (progn
                  (%abort-process-substitution-resources resources)
                  (values
                   (%process-substitution-error
                    "is not supported for internal or CPS pipelines")
                   127))
                (multiple-value-bind (output exit-code statuses)
                    (%execute-os-pipeline-with-process-substitutions
                     clean-commands redirects resources
                     (shell-context-pipefail-p context))
                  (%record-pipeline-statuses context statuses)
                  (values output exit-code)))
            (if (%source-pipeline-required-p context clean-commands)
                (%execute-source-pipeline-in-context
                 context clean-commands redirects)
                (if terminal-runner
                    (multiple-value-bind (output status statuses)
                        (funcall terminal-runner
                                 (lambda ()
                                   (%run-terminal-pipeline context clean-commands redirects)))
                      (%record-pipeline-statuses context statuses)
                      (values output status))
                    (let ((output nil)
                          (exit-code 0)
                          (pipeline-statuses nil))
                      (progn
                        (setf output
                              (with-output-to-string (*standard-output*)
                                (multiple-value-bind (status statuses)
                                    (nshell.infrastructure.acl:spawn-pipeline
                                     clean-commands
                                     :redirects redirects
                                     :stage-environments
                                     *pipeline-stage-environments*
                                     :pipefail-p
                                     (shell-context-pipefail-p context))
                                  (setf exit-code (or status 0)
                                        pipeline-statuses
                                        (or statuses (list exit-code))))))
                        (%record-pipeline-statuses context pipeline-statuses)
                        (values output exit-code))))))))))

;; -- Public pipeline API (OS-level) -------------------------------------------

(defun execute-pipeline (pipeline-ast &key filesystem)
  "Execute a pipeline AST using OS-level pipes. Returns the last process exit code."
  (let ((commands (if (nshell.domain.parsing:pipeline-node-p pipeline-ast)
                      (nshell.domain.parsing:pipeline-node-commands pipeline-ast)
                      (list pipeline-ast))))
    (let ((context (%make-pipeline-shell-context :filesystem filesystem)))
      (multiple-value-bind (expanded-commands error resources)
          (%expand-command-nodes-in-context context commands)
        (when error
          (%abort-process-substitution-resources resources)
          (write-string error *error-output*)
          (return-from execute-pipeline 127))
        (let* ((redirect-split (%extract-pipeline-redirects expanded-commands))
               (clean-commands
                 (nshell.domain.parsing:command-list-redirect-split-result-clean-commands
                  redirect-split))
               (redirects
                 (nshell.domain.parsing:command-list-redirect-split-result-redirects
                  redirect-split)))
          (if (and resources
                   (some (lambda (cmd) (%shell-internal-command-p context cmd))
                         clean-commands))
              (progn
                (%abort-process-substitution-resources resources)
                (write-string
                 (%process-substitution-error
                  "is not supported for internal commands")
                 *error-output*)
                127)
              (if resources
                  (nth-value
                   1
                   (%execute-os-pipeline-with-process-substitutions
                    clean-commands redirects resources
                    (shell-context-pipefail-p context)))
                  (nshell.infrastructure.acl:spawn-pipeline
                   clean-commands
                   :redirects redirects
                   :pipefail-p (shell-context-pipefail-p context)))))))))

(defun execute-pipeline-use-case (pipeline &key filesystem)
  (or (execute-pipeline pipeline :filesystem filesystem) 0))

;; -- Prefix assignments and the exported environment --------------------------
;;
;; `FOO=bar cmd` exports FOO for that one command; a bare `FOO=bar` sets the
;; shell variable. Child processes always read the context's exported
;; variables, so a script's `export` reaches the commands after it even when
;; no interactive session syncs the environment.

;; The ACL file holding this special is an ASDF component that loads after this
;; one, so name it as special here rather than compiling a free reference.
(declaim (special nshell.infrastructure.acl:*exported-environment*))

(defun %context-exported-environment-strings (context)
  (mapcar (lambda (entry)
            (format nil "~a=~a"
                    (nshell.domain.environment:env-entry-name entry)
                    (nshell.domain.environment:env-entry-value entry)))
          (nshell.domain.environment:env-list (shell-context-environment context))))

(defun %sync-context-exports (context)
  ;; A global rather than a dynamic binding: the foreground terminal runner
  ;; spawns the pipeline from another thread, which sees only global values.
  (setf nshell.infrastructure.acl:*exported-environment*
        (%context-exported-environment-strings context)))

(defmacro %with-context-exports ((context) &body body)
  `(progn
     (%sync-context-exports ,context)
     ,@body))

(defun %prefix-assignment-arg-p (arg)
  (and (null (nshell.domain.parsing:arg-quote-style arg))
       (nshell.domain.parsing:shell-assignment-word-p
        (nshell.domain.parsing:arg-value arg))))

(defun %assignment-word-binding (context word)
  (let* ((equals (position #\= word))
         (name (subseq word 0 equals))
         (fields (%expand-source-arg-in-context
                  context
                  (nshell.domain.parsing:make-command-arg (subseq word (1+ equals))))))
    (cons name (format nil "~{~a~^ ~}" fields))))

(defun %command-node-from-arg (arg rest-args span)
  (let ((typed (and (nshell.domain.parsing::command-arg-p arg) arg)))
    (nshell.domain.parsing:make-command-node
     (nshell.domain.parsing:arg-value arg)
     rest-args
     span
     (nshell.domain.parsing:arg-quote-style arg)
     (and typed (nshell.domain.parsing:command-arg-fragments typed)))))

(defun %split-prefix-assignments (context command-node)
  "Return (values ASSIGNMENTS NODE): the leading NAME=VALUE words of
COMMAND-NODE as (NAME . EXPANDED-VALUE) pairs, and the node that remains, or
NIL when the line was assignments only."
  (let ((command (nshell.domain.parsing:command-node-command command-node)))
    (if (or (nshell.domain.parsing:command-node-command-quote-style command-node)
            (not (nshell.domain.parsing:shell-assignment-word-p command)))
        (values nil command-node)
        (let ((assignments (list (%assignment-word-binding context command)))
              (args (nshell.domain.parsing:command-node-args command-node)))
          (loop while (and args (%prefix-assignment-arg-p (first args)))
                do (push (%assignment-word-binding context (nshell.domain.parsing:arg-value (pop args)))
                         assignments))
          (values (nreverse assignments)
                  (and args
                       (%command-node-from-arg (first args) (rest args)
                                               (nshell.domain.parsing::ast-node-span command-node))))))))

(defun %assign-shell-variables (context assignments)
  (dolist (assignment assignments (values nil 0))
    (let ((environment (shell-context-environment context)))
      (setf (shell-context-environment context)
            (nshell.domain.environment:env-set
             environment (car assignment) (cdr assignment)
             (nshell.domain.environment:env-exported-p environment (car assignment)))))))

(defun %call-with-prefix-assignments (context assignments thunk)
  (let ((saved (shell-context-environment context)))
    (setf (shell-context-environment context)
          (reduce (lambda (environment assignment)
                    (nshell.domain.environment:env-set
                     environment (car assignment) (cdr assignment) t))
                  assignments
                  :initial-value saved))
    (unwind-protect (funcall thunk)
      (setf (shell-context-environment context) saved)
      (%sync-context-exports context))))

(defun execute-command-node-in-context (context command-node)
  (multiple-value-bind (assignments node)
      (%split-prefix-assignments context command-node)
    (flet ((run ()
             (%with-context-exports (context)
               (%execute-plain-command-node-in-context context node))))
      (cond
        ((null assignments) (run))
        ((null node) (%assign-shell-variables context assignments))
        (t (%call-with-prefix-assignments context assignments #'run))))))

(defun %environment-with-assignments (environment assignments)
  (reduce (lambda (environment assignment)
            (nshell.domain.environment:env-set
             environment (car assignment) (cdr assignment) t))
          assignments
          :initial-value environment))

(defun %stage-environment-strings (context assignments)
  "The exported environment one pipeline stage sees: the session's exports plus
that stage's own prefix assignments, and nothing from a sibling stage."
  (when assignments
    (let ((saved (shell-context-environment context)))
      (unwind-protect
           (progn
             (setf (shell-context-environment context)
                   (%environment-with-assignments saved assignments))
             (%context-exported-environment-strings context))
        (setf (shell-context-environment context) saved)))))

(defun %split-pipeline-stages (context pipeline-node)
  "Return (values STAGES ASSIGNMENT-ONLY): the pipeline's stages as
(NODE . ASSIGNMENTS) pairs carrying each stage's own prefix assignments, plus
the assignments of any stage that named no command."
  (let ((stages '())
        (assignment-only '()))
    (dolist (command (nshell.domain.parsing:pipeline-node-commands pipeline-node))
      (multiple-value-bind (stage-assignments node)
          (%split-prefix-assignments context command)
        (if node
            (push (cons node stage-assignments) stages)
            (setf assignment-only (append assignment-only stage-assignments)))))
    (values (nreverse stages) assignment-only)))

(defun execute-pipeline-node-in-context (context pipeline-node)
  (multiple-value-bind (stages assignment-only)
      (%split-pipeline-stages context pipeline-node)
    (let* ((commands (mapcar #'car stages))
           (stage-assignments (mapcar #'cdr stages)))
      (when assignment-only
        (%assign-shell-variables context assignment-only))
      (flet ((run ()
               (%with-context-exports (context)
                 (%execute-plain-pipeline-node-in-context context commands))))
        (cond
          ((null commands) (values nil 0))
          ((notany #'identity stage-assignments) (run))
          ;; A builtin or function stage runs in this process, so its assignment
          ;; can only be scoped by the shared context environment; the OS path
          ;; takes each stage's own environment to its own spawn instead.
          ((%source-pipeline-required-p context commands)
           (%call-with-prefix-assignments
            context (apply #'append stage-assignments) #'run))
          (t
           (let ((*pipeline-stage-environments*
                   (mapcar (lambda (assignments)
                             (%stage-environment-strings context assignments))
                           stage-assignments)))
             (run))))))))
