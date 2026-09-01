(in-package #:nshell.domain.parsing)

(defstruct (%token-reduction-state
             (:constructor %make-token-reduction-state
                 (&key (all-cmds '())
                       (current-args '())
                       current-cmd
                       current-cmd-token
                       current-cmd-fragments
                       last-word-token
                       pending-redirect-token
                       pending-sep
                       pending-sep-token
                       (errors '())))
             (:copier nil))
  (all-cmds '() :type list)
  (current-args '() :type list)
  current-cmd
  current-cmd-token
  current-cmd-fragments
  last-word-token
  pending-redirect-token
  pending-sep
  pending-sep-token
  (errors '() :type list))

(defstruct (%token-reduction-result
             (:constructor %make-token-reduction-result (commands errors))
             (:copier nil))
  (commands '() :type list)
  (errors '() :type list))

(defstruct (%token-reduction-argument
            (:constructor %make-token-reduction-argument
                (value quote-style syntactic-p fragments))
            (:copier nil))
  (value "" :type string :read-only t)
  (quote-style nil :read-only t)
  (syntactic-p nil :type boolean :read-only t)
  (fragments nil :type list :read-only t))

(defstruct (%token-reduction-diagnostic-policy
            (:constructor %make-token-reduction-diagnostic-policy
                (kind message))
            (:copier nil))
  (kind nil :type keyword :read-only t)
  (message "" :type string :read-only t))
