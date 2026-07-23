(in-package #:nshell.domain.execution)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct (job (:constructor %allocate-job (id-int pipeline-pipe))
                  (:copier nil)
                  (:conc-name job-))
    (id-int 0 :type integer :read-only t)
    (pipeline-pipe nil :type (or null pipeline) :read-only t)
    (state-kw :created :type keyword)
    (pgid-int 0 :type integer)
    (exit-code-int nil :type (or null integer))
    (pids-list nil :type list)
    (command-line-str "" :type string)
    (background-visible-p nil :type boolean)))

(defun %job-string-value (value)
  (copy-seq value))

(defun %job-pid-list (pids)
  (copy-list pids))

(defun %job-state (job)
  (job-state-kw job))

(defun %set-job-state (job state)
  (setf (job-state-kw job) state))

(defun %job-pipeline (job)
  (job-pipeline-pipe job))

(defun %job-pgid (job)
  (job-pgid-int job))

(defun %set-job-pgid (job pgid)
  (setf (job-pgid-int job) pgid))

(defun %job-exit-code (job)
  (job-exit-code-int job))

(defun %set-job-exit-code (job exit-code)
  (setf (job-exit-code-int job) exit-code))

(defun %job-pids (job)
  (job-pids-list job))

(defun %set-job-pids (job pids)
  (setf (job-pids-list job) (%job-pid-list pids)))

(defun %job-command-line (job)
  (job-command-line-str job))

(defun %set-job-command-line (job command-line)
  (setf (job-command-line-str job) (%job-string-value command-line)))

(defun %job-background-p (job)
  (job-background-visible-p job))

(defun %set-job-background-p (job background-p)
  (setf (job-background-visible-p job) (not (null background-p))))

(defun %assert-job-id (id)
  (unless (integerp id)
    (error "Invalid job id: ~s" id)))

(defun %assert-job-pipeline (pipeline)
  (unless (or (null pipeline)
              (pipeline-p pipeline))
    (error "Invalid job pipeline: ~s" pipeline)))

(defun %assert-job-pgid (pgid)
  (unless (integerp pgid)
    (error "Invalid job process group id: ~s" pgid)))

(defun %assert-job-pids (pids)
  (unless (listp pids)
    (error "Invalid job pid list: ~s" pids)))

(defun %assert-job-command-line (command-line)
  (unless (stringp command-line)
    (error "Invalid job command line: ~s" command-line)))

(defun %make-job-with-invariants (id pipeline)
  (%assert-job-id id)
  (%assert-job-pipeline pipeline)
  (%allocate-job id pipeline))

(defun make-job (id pipeline)
  (%make-job-with-invariants id pipeline))
(defun job-id (j) (job-id-int j))
(defun job-state (j) (%job-state j))
(defun job-pgid (j) (%job-pgid j))
(defun job-exit-code (j) (%job-exit-code j))
(defun job-pids (j) (%job-pid-list (%job-pids j)))
(defun job-command-line (j) (%job-string-value (%job-command-line j)))
(defun job-background-p (j) (%job-background-p j))

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
  (unless (%job-state-transition-valid-p (%job-state job) new-state)
    (error "Invalid job state transition: ~s -> ~s"
           (%job-state job)
           new-state))
  (unless (eq (%job-state job) new-state)
    (%set-job-state job new-state))
  job)

(defun job-running-p (job) (eq (%job-state job) :running))
(defun job-stopped-p (job) (eq (%job-state job) :stopped))
(defun job-completed-p (job)
  (not (null (member (%job-state job) '(:completed :done)))))

(defun job-record-runtime-metadata (job &key
                                          (pids nil pids-supplied-p)
                                          (pgid nil pgid-supplied-p)
                                          (command-line nil command-line-supplied-p))
  (when pids-supplied-p
    (%assert-job-pids pids)
    (%set-job-pids job pids))
  (when pgid-supplied-p
    (%assert-job-pgid pgid)
    (%set-job-pgid job pgid))
  (when command-line-supplied-p
    (%assert-job-command-line command-line)
    (%set-job-command-line job command-line))
  job)

(defun job-register-background-processes (job pids command-line)
  (job-record-runtime-metadata job
                               :pids pids
                               :pgid (or (first pids) 0)
                               :command-line command-line)
  (%set-job-background-p job t)
  (job-state-transition job :running))

(defun job-set-background-visible (job background-p)
  (%set-job-background-p job background-p)
  job)

(defun job-record-terminal-exit-code (job exit-code)
  (when (and exit-code
             (job-completed-p job))
    (%set-job-exit-code job exit-code))
  job)

(defun valid-process-group-id-p (pgid)
  (and (integerp pgid) (plusp pgid)))

(defun job-control-pgid (job)
  (let ((pgid (%job-pgid job)))
    (when (valid-process-group-id-p pgid)
      pgid)))

(defun job-command-display-string (job)
  (let ((command-line (%job-command-line job)))
    (if (plusp (length command-line))
        (%job-string-value command-line)
        (let ((pipeline (%job-pipeline job)))
          (if pipeline
              (format nil "~{~{~a~^ ~}~^ | ~}"
                      (mapcar #'command-to-list
                              (pipeline-commands pipeline)))
              "")))))

(defun job-known-pids (job)
  (remove-if-not (lambda (pid)
                   (and (integerp pid) (plusp pid)))
                 (%job-pids job)))

(defun job-last-pid (job)
  (car (last (job-known-pids job))))
