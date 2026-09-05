(in-package #:nshell/test)

(defun %job-pty-foreground-group (fd)
  (sb-alien:alien-funcall
   (sb-alien:extern-alien "tcgetpgrp" (function sb-alien:int sb-alien:int)) fd))

(defun %job-process-state (pid)
  (multiple-value-bind (output error-output code)
      (uiop:run-program (list "ps" "-o" "pgid=" "-o" "state=" "-p"
                              (write-to-string pid))
                        :output :string :error-output :string
                        :ignore-error-status t)
    (declare (ignore error-output))
    (when (zerop code)
      (let ((fields (uiop:split-string output :separator '(#\Space #\Tab #\Newline))))
        (setf fields (remove "" fields :test #'string=))
        (when (= 2 (length fields))
          (list (parse-integer (first fields)) (second fields)))))))

(defun %job-pty-await (fd predicate)
  (let ((output "")
        (deadline (+ (get-internal-real-time)
                     (* 15 internal-time-units-per-second))))
    (loop
      (when (funcall predicate output)
        (return output))
      (when (>= (get-internal-real-time) deadline)
        (error "PTY job condition timed out; output: ~S" output))
      (let ((chunk (%e2e-pty-read-available fd)))
        (when chunk
          (setf output (concatenate 'string output chunk)))))))

(defun %job-marker-pid (output label)
  (let* ((marker (format nil "job-~A:<" label))
         (start (search marker output)))
    (when start
      (let* ((begin (+ start (length marker)))
             (end (position #\> output :start begin)))
        (when end
          (parse-integer output :start begin :end end))))))

(defun %call-with-job-pty (function)
  #-(or darwin linux)
  (skip "PTY tests are only supported on Darwin and Linux")
  #+(or darwin linux)
  (skip-when-pty-unavailable "launches real nshell under a PTY"
    (let ((program (%absolute-sbcl-executable)) (pty nil) (groups nil))
      (unless program
        (skip "requires an absolute SBCL runtime path"))
      (unwind-protect
           (progn
             (setf pty (nshell.infrastructure.acl:pty-spawn
                        program (%nshell-main-pty-arguments) :rows 24 :cols 100))
             (let ((fd (nshell.infrastructure.acl:pty-process-master-fd pty)))
               (%e2e-pty-await-ready fd)
               (funcall function pty fd
                        (lambda (pgid)
                          (when (and pgid (plusp pgid)
                                     (/= pgid (nshell.infrastructure.acl:pty-process-pgid pty)))
                            (pushnew pgid groups))))))
        (when pty
          (let ((foreground (ignore-errors
                              (%job-pty-foreground-group
                               (nshell.infrastructure.acl:pty-process-master-fd pty)))))
            (when (and foreground (plusp foreground)
                       (/= foreground (nshell.infrastructure.acl:pty-process-pgid pty)))
              (pushnew foreground groups)))
          (dolist (pgid groups)
            (ignore-errors (nshell.infrastructure.acl:kill-process (- pgid) 9)))
          (%terminate-pty-process pty))))))

(defun %assert-pty-job-lifecycle (pipeline-p)
  (%call-with-job-pty
   (lambda (pty fd remember-group)
     (let* ((labels (if pipeline-p '("left" "middle" "right") '("single")))
            (pids nil)
            (pgid nil)
            (command
              (format nil "~{~A~^ | ~}"
                      (mapcar (lambda (label)
                                (format nil "sh -c 'printf \"job-%s:<%s>\\n\" ~A \"$$\" > /dev/tty; exec sleep 30'"
                                        label))
                              labels))))
       (%e2e-pty-write-line fd command)
       (%job-pty-await
        fd (lambda (output)
             (setf pids (remove nil (mapcar (lambda (label)
                                             (%job-marker-pid output label)) labels)))
             (dolist (pid pids)
               (let ((state (%job-process-state pid)))
                 (when state (funcall remember-group (first state)))))
             (= (length pids) (length labels))))
       (setf pgid (first (%job-process-state (first pids))))
       (expect (and pgid (plusp pgid)
                    (/= pgid (nshell.infrastructure.acl:pty-process-pgid pty)))
               :to-be-truthy)
       (expect (length labels) :to-equal (length (remove-duplicates pids)))
       (flet ((all-in-state (stopped-p)
                (every (lambda (pid)
                         (let ((state (%job-process-state pid)))
                           (and state (= pgid (first state))
                                (if stopped-p
                                    (find #\T (second state))
                                    (not (find #\T (second state))))))) pids)))
         (%job-pty-await fd (lambda (output)
                             (declare (ignore output))
                             (and (= pgid (%job-pty-foreground-group fd))
                                  (all-in-state nil))))
         (nshell.infrastructure.acl:pty-write fd (string (code-char 26)))
         (%job-pty-await fd (lambda (output)
                             (declare (ignore output))
                             (and (= (nshell.infrastructure.acl:pty-process-pgid pty)
                                     (%job-pty-foreground-group fd))
                                  (all-in-state t))))
         (%e2e-pty-write-line fd "jobs")
         (%e2e-pty-write-line fd "printf 'job-%s\\n' stopped-list-end")
         (let ((output (%e2e-pty-read-until fd "job-stopped-list-end")))
           (expect (search "job-stopped-list-end" output) :to-be-truthy)
           (expect (search "[1] Stopped" output) :to-be-truthy))
         (%e2e-pty-write-line fd "bg 1")
         (%job-pty-await fd (lambda (output)
                             (declare (ignore output))
                             (all-in-state nil)))
         (%e2e-pty-write-line fd "jobs")
         (%e2e-pty-write-line fd "printf 'job-%s\\n' running-list-end")
         (let ((output (%e2e-pty-read-until fd "job-running-list-end")))
           (expect (search "job-running-list-end" output) :to-be-truthy)
           (expect (search "[1] Running" output) :to-be-truthy))
         (%e2e-pty-write-line fd "fg 1")
         (%job-pty-await fd (lambda (output)
                             (declare (ignore output))
                             (and (= pgid (%job-pty-foreground-group fd))
                                  (all-in-state nil))))
         (nshell.infrastructure.acl:pty-write fd (string (code-char 3)))
         (%job-pty-await fd (lambda (output)
                             (declare (ignore output))
                             (= (nshell.infrastructure.acl:pty-process-pgid pty)
                                (%job-pty-foreground-group fd))))
         (%e2e-pty-write-line fd "printf 'job-status:<%s>\\n' $status")
         (expect (search "job-status:<130>"
                         (%e2e-pty-read-until fd "job-status:<130>")) :to-be-truthy)
         (%job-pty-await fd (lambda (output)
                             (declare (ignore output))
                             (every (lambda (pid) (null (%job-process-state pid))) pids))))
       (%e2e-pty-write-line fd "exit 0")
       (%assert-pty-child-exit pty)))))

(describe "e2e-job-tests"
  (it "e2e-external-command-tty-input-and-live-output"
    (%call-with-job-pty
     (lambda (pty fd remember-group)
       (declare (ignore remember-group))
       (%e2e-pty-write-line
        fd "sh -c 'test -t 0 && test -t 1 && test -t 2 || exit 91; printf \"tty-%s>\" read-ready; IFS= read -r value || exit 92; printf \"tty-input:<%s>\\n\" \"$value\"; printf \"tty-%s\\n\" stderr-ok >&2'")
       (expect (search "tty-read-ready>" (%e2e-pty-read-until fd "tty-read-ready>"))
               :to-be-truthy)
       (%e2e-pty-write-line fd "accepted-input")
       (let ((output (%e2e-pty-read-until fd "tty-stderr-ok")))
         (expect (search "tty-input:<accepted-input>" output) :to-be-truthy)
         (expect (search "tty-stderr-ok" output) :to-be-truthy))
       (%e2e-pty-write-line fd "exit")
       (%assert-pty-child-exit pty))))
  (it "e2e-external-job-stop-bg-fg-interrupt"
    (%assert-pty-job-lifecycle nil))
  (it "e2e-external-pipeline-stop-bg-fg-interrupt"
    (%assert-pty-job-lifecycle t))
  (it "e2e-external-pipeline-short-first-stage-restores-terminal"
    (%call-with-job-pty
     (lambda (pty fd remember-group)
       (declare (ignore remember-group))
       (%e2e-pty-write-line
        fd "sh -c 'printf \"%s\\n\" short-first' | cat | sh -c 'IFS= read -r value || exit 91; printf \"pipeline-short:<%s>\\n\" \"$value\"'")
       (expect (search "pipeline-short:<short-first>"
                       (%e2e-pty-read-until fd "pipeline-short:<short-first>"))
               :to-be-truthy)
       (%job-pty-await fd (lambda (output)
                           (declare (ignore output))
                           (= (nshell.infrastructure.acl:pty-process-pgid pty)
                              (%job-pty-foreground-group fd))))
       (%e2e-pty-write-line fd "printf 'pipeline-status:<%s>\\n' $status")
       (expect (search "pipeline-status:<0>"
                       (%e2e-pty-read-until fd "pipeline-status:<0>"))
               :to-be-truthy)
       (nshell.infrastructure.acl:pty-write fd "printf 'pipeline-edit:<%s>\\n' okx")
       (nshell.infrastructure.acl:pty-write fd (string (code-char 8)))
       (nshell.infrastructure.acl:pty-write fd (string #\Newline))
       (expect (search "pipeline-edit:<ok>"
                       (%e2e-pty-read-until fd "pipeline-edit:<ok>"))
               :to-be-truthy)
       (%e2e-pty-write-line fd "exit 0")
       (%assert-pty-child-exit pty)))))
