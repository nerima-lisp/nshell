(in-package #:nshell.domain.execution)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct (pipeline (:constructor %make-pipeline (commands-list))
                       (:conc-name pipeline-))
    (commands-list nil :type list :read-only t))

  (defstruct (pipe-config (:constructor %make-pipe-config (&key stdin stdout index last-p))
                          (:conc-name pipe-config-))
    (stdin nil :type (or null keyword))
    (stdout nil :type (or null keyword))
    (index 0 :type integer :read-only t)
    (last-p nil :type boolean :read-only t))

  (defstruct (pipeline-stage (:constructor %make-pipeline-stage (stage-command pipe-config))
                             (:conc-name pipeline-stage-))
    (stage-command nil :read-only t)
    (pipe-config nil :type pipe-config :read-only t))

  (defstruct (pipeline-plan (:constructor %make-pipeline-plan (stages))
                            (:conc-name pipeline-plan-))
    (stages nil :type list :read-only t)))

(defun %pipeline-command-list (commands)
  (copy-list commands))

(defun %pipeline-commands (pipe)
  (pipeline-commands-list pipe))

(defun make-pipeline (&rest commands)
  (%make-pipeline (%pipeline-command-list commands)))
(defun pipeline-commands (pipe) (%pipeline-command-list (%pipeline-commands pipe)))
(defun pipeline-single-command-p (pipe) (= (length (%pipeline-commands pipe)) 1))
(defun pipeline-empty-p (pipe) (null (%pipeline-commands pipe)))
(defun pipeline-length (pipe) (length (%pipeline-commands pipe)))

(defun make-pipeline-plan (pipeline)
  "Create a pure execution plan from PIPELINE."
  (let* ((commands (%pipeline-commands pipeline))
         (last-index (1- (length commands))))
    (%make-pipeline-plan
     (loop for command in commands
           for index from 0
           for last-p = (= index last-index)
           collect (%make-pipeline-stage
                    command
                    (%make-pipe-config
                     :stdin (when (plusp index) :pipe)
                     :stdout (unless last-p :pipe)
                     :index index
                     :last-p last-p))))))

(defun pipeline-plan-stage-count (plan)
  "Return the number of stages in PLAN."
  (length (pipeline-plan-stages plan)))

(defun pipeline-plan-commands (plan)
  "Return the commands in PLAN stage order."
  (mapcar #'pipeline-stage-stage-command
          (pipeline-plan-stages plan)))

(defun %pipeline-plan-stage-at (plan index)
  (unless (and (integerp index)
               (<= 0 index)
               (< index (pipeline-plan-stage-count plan)))
    (error "Invalid pipeline stage index: ~s" index))
  (nth index (pipeline-plan-stages plan)))

(defun %pipeline-plan-stage-pipe-config (plan index)
  (pipeline-stage-pipe-config
   (%pipeline-plan-stage-at plan index)))

(defun pipeline-plan-stage-piped-input-p (plan index)
  "Return true when stage INDEX receives stdin from a previous pipeline stage."
  (eq :pipe
      (pipe-config-stdin
       (%pipeline-plan-stage-pipe-config plan index))))

(defun pipeline-plan-stage-piped-output-p (plan index)
  "Return true when stage INDEX writes stdout to the next pipeline stage."
  (eq :pipe
      (pipe-config-stdout
       (%pipeline-plan-stage-pipe-config plan index))))
