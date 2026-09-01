(in-package #:nshell/test)

(defmacro expect-waitpid-flags (expected &rest options)
  `(expect ,expected
           :to-equal
           (nshell.infrastructure.acl::%waitpid-flags ,@options)))

;;; PTY-driven coverage for a directly-launched (non-`fg`) foreground external
;;; command: the process-group handoff and Ctrl-Z stop handling added to
;;; NSHELL.APPLICATION::%EXECUTE-EXTERNAL-PIPELINE-STAGE (see
;;; src/application/execute-pipeline-stage-external.lisp). These spawn a
;;; second SBCL under a fresh PTY that loads :NSHELL itself and drives that
;;; function directly -- self-contained rather than reusing t/e2e/test-smoke.lisp's
;;; bootstrap helpers, because t/e2e/ loads after this file (see nshell.asd)
;;; and those helpers would be an unresolved forward reference here.

(defun %job-control-test-sbcl-executable ()
  (ignore-errors
   (let ((pathname (probe-file (current-sbcl-executable))))
     (when pathname (namestring (truename pathname))))))

(defun %job-control-asdf-bootstrap-arguments ()
  "--eval arguments that REQUIRE ASDF and register :NSHELL's and
%JOB-CONTROL-DRIVER-DEPENDENCIES%'s source directories on the fresh
subprocess's ASDF central-registry, mirroring t/e2e/test-smoke.lisp's
%ASDF-BOOTSTRAP-FORMS. A bare subprocess starts with an empty central-registry
and no ASDF loaded at all, so ASDF:LOAD-SYSTEM -- or its
FIND-SYMBOL-mediated equivalent in %JOB-CONTROL-STOP-DRIVER-EVAL-STRING --
would fail to find :NSHELL without this, independent of the read-time symbol
hazard that function's docstring describes."
  (let ((root (namestring (asdf:system-source-directory :nshell))))
    (list* "--eval" "(require :asdf)"
           "--eval" (format nil "(pushnew (truename ~S) asdf:*central-registry* :test #'equal)" root)
           (loop for system in +nshell-runtime-dependencies+
                 collect "--eval"
                 collect (format nil "(pushnew (truename ~S) asdf:*central-registry* :test #'equal)"
                                 (namestring (asdf:system-source-directory system)))))))

(defun %job-control-pty-wait-child-exit (pty &key (attempts 40) (delay 0.05))
  (loop repeat attempts
        for status = (multiple-value-list
                      (nshell.infrastructure.acl:wait-job
                       (nshell.infrastructure.acl:pty-process-pid pty)
                       :nohang t))
        when (member (second status) '(:exited :signaled :no-child))
          do (return status)
        do (sleep delay)))

(defun %job-control-stop-driver-eval-string (command args)
  "Build the --eval argument for a PTY-spawned SBCL that loads :NSHELL, then
calls %EXECUTE-EXTERNAL-PIPELINE-STAGE directly on COMMAND/ARGS and reports
the result. Callers must precede this --eval argument with
%JOB-CONTROL-ASDF-BOOTSTRAP-ARGUMENTS's --eval arguments (as
%JOB-CONTROL-STOP-DRIVER-ARGUMENTS does) -- without them ASDF is not loaded
and :NSHELL's central-registry entry does not exist, so ASDF:LOAD-SYSTEM
fails to find :NSHELL regardless of how it is referenced below.

Built as literal TEXT via FORMAT -- exactly like t/e2e/test-smoke.lisp's
%NSHELL-MAIN-FORM -- rather than by backquoting a Lisp form and printing it
with ~S. An earlier version of this function backquoted (ASDF:LOAD-SYSTEM
...) plus local variables such as NODE, STAGE-FN, and JOBS-FN; every one of
those is an ordinary symbol interned in *some* package at backquote
construction time (ASDF:LOAD-SYSTEM in ASDF/OPERATE under a package-split
ASDF >= 3.2; NODE and friends in this file's own NSHELL/TEST), and printing
that structure with ~S serializes every symbol fully package-qualified. The
fresh subprocess -- which loads only :NSHELL, never :NSHELL/TEST, and starts
with no ASDF loaded -- cannot read a token naming either package back,
failing with SIMPLE-READER-PACKAGE-ERROR before any evaluation starts
(confirmed against both ASDF/OPERATE:LOAD-SYSTEM and NSHELL/TEST::NODE).

Only ~S-printing an already-known STRING value (COMMAND, each of ARGS) is
safe, because a Lisp string literal reads back without needing any package
to exist -- so those two are the only FORMAT directives below. Everything
else is literal source text the subprocess reads fresh in its own default
package, using FIND-SYMBOL on strings (never a literal package-qualified
symbol) to reach :NSHELL's own definitions once :NSHELL has actually loaded."
  (format nil
          "(progn
             (handler-case
                 (let ((*error-output* (make-broadcast-stream)))
                   (funcall (find-symbol \"LOAD-SYSTEM\" \"ASDF\") :nshell))
               (error (condition)
                 (format t \"nshell-load-failed: ~~a~~%\" condition)
                 (finish-output)
                 (sb-ext:exit :code 1)))
             (format t \"nshell-loaded~~%\")
             (finish-output)
             (let* ((node (funcall (find-symbol \"MAKE-COMMAND-NODE\" \"NSHELL.DOMAIN.PARSING\")
                                    ~s (list ~s)))
                    (stage-fn
                      (find-symbol \"%EXECUTE-EXTERNAL-PIPELINE-STAGE\" \"NSHELL.APPLICATION\"))
                    (jobs-fn (find-symbol \"JOBS\" \"NSHELL.APPLICATION\")))
               (multiple-value-bind (output code) (funcall stage-fn node nil nil)
                 (declare (ignore output))
                 (format t \"exit-code=~~a~~%\" code)
                 (format t \"jobs-count=~~a~~%\" (length (funcall jobs-fn)))
                 (finish-output))))"
          command args))

(defun %job-control-stop-driver-arguments (command args)
  (append (list "--noinform" "--disable-debugger")
          (%job-control-asdf-bootstrap-arguments)
          (list "--eval" (%job-control-stop-driver-eval-string command args))))

(describe "job-control-pty-integration-tests"
  (it "directly-launched-foreground-command-survives-ctrl-z-without-hanging"
    "A directly-launched (non-fg) foreground external command gets its own
process group and the terminal's foreground group, so Ctrl-Z stops the child
via the kernel instead of the shell process. The wait refuses the suspension
-- it SIGCONTs the child and keeps waiting (see
%CONTINUE-STOPPED-EXTERNAL-PROCESS for why suspending cannot work on this
synchronous path) -- so the command must run to completion with its normal
exit status, no job registered, and above all no hang: pre-fix, the plain
%WAIT-PROCESS-WITH-COPIERS blocked forever against the stopped child."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "spawns a real SBCL/:nshell subprocess under a PTY"
      (let ((program (%job-control-test-sbcl-executable))
            (pty nil))
        (unless program
          (skip "requires an absolute SBCL runtime path"))
        (unwind-protect
             (progn
               (setf pty
                     (nshell.infrastructure.acl:pty-spawn
                      program
                      (%job-control-stop-driver-arguments "/bin/sleep" "3")
                      :rows 24
                      :cols 100))
               (let ((fd (nshell.infrastructure.acl:pty-process-master-fd pty)))
                 (let ((loaded (pty-test-read-until fd "nshell-loaded" :attempts 400)))
                   (if (search "nshell-load-failed" loaded)
                       (skip (format nil "subprocess could not load :nshell: ~a" loaded))
                       (progn
                         (expect (search "nshell-loaded" loaded) :to-be-truthy)
                         (sleep 0.3)
                         (nshell.infrastructure.acl:pty-write fd (string (code-char 26)))
                         (let ((output (pty-test-read-until fd "jobs-count=" :attempts 400)))
                           (expect (search "exit-code=0" output) :to-be-truthy)
                           (expect (search "jobs-count=0" output) :to-be-truthy))))))
               (%job-control-pty-wait-child-exit pty))
          (pty-test-close-process pty))))))

(describe "job-control-integration-tests"
  (it "job-creation-assigns-unique-ids"
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job1 (make-test-job 0 "sleep" :args '("1")))
           (job2 (make-test-job 1 "sleep" :args '("2")))
           (id1 (nshell.domain.job-control:monitor-add-job monitor job1))
           (id2 (nshell.domain.job-control:monitor-add-job monitor job2)))
      (expect (= id1 id2) :to-be-falsy)
      (expect 1 :to-equal id1)
      (expect 2 :to-equal id2)))

  (it "job-state-transitions-created-running-stopped-completed"
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "sleep" :args '("1")))
           (id (nshell.domain.job-control:monitor-add-job monitor job)))
      (expect :created :to-be (nshell.domain.execution:job-state job))
      (nshell.domain.job-control:monitor-update monitor id :running)
      (expect :running :to-be (nshell.domain.execution:job-state job))
      (nshell.domain.job-control:monitor-update monitor id :stopped)
      (expect :stopped :to-be (nshell.domain.execution:job-state job))
      (nshell.domain.job-control:monitor-update monitor id :completed 0)
      (expect :completed :to-be (nshell.domain.execution:job-state job))
      (expect 0 :to-equal (nshell.domain.execution:job-exit-code job))))

  (it "jobs-returns-current-job-list"
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job (make-test-job 0 "echo" :args '("hello"))))
      (nshell.domain.job-control:monitor-add-job monitor job)
      (let ((returned (mapcar #'test-monitor-entry-job
                              (collect-monitor-entries monitor))))
        (expect 1 :to-equal (length returned))
        (expect (search "echo hello"
                    (nshell.domain.execution:job-command-line (first returned))) :to-be-truthy))))

  (it "reap-children-cleans-up-zombies"
    "Verify that process-wait properly cleans up child processes."
    (let ((proc (sb-ext:run-program "true" nil :wait nil :search t)))
      ;; Wait for the process via SBCL's process-wait
      (sb-ext:process-wait proc)
      (let ((pid (sb-ext:process-pid proc)))
        (expect (integerp pid) :to-be-truthy)
        (expect (sb-ext:process-alive-p proc) :to-be-falsy)))))

  (it "wait-job-flags-request-wcontinued-when-available"
    (let* ((wcontinued-symbol (find-symbol "WCONTINUED" "SB-POSIX"))
           (wcontinued (and wcontinued-symbol
                            (boundp wcontinued-symbol)
                            (symbol-value wcontinued-symbol))))
      (expect (logior sb-posix:wnohang
                      sb-posix:wuntraced
                      (or wcontinued 0))
              :to-equal
              (nshell.infrastructure.acl::%waitpid-flags
               :nohang t
               :untraced t
               :continued t))))

  (it "wait-job-flags-compose-each-independent-option"
    "Each waitpid option contributes only its own platform flag."
    (expect-waitpid-flags 0)
    (expect-waitpid-flags sb-posix:wnohang :nohang t)
    (expect-waitpid-flags sb-posix:wuntraced :untraced t)
    (let* ((symbol (find-symbol "WCONTINUED" "SB-POSIX"))
           (continued (and symbol (boundp symbol) (symbol-value symbol))))
      (expect-waitpid-flags (or continued 0) :continued t)))
