;;; Data definitions for session-level input transitions.

(in-package #:nshell.presentation)

(defparameter +completion-session-preserving-key-event-types+
  '(:tab :shift-tab :ctrl-l))

(defparameter +completion-session-resetting-key-event-types+
  '(:escape :ctrl-g :ctrl-c))

(defparameter +yank-session-preserving-key-event-types+
  '(:ctrl-y :alt-y))

(defparameter +argument-session-preserving-key-event-types+
  '(:alt-dot))

(define-value-struct %input-session-transition-policy
    ((preserve-all-p nil :type boolean)
     (preserve-completion-p nil :type boolean)
     (preserve-yank-session-p nil :type boolean)
     (preserve-argument-session-p nil :type boolean))
  :keyword-constructor t)

(define-value-struct %input-session-reduction
    ((state nil)
     (output :none :type symbol)))

(defstruct (%transient-session-clear
            (:constructor %make-transient-session-clear (kind overrides))
            (:conc-name %transient-session-clear-))
  kind
  overrides)
