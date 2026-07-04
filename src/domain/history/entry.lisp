(in-package #:nshell.domain.history)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export '(history-entry
            history-entry-p
            history-entry-text
            history-entry-timestamp
            history-entry-exit-code
            history-entry-texts
            entry-equal-p)))

;;; HistoryEntry - immutable value object
(defstruct (history-entry (:constructor %make-history-entry
                             (text &optional (timestamp (get-universal-time)) exit-code)))
  "A single command history entry.
TEXT is the command text.
TIMESTAMP is the universal time when entered.
EXIT-CODE is the exit code (nil if not yet executed)."
  (text "" :type string :read-only t)
  (timestamp (get-universal-time) :type integer :read-only t)
  (exit-code nil :type (or null integer) :read-only t))

(defun make-history-entry (text &optional (timestamp (get-universal-time)) exit-code)
  (%make-history-entry text timestamp exit-code))

(defun entry-text (entry)
  "Return the command text for ENTRY."
  (history-entry-text entry))

(defun history-entry-texts (entries)
  "Return the command texts for ENTRIES."
  (mapcar #'entry-text entries))

(defun entry-timestamp (entry)
  "Return the universal-time timestamp for ENTRY."
  (history-entry-timestamp entry))

(defun entry-exit-code (entry)
  "Return the exit code for ENTRY, or NIL if unknown."
  (history-entry-exit-code entry))

(defun entry-equal-p (a b)
  "Compare two history entries by text (same command text = same entry)."
  (string= (history-entry-text a) (history-entry-text b)))
