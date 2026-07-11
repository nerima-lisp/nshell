(in-package #:nshell.presentation)

;; Trampoline
(defun trampoline (thunk)
  "Run THUNK and repeatedly invoke each returned continuation until NIL."
  (loop for continuation = (funcall thunk)
        then (funcall continuation)
        while continuation))

;; REPL State
(defun %make-repl-name-table ()
  (make-hash-table :test #'equal))

(defun %make-repl-process-registry ()
  (make-hash-table :test #'eql))

(defun %make-repl-state-tables ()
  (values (%make-repl-name-table)
          (%make-repl-name-table)
          (%make-repl-name-table)
          (%make-repl-name-table)
          (%make-repl-process-registry)))

(defvar *running* nil)
(defvar *last-exit-code* 0)
(defvar *last-command-duration-ms* nil)
(defvar *history* nil)
(defvar *config* nil)
(defvar *kb* nil)
(defvar *input-state* nil)
(defvar *completion-rendered-lines* 0)
(defvar *prompt-rendered-lines* 0)
(defvar *prompt-rendered-cursor-row* 0)
(defvar *environment* nil)
(defvar *aliases* (%make-repl-name-table))
(defvar *abbreviations* (%make-repl-name-table))
(defvar *functions* (%make-repl-name-table))
(defvar *function-sources* (%make-repl-name-table))
(defvar *proc-registry* (%make-repl-process-registry)
  "Maps job-id -> SBCL process object or process list for status checking.")
(defvar *completion-help-cache* (make-hash-table :test #'equal))

(defun %reset-repl-state-tables ()
  (multiple-value-setq (*aliases*
                        *abbreviations*
                        *functions*
                        *function-sources*
                        *proc-registry*)
    (%make-repl-state-tables))
  (clrhash *completion-help-cache*)
  (values))

(defmacro with-fresh-repl-state-tables (&body body)
  `(multiple-value-bind (*aliases*
                         *abbreviations*
                         *functions*
                         *function-sources*
                         *proc-registry*)
       (%make-repl-state-tables)
     (let ((*completion-help-cache* (make-hash-table :test #'equal)))
       ,@body)))
