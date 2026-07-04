(in-package #:nshell.domain.events)

(defstruct (domain-event (:constructor %make-domain-event (type &optional (timestamp (get-universal-time)))))
  (type nil :type keyword :read-only t)
  (timestamp (get-universal-time) :type integer :read-only t))

(defun %make-domain-event-with-invariants (type &optional (timestamp (get-universal-time)))
  (check-type type keyword)
  (check-type timestamp integer)
  (%make-domain-event type timestamp))

(defun make-generic-domain-event (type &key (timestamp (get-universal-time)))
  (%make-domain-event-with-invariants type timestamp))

(defmacro define-event-constructors (&rest specs)
  `(progn
     ,@(loop for (name type args) in specs
              collect `(defun ,name ,args
                          ,(when args `(declare (ignore ,@args)))
                          (%make-domain-event-with-invariants ,type)))))

(define-event-constructors
  (make-command-entered-event :command-entered (text))
  (make-command-parsed-event :command-parsed (ast))
  (make-parse-failed-event :parse-failed (text msg))
  (make-pipeline-started-event :pipeline-started (pipe id))
  (make-process-created-event :process-created (id pid))
  (make-process-exited-event :process-exited (id code))
  (make-pipeline-completed-event :pipeline-completed (id code))
  (make-job-created-event :job-created (id cmd pgid))
  (make-job-stopped-event :job-stopped (id sig))
  (make-job-continued-event :job-continued (id))
  (make-job-completed-event :job-completed (id code))
  (make-signal-caught-event :signal-caught (sig))
  (make-command-appended-to-history-event :command-appended-to-history (entry))
  (make-history-searched-event :history-searched ())
  (make-completion-triggered-event :completion-triggered (prefix)))
