(in-package #:nshell.application)

(defun %complete-ensure-knowledge-base (context)
  "Return CONTEXT's completion knowledge base, lazily creating one when the
session has none -- batch mode (`nshell -c ...`) never seeds *KB*, so without
this `complete -c ...` would call KB-ADD-COMMAND/KB-REMOVE-COMMAND on NIL and
crash instead of registering the completion, the same class of non-interactive
gap as the NIL history in builtin-commands-history.lisp."
  (or (shell-context-knowledge-base context)
      (setf (shell-context-knowledge-base context)
            (nshell.domain.completion:make-empty-knowledge-base))))

(defun %complete-do-complete (context line)
  "Print each completion candidate for LINE on its own line (fish's `complete
-C`, the scriptable completion entry point). A NIL knowledge base falls back
to PATH/filesystem candidates rather than crashing -- see the TYPECASE in
%COMPLETION-CANDIDATES (candidate-routing.lisp) -- so no lazy KB creation is
needed here the way the mutating `-c`/`-e` paths below need one."
  (let* ((environment (shell-context-environment context))
         (path (and environment (nshell.domain.environment:env-get environment "PATH")))
         (variable-names
           (when environment
             (mapcar (lambda (binding)
                       (cons (nshell.domain.environment:env-binding-name binding)
                             (nshell.domain.environment:env-binding-value binding)))
                     (nshell.domain.environment:env-bindings environment))))
         (directory (nshell.infrastructure.acl:current-working-directory))
         (home-directory
           (and environment (nshell.domain.environment:env-get environment "HOME")))
         (process-ids nil)
         (registry (shell-context-process-registry context))
         (candidates
           (progn
             (when (hash-table-p registry)
               (maphash
                (lambda (job-id processes)
                  (declare (ignore job-id))
                  (dolist (process (if (listp processes) processes (list processes)))
                    (let ((pid (ignore-errors
                                 (nshell.infrastructure.acl:process-pid process))))
                      (when (and (integerp pid) (plusp pid))
                        (push (princ-to-string pid) process-ids)))))
                registry))
             (nshell.domain.completion:complete
              (shell-context-knowledge-base context)
              line
              :path path
              :filesystem (shell-context-filesystem context)
              :alias-table (shell-context-alias-table context)
              :function-table (shell-context-function-table context)
              :variable-names variable-names
              :directory directory
              :home-directory home-directory
              :process-ids (remove-duplicates process-ids :test #'string=)))))
    (values (when candidates
              (format nil "~{~a~%}"
                      (mapcar #'nshell.domain.completion:candidate-text candidates)))
            0)))


(defun %complete-upsert-command (kb command flags long-options short-options arguments description)
  (let* ((option-flags (append long-options short-options))
         (generic-arguments (and (null option-flags) arguments))
         (option-values
           (loop for option in option-flags
                 collect (cons option arguments)))
         (option-descriptions
           (when description
             (loop for option in (append flags option-flags)
                   collect (list option description)))))
    (nshell.domain.completion:kb-add-command
     kb command
     :subcommands generic-arguments
     :flags (append flags option-flags)
     :option-values option-values
     :option-descriptions option-descriptions
     :description description)))

(defun %builtin-complete (context args)
  (if (and args (member (first args) '("-C" "--do-complete") :test #'string=))
      (if (rest args)
          (%complete-do-complete context (second args))
          (values (%required-argument-error "complete" (first args) "a line") 2))
      (multiple-value-bind
            (command flags long-options short-options arguments description erase error)
          (%parse-complete-args args)
        (cond
          (error
           (values error 2))
          ((null command)
           (%builtin-usage
            "complete"
            ;; Assembled rather than written as one literal: the synopsis is longer
            ;; than 100 columns and a string cannot be split across source lines.
            (concatenate 'string
                         "complete -c command [-f flag ...] [-l option ...]"
                         " [-s option ...] [-a arguments] [-d description] [-e]"
                         " | complete -C line")))
          (erase
           (nshell.domain.completion:kb-remove-command
            (%complete-ensure-knowledge-base context)
            command)
           (values nil 0))
          (t
           (%complete-upsert-command (%complete-ensure-knowledge-base context)
                                     command
                                     flags
                                     long-options
                                     short-options
                                     arguments
                                     description)
           (values nil 0))))))
