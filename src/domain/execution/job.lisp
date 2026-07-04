(in-package #:nshell.domain.execution)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct (job (:constructor %make-job (id-int pipeline-pipe))
                  (:conc-name job-))
    (id-int 0 :type integer :read-only t)
    (pipeline-pipe nil :type (or null pipeline) :read-only t)
    (state-kw :created :type keyword)
    (pgid 0 :type integer)
    (exit-code nil :type (or null integer))
    (pids nil :type list)
    (command-line "" :type string)
    (background-p nil :type boolean)))
(defun make-job (id pipeline) (%make-job id pipeline))
(defun job-id (j) (job-id-int j))
(defun job-state (j) (job-state-kw j))
(defun job-pipeline (j) (job-pipeline-pipe j))
(defun job-state-valid-p (state)
  (not (null (member state '(:created :running :stopped :background :completed :done)))))

(defun %terminal-job-state-p (state)
  (not (null (member state '(:completed :done)))))

(defun %job-state-transition-valid-p (current-state new-state)
  (or (eq current-state new-state)
      (not (%terminal-job-state-p current-state))))

(defun job-state-transition (job new-state)
  (unless (job-state-valid-p new-state)
    (error "Invalid job state: ~s" new-state))
  (unless (%job-state-transition-valid-p (job-state-kw job) new-state)
    (error "Invalid job state transition: ~s -> ~s"
           (job-state-kw job)
           new-state))
  (unless (eq (job-state-kw job) new-state)
    (setf (job-state-kw job) new-state))
  job)

(defun job-running-p (job) (eq (job-state-kw job) :running))
(defun job-stopped-p (job) (eq (job-state-kw job) :stopped))
(defun job-completed-p (job)
  (not (null (member (job-state-kw job) '(:completed :done)))))

(defun job-register-background-processes (job pids command-line)
  (setf (job-pids job) (copy-list pids)
        (job-pgid job) (first pids)
        (job-command-line job) command-line
        (job-background-p job) t)
  (job-state-transition job :running))

(defun job-set-background-visible (job background-p)
  (setf (job-background-p job) (not (null background-p)))
  job)

(defun job-record-terminal-exit-code (job exit-code)
  (when (and exit-code
             (job-completed-p job))
    (setf (job-exit-code job) exit-code))
  job)

(defun valid-process-group-id-p (pgid)
  (and (integerp pgid) (plusp pgid)))

(defun job-control-pgid (job)
  (let ((pgid (job-pgid job)))
    (when (valid-process-group-id-p pgid)
      pgid)))

(defun job-command-display-string (job)
  (let ((command-line (job-command-line job)))
    (if (plusp (length command-line))
        command-line
        (let ((pipeline (job-pipeline job)))
          (if pipeline
              (format nil "~{~{~a~^ ~}~^ | ~}"
                      (mapcar #'command-to-list
                              (pipeline-commands pipeline)))
              "")))))

(defun job-known-pids (job)
  (remove-if-not (lambda (pid)
                   (and (integerp pid) (plusp pid)))
                 (job-pids job)))

(defun job-last-pid (job)
  (car (last (job-known-pids job))))
