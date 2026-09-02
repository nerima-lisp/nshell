;;; Redirect-splitting engine: separates redirect operators/targets out of a
;;; COMMAND-NODE's args into a typed COMMAND-REDIRECT-SPLIT-RESULT.
(in-package #:nshell.domain.parsing)

(declaim (notinline %redirect-facts-kind
                    %redirect-facts-fd-dup-p
                    %redirect-facts-fd-dup-target))

(define-value-struct command-redirect-split-result
    ((clean-command nil)
     (redirects nil :type list)))

(define-value-struct command-list-redirect-split-result
    ((clean-commands nil :type list)
     (redirects nil :type list)))

(defstruct (%command-redirect-split-state
            (:constructor %make-command-redirect-split-state (clean redirects)))
  (clean nil :type list :read-only t)
  (redirects nil :type list :read-only t))

(defun %empty-command-redirect-split-state ()
  (%make-command-redirect-split-state nil nil))

(defun %command-redirect-split-state-push-clean (state arg)
  (%make-command-redirect-split-state
   (cons arg (%command-redirect-split-state-clean state))
   (%command-redirect-split-state-redirects state)))

(defun %command-redirect-split-state-push-redirect (state kind target)
  (%make-command-redirect-split-state
   (%command-redirect-split-state-clean state)
   (cons (cons kind target)
         (%command-redirect-split-state-redirects state))))

(defstruct (%command-redirect-arg-cursor
            (:constructor %make-command-redirect-arg-cursor
                (arg remaining-args)))
  (arg nil :read-only t)
  (remaining-args nil :type list :read-only t))

(defun %command-redirect-arg-cursor-from-args (args)
  (when args
    (%make-command-redirect-arg-cursor (first args) (rest args))))

(defun %command-redirect-arg-cursor-after-current (cursor)
  (%command-redirect-arg-cursor-from-args
   (%command-redirect-arg-cursor-remaining-args cursor)))

(defun %command-redirect-arg-cursor-target-arg (cursor)
  (first (%command-redirect-arg-cursor-remaining-args cursor)))

(defun %command-redirect-arg-cursor-after-target (cursor)
  (%command-redirect-arg-cursor-from-args
   (rest (%command-redirect-arg-cursor-remaining-args cursor))))

(defstruct (%command-redirect-split-step
            (:constructor %make-command-redirect-split-step
                (state cursor)))
  (state nil :read-only t)
  (cursor nil :read-only t))

(defun %command-redirect-split-state-accept-cursor (state cursor)
  (let* ((arg (%command-redirect-arg-cursor-arg cursor))
         (value (arg-value arg))
         (redirect-facts (%redirect-facts value)))
    (cond
      ((and redirect-facts
            (%redirect-facts-fd-dup-p redirect-facts))
       (%make-command-redirect-split-step
        (%command-redirect-split-state-push-redirect
         state
         (%redirect-facts-kind redirect-facts)
         (%redirect-facts-fd-dup-target redirect-facts))
        (%command-redirect-arg-cursor-after-current cursor)))
      ((and redirect-facts
            (%command-redirect-arg-cursor-remaining-args cursor))
       (%make-command-redirect-split-step
        (%command-redirect-split-state-push-redirect
         state
         (%redirect-facts-kind redirect-facts)
         (arg-value (%command-redirect-arg-cursor-target-arg cursor)))
        (%command-redirect-arg-cursor-after-target cursor)))
      (t
       (%make-command-redirect-split-step
        (%command-redirect-split-state-push-clean state arg)
        (%command-redirect-arg-cursor-after-current cursor))))))

(defun %command-redirect-split-result-from-state (cmd-node state)
  (%make-command-redirect-split-result
   (make-command-node
    (command-node-command cmd-node)
    (nreverse (%command-redirect-split-state-clean state))
    (ast-node-span cmd-node)
    (command-node-command-quote-style cmd-node)
    (command-node-command-fragments cmd-node))
   (nreverse (%command-redirect-split-state-redirects state))))

(defun split-command-node-redirects (cmd-node)
  "Split CMD-NODE into a COMMAND-REDIRECT-SPLIT-RESULT.
Redirect operator args and their targets are removed from the clean command."
  (let ((state (%empty-command-redirect-split-state))
        (cursor (%command-redirect-arg-cursor-from-args
                 (command-node-args cmd-node))))
    (loop while cursor
          do (let ((step (%command-redirect-split-state-accept-cursor
                          state
                          cursor)))
               (setf state (%command-redirect-split-step-state step)
                     cursor (%command-redirect-split-step-cursor step))))
    (%command-redirect-split-result-from-state cmd-node state)))

(defstruct (%command-list-redirect-split-state
            (:constructor %make-command-list-redirect-split-state
                (clean-commands redirects)))
  (clean-commands nil :type list :read-only t)
  (redirects nil :type list :read-only t))

(defun %empty-command-list-redirect-split-state ()
  (%make-command-list-redirect-split-state nil nil))

(defun %command-list-redirect-split-state-push (state clean-command command-redirects)
  (%make-command-list-redirect-split-state
   (cons clean-command
         (%command-list-redirect-split-state-clean-commands state))
   (cons command-redirects
         (%command-list-redirect-split-state-redirects state))))

(defun %command-list-redirect-split-state-accept-command (state command)
  (let ((result (split-command-node-redirects command)))
    (%command-list-redirect-split-state-push
     state
     (command-redirect-split-result-clean-command result)
     (command-redirect-split-result-redirects result))))

(defun %command-list-redirect-split-result-from-state (state)
  (%make-command-list-redirect-split-result
   (nreverse (%command-list-redirect-split-state-clean-commands state))
   (nreverse (%command-list-redirect-split-state-redirects state))))

(defun split-command-nodes-redirects (commands)
  "Split COMMANDS into a COMMAND-LIST-REDIRECT-SPLIT-RESULT."
  (let ((state (%empty-command-list-redirect-split-state)))
    (dolist (command commands)
      (setf state
            (%command-list-redirect-split-state-accept-command state command)))
    (%command-list-redirect-split-result-from-state state)))
