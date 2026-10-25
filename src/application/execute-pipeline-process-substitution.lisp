(in-package #:nshell.application)

(defun %reader-process-substitution-preflight-error (source-span message)
  (error 'command-execution-plan-error
         :source-span source-span
         :operation :preflight
         :cause (make-condition 'simple-error
                                :format-control "~a"
                                :format-arguments (list message))))

(defun %reader-command-has-nested-process-substitution-p (command-node)
  (some (lambda (entry)
          (and (nshell.domain.parsing:ast-redirect-entry-p entry)
               (nshell.domain.parsing:redirect-procsub-target-p
                (nshell.domain.parsing:ast-redirect-entry-target entry))))
        (nshell.domain.parsing:command-node-redirects command-node)))

(defun %preflight-reader-process-substitution-entry (entry)
  (unless (nshell.domain.parsing:ast-redirect-entry-p entry)
    (%reader-process-substitution-preflight-error
     nil "process substitution requires a redirect entry"))
  (let* ((source-span
           (nshell.domain.parsing:ast-redirect-entry-source-span entry))
         (kind (nshell.domain.parsing:ast-redirect-entry-kind entry))
         (target (nshell.domain.parsing:ast-redirect-entry-target entry)))
    (unless (nshell.domain.parsing:redirect-procsub-target-p target)
      (%reader-process-substitution-preflight-error
       source-span "process substitution redirect has an invalid target"))
    (let* ((expected-direction
             (case kind
               ((:input-file :process-substitution-input) :input)
               ((:output-file :process-substitution-output) :output)
               (otherwise nil)))
           (direction
             (nshell.domain.parsing:redirect-procsub-target-direction target)))
      (unless expected-direction
        (%reader-process-substitution-preflight-error
         source-span "process substitution requires an input or output redirect"))
      (unless (eq expected-direction direction)
        (%reader-process-substitution-preflight-error
         source-span "process substitution direction does not match its redirect"))
      (let* ((form (nshell.domain.parsing:redirect-procsub-target-form target))
             (commands
               (cond
                 ((nshell.domain.parsing:command-node-p form)
                  (list form))
                 ((nshell.domain.parsing:pipeline-node-p form)
                  (nshell.domain.parsing:pipeline-node-commands form))
                 (t nil))))
        (unless (and (consp commands)
                     (every #'nshell.domain.parsing:command-node-p commands))
          (%reader-process-substitution-preflight-error
           source-span "process substitution form must be a command or pipeline"))
        (when (some #'%reader-command-has-nested-process-substitution-p commands)
          (%reader-process-substitution-preflight-error
           source-span "nested process substitutions are not supported"))
        commands))))
