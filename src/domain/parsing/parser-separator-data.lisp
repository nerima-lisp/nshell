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

(defun %separator-rule (separator)
  (find separator +separator-rules+
        :key #'%separator-rule-entry-kind
        :test #'eq))

(defun %separator-rule-entry (separator)
  (or (%separator-rule separator)
      (and separator
           (%make-separator-rule-entry
            separator
            nil
            (string-downcase (symbol-name separator))
            nil))))

(defun %separator-rule-entry-from-token-type (token-type)
  (when token-type
    (loop for entry in +separator-rules+
          when (eq token-type (%separator-rule-entry-token-type entry))
            return entry)))

(defun %separator-from-token-type (token-type)
  (let ((entry (%separator-rule-entry-from-token-type token-type)))
    (and entry
         (%separator-rule-entry-kind entry))))

(defun %separator-facts (separator)
  (let ((entry (%separator-rule-entry separator)))
    (and entry
         (%make-separator-facts
          (%separator-rule-entry-kind entry)
          (%separator-rule-entry-token-type entry)
          (%separator-rule-entry-text entry)
          (%separator-rule-entry-continues-p entry)))))

(defun %continuation-separator-p (separator)
  (let ((facts (%separator-facts separator)))
    (and facts
         (%separator-facts-continues-p facts))))

(defun %separator-text (separator)
  (let ((facts (%separator-facts separator)))
    (and facts
         (%separator-facts-text facts))))

(defstruct (%reduced-command-entry
            (:constructor %make-reduced-command-entry
                (command separator separator-token)))
  (command nil :read-only t)
  (separator nil :read-only t)
  (separator-token nil :read-only t))

(defun %reduced-command-entry-from-reducer-entry (entry)
  (destructuring-bind (command separator separator-token) entry
    (%make-reduced-command-entry command separator separator-token)))

(defun %reduced-command-entries-from-reducer-entries (entries)
  (mapcar #'%reduced-command-entry-from-reducer-entry entries))
