(in-package #:nshell.domain.parsing)

(defstruct (%separator-facts
            (:constructor %make-separator-facts
                (kind token-type text continues-p)))
  kind
  token-type
  text
  continues-p)

(defstruct (%separator-rule-entry
            (:constructor %make-separator-rule-entry
                (kind token-type text continues-p)))
  kind
  token-type
  text
  continues-p)

(defparameter +separator-rules+
  (list (%make-separator-rule-entry :pipe :pipe "|" t)
        (%make-separator-rule-entry :and :and "&&" t)
        (%make-separator-rule-entry :or :or "||" t)
        (%make-separator-rule-entry :semi :semicolon ";" nil)
        (%make-separator-rule-entry :semi :newline "newline" nil)
        (%make-separator-rule-entry :amp :ampersand "&" nil)))

(defstruct (%reduced-command-entry
            (:constructor %make-reduced-command-entry
                (command separator separator-token)))
  (command nil :read-only t)
  (separator nil :read-only t)
  (separator-token nil :read-only t))
