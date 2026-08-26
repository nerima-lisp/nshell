(in-package #:nshell/test)

(defun %process-test-sbcl-command-node (form)
  (nshell.domain.parsing:make-command-node
   (current-sbcl-executable)
   (%process-test-sbcl-argv form)))

(defun %process-test-sbcl-argv (form)
  (list "--noinform"
        "--non-interactive"
        "--disable-debugger"
        "--eval"
        form))

(describe "process-tests"
  (it "foreground-external-command-timeout-is-nil-by-default-for-noninteractive-output"
    "With *EXTERNAL-COMMAND-TIMEOUT* left at its production default (now NIL),
%FOREGROUND-EXTERNAL-COMMAND-TIMEOUT must return NIL even when
*STANDARD-OUTPUT* is not an interactive terminal -- pre-fix the default was
30, so this same non-interactive check would have returned 30 (a truthy,
enforced timeout) instead."
    (let ((*standard-output* (make-string-output-stream)))
      (expect (nshell.infrastructure.acl::%foreground-external-command-timeout)
              :to-be nil)))

  (it "run-external-exec-echo"
  "Exec-mode external command preserves direct standard output and returns exit 0."
  (let* ((exit nil)
         (output
           (capture-standard-output
             (setf exit
                   (nshell.infrastructure.acl:run-external-exec
                    "echo" '("hello"))))))
    (expect 0 :to-equal exit)
    (expect (format nil "hello~%") :to-equal output)))
  (it "run-external-exec-times-out-and-returns"
    "Exec-mode external commands use the shared noninteractive timeout policy."
    (let* ((nshell.infrastructure.acl:*external-command-timeout* 0.2)
           (exit nil)
           (error-output
             (with-output-to-string (*error-output*)
               (let ((*standard-output* (make-string-output-stream)))
                 (setf exit
                       (nshell.infrastructure.acl:run-external-exec
                        (current-sbcl-executable)
                        (%process-test-sbcl-argv "(sleep 5)")))))))
      (expect 124 :to-equal exit)
      (expect (search "timed out after" error-output) :to-be-truthy)))
  (it "run-external-echo"
    "External echo command executes and returns exit 0"
    (let ((exit (nshell.infrastructure.acl:run-external "echo" '("hello"))))
      (expect 0 :to-equal exit)))

  (it "run-external-large-output-streams-before-wait"
    "Synchronous execution drains stdout before waiting for process exit."
    (let* ((size 131072)
           (form (format nil
                         "(write-string (make-string ~d :initial-element #\\x))"
                         size))
           (exit nil)
           (output
             (capture-standard-output
               (setf exit
                     (nshell.infrastructure.acl:run-external
                      (current-sbcl-executable)
                      (%process-test-sbcl-argv form))))))
      (expect 0 :to-equal exit)
      (expect size :to-equal (length output))
      (let ((bad-index (position-if-not (lambda (char) (char= #\x char)) output)))
        (expect bad-index :to-be-null)
        (when bad-index
          (fail "unexpected character at ~d: ~s" bad-index (char output bad-index))))))

  (it "run-external-capture-echo"
    "External command capture returns stdout and exit code."
    (multiple-value-bind (output exit)
        (nshell.infrastructure.acl:run-external-capture "echo" '("hello"))
      (expect 0 :to-equal exit)
      (expect (format nil "hello~%") :to-equal output)))

  (it "run-external-times-out-and-returns"
    "Synchronous execution should time out while reading output or waiting."
    ;; *STANDARD-OUTPUT* is bound to a string stream, and that binding is load
    ;; bearing rather than merely tidy. %FOREGROUND-EXTERNAL-COMMAND-TIMEOUT
    ;; applies *EXTERNAL-COMMAND-TIMEOUT* only when stdout is NOT an
    ;; interactive terminal, so redirecting stdout is what puts this call on
    ;; the timeout-bearing path in the first place -- the same path a user gets
    ;; from `cmd > file`. SBCL reports its standard streams as interactive even
    ;; when the process is running with them attached to a pipe, so without
    ;; this binding the timeout is skipped and the child runs to completion.
    (let* ((nshell.infrastructure.acl:*external-command-timeout* 0.2)
           (exit nil)
           (error-output
             (with-output-to-string (*error-output*)
               (let ((*standard-output* (make-string-output-stream)))
                 (setf exit
                       (nshell.infrastructure.acl:run-external
                        (current-sbcl-executable)
                        (list "--noinform"
                              "--non-interactive"
                              "--disable-debugger"
                              "--eval"
                              "(sleep 5)")))))))
      (expect 124 :to-equal exit)
      (expect (search "timed out after" error-output) :to-be-truthy)))

  (it "run-external-timeout-terminates-descendant-processes"
    "Timeout cleanup should kill descendants that inherited stdout."
    #+unix
    (with-temporary-output-file (pid-file :prefix "nshell-timeout-child")
      (let ((nshell.infrastructure.acl:*external-command-timeout* 0.3)
            (child-pid nil)
            (exit nil)
            (started-at (get-internal-real-time)))
        (unwind-protect
             (progn
               (with-output-to-string (*error-output*)
                 (let ((*standard-output* (make-string-output-stream)))
                   (setf exit
                         (nshell.infrastructure.acl:run-external
                          "/bin/sh"
                          (list "-c"
                                "trap \"\" TERM; sleep 0.05; sleep 30 & echo $! > \"$1\"; wait"
                                "sh"
                                (namestring pid-file))))))
               (setf child-pid
                     (parse-integer
                      (string-trim '(#\Space #\Tab #\Newline #\Return)
                                   (host-kit:read-file-string pid-file))))
               (loop repeat 100
                     while (ignore-errors (sb-posix:kill child-pid 0) t)
                     do (sleep 0.01))
               (expect 124 :to-equal exit)
               (expect (/ (- (get-internal-real-time) started-at)
                          internal-time-units-per-second)
                       :to-be-less-than 2.0)
               (expect (ignore-errors (sb-posix:kill child-pid 0) t)
                       :to-be-null))
          (when (and child-pid
                     (ignore-errors (sb-posix:kill child-pid 0) t))
            (ignore-errors (sb-posix:kill child-pid sb-unix:sigkill))))))
    #-unix
    (pass "Process-group cleanup is Unix-specific."))

  (it "run-external-capture-times-out-and-returns"
    "Captured synchronous execution should return a timeout message and exit 124."
    (let ((nshell.infrastructure.acl:*external-command-timeout* 0.2))
      (multiple-value-bind (output exit)
          (nshell.infrastructure.acl:run-external-capture
           (current-sbcl-executable)
           (%process-test-sbcl-argv "(sleep 5)"))
        (expect 124 :to-equal exit)
        (expect (search "timed out after" output) :to-be-truthy))))

  (it "run-external-capture-signal-exit-status"
    "External command capture normalizes signaled processes to 128+signal."
    (multiple-value-bind (output exit)
        (nshell.infrastructure.acl:run-external-capture
         "sh"
         '("-c" "kill -TERM $$"))
      (expect 143 :to-equal exit)
      (expect "" :to-equal output)))

  (it "run-external-nonexistent"
    "Nonexistent command returns error exit code"
    (let ((exit (nshell.infrastructure.acl:run-external "nonexistent_cmd_xyz" '())))
      (expect (= 0 exit) :to-be-falsy)))

  (it "run-external-capture-nonexistent"
    "Nonexistent command capture returns an error exit code and message."
    (multiple-value-bind (output exit)
        (nshell.infrastructure.acl:run-external-capture "nonexistent_cmd_xyz" '())
      (expect (= 0 exit) :to-be-falsy)
      (expect (search "nonexistent_cmd_xyz" output) :to-be-truthy)))

  (it "spawn-async-inherits-output-when-unredirected"
    "Unredirected background processes should not leave an unread output pipe."
    (let ((proc (nshell.infrastructure.acl:spawn-async
                 "true"
                 nil)))
      (expect (null proc) :to-be-falsy)
      (when proc
        (unwind-protect
             (progn
               (sb-ext:process-wait proc)
               (expect (sb-ext:process-output proc) :to-be-null)
               (expect 0 :to-equal (sb-ext:process-exit-code proc)))
          (when (sb-ext:process-alive-p proc)
            (ignore-errors
              (sb-ext:process-kill proc 15)))))))

  (it "spawn-async-here-document-redirects-standard-input"
    "Asynchronous process spawning should route a here-document to stdin."
    (let ((proc (nshell.infrastructure.acl:spawn-async
                 (current-sbcl-executable)
                 (%process-test-sbcl-argv
                  "(sb-ext:exit :code (if (string= (read-line) \"inline-doc\") 0 7))")
                 :redirects
                 (list (cons :<<-
                             (format nil "inline-doc~%"))))))
      (expect proc :to-be-truthy)
      (when proc
        (sb-ext:process-wait proc)
        (expect 0 :to-equal (sb-ext:process-exit-code proc)))))

  (it "spawn-pipeline-pipes-stdout-only-by-default"
    "Pipeline stages pipe stdout only unless stderr is explicitly merged."
    (let* ((writer (%process-test-sbcl-command-node
                    "(progn (write-string \"OUT\") (write-string \"ERR\" *error-output*))"))
           (counter (%process-test-sbcl-command-node
                     "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
           (exit nil)
           (output (capture-standard-output
                     (setf exit
                           (nshell.infrastructure.acl:spawn-pipeline
                            (list writer counter))))))
      (expect 0 :to-equal exit)
      (expect (format nil "3~%") :to-equal output)))

  (it "spawn-pipeline-pipes-stderr-when-explicitly-merged"
    "An explicit 2>&1 redirect merges stderr into the downstream pipeline input."
    (let* ((writer (%process-test-sbcl-command-node
                    "(progn (write-string \"OUT\") (write-string \"ERR\" *error-output*))"))
           (counter (%process-test-sbcl-command-node
                     "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
           (exit nil)
           (output (capture-standard-output
                     (setf exit
                            (nshell.infrastructure.acl:spawn-pipeline
                            (list writer counter)
                            :redirects (list (list (cons :2>&1 nil)) nil))))))
      (expect 0 :to-equal exit)
      (expect (format nil "6~%") :to-equal output)))

  (it "spawn-pipeline-routes-stdout-to-stderr-with-dynamic-fd-dup"
    "A dynamic 1>&2 redirect should leave downstream stdout empty and route both writes to stderr."
    (let* ((writer (%process-test-sbcl-command-node
                    "(progn (write-string \"OUT\") (write-string \"ERR\" *error-output*))"))
           (counter (%process-test-sbcl-command-node
                     "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
           (exit nil)
           (error-output nil)
           (output
             (capture-standard-output
               (setf error-output
                     (with-output-to-string (*error-output*)
                       (setf exit
                             (nshell.infrastructure.acl:spawn-pipeline
                              (list writer counter)
                              :redirects
                              (list
                               (list
                                (cons
                                 :fd-dup
                                 (nshell.domain.parsing:make-redirect-fd-dup-target
                                  1
                                  2)))
                               nil))))))))
      (expect 0 :to-equal exit)
      (expect (format nil "0~%") :to-equal output)
      (expect (search "OUT" error-output) :to-be-truthy)
      (expect (search "ERR" error-output) :to-be-truthy)
      (expect (search "OUT" output) :to-be-falsy)
      (expect (search "ERR" output) :to-be-falsy)))

  (it "spawn-pipeline-here-document-redirects-standard-input"
    "Pipeline stages should receive a here-document on standard input."
    (let* ((reader (%process-test-sbcl-command-node
                    "(write-line (read-line))"))
           (exit nil)
           (output (capture-standard-output
                     (setf exit
                           (nshell.infrastructure.acl:spawn-pipeline
                            (list reader)
                            :redirects
                            (list (list (cons :<<-
                                              (format nil "inline-doc~%")))))))))
      (expect 0 :to-equal exit)
      (expect (format nil "inline-doc~%") :to-equal output)))

  (it "spawn-pipeline-times-out-and-returns"
    "Synchronous pipelines should time out and terminate started processes."
    (let* ((nshell.infrastructure.acl:*external-command-timeout* 0.2)
           (sleeper (%process-test-sbcl-command-node "(sleep 5)"))
           (exit nil)
           (error-output
             (with-output-to-string (*error-output*)
               (let ((*standard-output* (make-string-output-stream)))
                 (setf exit
                       (nshell.infrastructure.acl:spawn-pipeline
                        (list sleeper)))))))
      (expect 124 :to-equal exit)
      (expect (search "pipeline timed out" error-output) :to-be-truthy)))

  (it "spawn-pipeline-redirect-dup-before-stdout-redirect-keeps-stderr-on-pipe"
    "2>&1 before a stdout redirect keeps stderr connected to the original pipeline stdout."
    (with-temporary-output-file (target :prefix "nshell-pipeline-dup-before-out")
      (let* ((writer (%process-test-sbcl-command-node
                      "(progn (write-string \"OUT\") (finish-output) (write-string \"ERR\" *error-output*) (finish-output *error-output*))"))
             (counter (%process-test-sbcl-command-node
                       "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
             (exit nil)
             (output (capture-standard-output
                       (setf exit
                             (nshell.infrastructure.acl:spawn-pipeline
                              (list writer counter)
                              :redirects (list (list (cons :2>&1 nil)
                                                     (cons :> target))
                                               nil))))))
        (expect 0 :to-equal exit)
        (expect (format nil "3~%") :to-equal output)
        (expect "OUT" :to-equal (host-kit:read-file-string target)))))

  (it "spawn-pipeline-stdout-redirect-before-dup-merges-stderr-into-file"
    "A stdout redirect before 2>&1 merges stderr into the redirected stdout file."
    (with-temporary-output-file (target :prefix "nshell-pipeline-out-before-dup")
      (let* ((writer (%process-test-sbcl-command-node
                      "(progn (write-string \"OUT\") (finish-output) (write-string \"ERR\" *error-output*) (finish-output *error-output*))"))
             (counter (%process-test-sbcl-command-node
                       "(let ((count 0)) (loop for ch = (read-char *standard-input* nil nil) while ch do (incf count)) (format t \"~d~%\" count))"))
             (exit nil)
             (output (capture-standard-output
                       (setf exit
                             (nshell.infrastructure.acl:spawn-pipeline
                              (list writer counter)
                              :redirects (list (list (cons :> target)
                                                     (cons :2>&1 nil))
                                               nil))))))
        (expect 0 :to-equal exit)
        (expect (format nil "0~%") :to-equal output)
        (expect "OUTERR" :to-equal (host-kit:read-file-string target)))))

  (it "spawn-pipeline-preserves-arbitrary-fd-dup-order"
    "A child wrapper keeps fd 3 on the original stdout when stdout is redirected later."
    (with-temporary-output-file (target :prefix "nshell-pipeline-arbitrary-fd-dup")
      (let* ((writer
               (nshell.domain.parsing:make-command-node
                "sh"
                (list "-c" "printf out; printf fd3 >&3")))
             (exit nil)
             (output
               (capture-standard-output
                 (setf exit
                       (nshell.infrastructure.acl:spawn-pipeline
                        (list writer)
                        :redirects
                        (list
                         (list
                          (cons :fd-dup
                                (nshell.domain.parsing:make-redirect-fd-dup-target
                                 3
                                 1))
                          (cons :> target))))))))
        (expect 0 :to-equal exit)
        (expect "fd3" :to-equal output)
        (expect "out" :to-equal (host-kit:read-file-string target)))))

  (it "spawn-pipeline-duplicates-arbitrary-input-fd"
    "A child wrapper duplicates stdin onto an arbitrary input descriptor."
    (let* ((reader
             (nshell.domain.parsing:make-command-node
              "sh"
              (list "-c"
                    "IFS= read -r value <&3; printf '%s' \"$value\"")))
           (exit nil)
           (output nil))
      (setf output
            (capture-standard-output
              (setf exit
                    (nshell.infrastructure.acl:spawn-pipeline
                     (list reader)
                     :redirects
                     (list
                      (list
                       (cons :<<< "from-fd")
                       (cons :fd-dup
                             (nshell.domain.parsing:make-redirect-fd-dup-target
                              3
                              0
                              :input))))))))
      (expect 0 :to-equal exit)
      (expect "from-fd" :to-equal output)))

  (it "spawn-pipeline-closes-arbitrary-fd"
    "A child wrapper can close an arbitrary descriptor before command execution."
    (let* ((writer
             (nshell.domain.parsing:make-command-node
              "sh"
              (list "-c" "printf blocked >&3")))
           (exit nil)
           (output nil))
      (setf output
            (capture-standard-output
              (setf exit
                    (nshell.infrastructure.acl:spawn-pipeline
                     (list writer)
                     :redirects
                     (list
                      (list
                       (cons :fd-dup
                             (nshell.domain.parsing:make-redirect-fd-dup-target
                              3
                              :close))
                       (cons :2> "/dev/null")))))))
      (expect (and exit (not (zerop exit))) :to-be-truthy)
      (expect "" :to-equal output)))

  (it "spawn-pipeline-supports-pipefail"
    "pipefail returns the first non-zero source-stage status while the default returns the last stage status."
    (let* ((failed (%process-test-sbcl-command-node "(sb-ext:exit :code 7)"))
           (succeeded (%process-test-sbcl-command-node "(sb-ext:exit :code 0)"))
           (pipefail-status
             (nshell.infrastructure.acl:spawn-pipeline
              (list failed succeeded)
              :pipefail-p t))
           (last-stage-status
             (nshell.infrastructure.acl:spawn-pipeline
              (list failed succeeded))))
      (expect 7 :to-equal pipefail-status)
      (expect 0 :to-equal last-stage-status)))

  (it "spawn-pipeline-cleans-up-started-processes-after-spawn-failure"
    "A later stage spawn failure should not block on output from already-started stages."
    (let* ((sleeper (%process-test-sbcl-command-node "(sleep 30)"))
           (missing (nshell.domain.parsing:make-command-node
                     "definitely-not-a-real-command-nshell-pipeline"
                     nil))
           (start (get-internal-real-time))
           (exit (nshell.infrastructure.acl:spawn-pipeline
                  (list sleeper missing)))
           (elapsed (/ (- (get-internal-real-time) start)
                        internal-time-units-per-second)))
      (expect 127 :to-equal exit)
      (expect elapsed :to-be-less-than 2.0)))

  (it "spawn-pipeline-async-cleans-up-started-processes-after-spawn-failure"
    "A later async stage spawn failure should terminate already-started stages."
    (let* ((sleeper (%process-test-sbcl-command-node "(sleep 30)"))
           (missing (nshell.domain.parsing:make-command-node
                     "definitely-not-a-real-command-nshell-pipeline"
                     nil))
           (start (get-internal-real-time))
           (procs (nshell.infrastructure.acl:spawn-pipeline-async
                   (list sleeper missing)))
           (elapsed (/ (- (get-internal-real-time) start)
                       internal-time-units-per-second)))
      (expect procs :to-be-null)
      (expect elapsed :to-be-less-than 2.0)))

  (it "spawn-process-substitution-preserves-fd-for-consumer"
    "An input process substitution exposes a live inherited fd path to a consumer."
    (let* ((producer (%process-test-sbcl-command-node
                      "(write-string \"input-ok\")"))
           (resource (nshell.infrastructure.acl:spawn-process-substitution
                      :input
                      (list producer)))
           (path (nshell.infrastructure.acl:process-substitution-resource-path
                  resource))
           (output nil)
           (exit nil))
      (unwind-protect
           (progn
             (expect (or (search "/dev/fd/" path)
                         (search "/proc/self/fd/" path))
                     :to-be-truthy)
             (setf output
                   (capture-standard-output
                     (setf exit
                           (nshell.infrastructure.acl:spawn-pipeline
                            (list (nshell.domain.parsing:make-command-node
                                   "cat"
                                   (list path)))
                            :preserve-fds
                            (list
                             (nshell.infrastructure.acl:process-substitution-resource-fd
                              resource))))))
             (expect 0 :to-equal exit)
             (expect "input-ok" :to-equal output)
             (expect 0 :to-equal
                     (nshell.infrastructure.acl:wait-process-substitution
                      resource)))
        (nshell.infrastructure.acl:close-process-substitution resource)))))

  (it "spawn-output-process-substitution-preserves-fd-for-producer"
    "An output process substitution exposes a live inherited fd path to a producer."
    (with-temporary-output-file (output-path :prefix "nshell-process-substitution-output")
      (let* ((consumer (%process-test-sbcl-command-node
                        "(write-line (read-line))"))
             (resource (nshell.infrastructure.acl:spawn-process-substitution
                        :output
                        (list consumer)
                        :redirects
                        (list (list (cons :> output-path)))))
             (path (nshell.infrastructure.acl:process-substitution-resource-path
                    resource))
             (producer (%process-test-sbcl-command-node
                        (format nil
                                "(with-open-file (out ~S :direction :output :if-exists :overwrite) (write-string \"output-ok\" out))"
                                path)))
             (exit nil))
        (unwind-protect
             (progn
               (expect (or (search "/dev/fd/" path)
                           (search "/proc/self/fd/" path))
                       :to-be-truthy)
               (setf exit
                     (nshell.infrastructure.acl:spawn-pipeline
                      (list producer)
                      :preserve-fds
                      (list
                       (nshell.infrastructure.acl:process-substitution-resource-fd
                        resource))))
               (nshell.infrastructure.acl:release-process-substitution-fd resource)
               (expect 0 :to-equal exit)
               (expect 0 :to-equal
                       (nshell.infrastructure.acl:wait-process-substitution
                        resource))
               (expect (format nil "output-ok~%") :to-equal
                       (host-kit:read-file-string output-path)))
          (nshell.infrastructure.acl:close-process-substitution resource)))))

  (it "spawn-process-substitution-rejects-invalid-direction"
    "Process substitution accepts only input and output directions."
            (expect (lambda ()
              (nshell.infrastructure.acl:spawn-process-substitution
               :invalid nil))
            :to-throw 'error))

  (it "run-external-capture-registers-the-child-for-sigint-forwarding"
    "While RUN-EXTERNAL-CAPTURE waits, the child's pgid is registered as
*FOREGROUND-PGID* so SHELL-SIGINT-HANDLER's forwarding reaches it, and the
registration is cleared once the wait ends.

Pre-fix, RUN-EXTERNAL-CAPTURE ran through the one-shot PROCESS-KIT:RUN with no
pgid registration: *FOREGROUND-PGID* stayed 0 for the whole wait, so the plusp
poll below never succeeds, the forwarded SIGINT is a no-op, and the exit code
is 0 (a full 10-second sleep) rather than 130."
    (let* ((captured nil)
           (worker (sb-thread:make-thread
                    (lambda ()
                      (setf captured
                            (multiple-value-list
                             (nshell.infrastructure.acl:run-external-capture
                              "/bin/sleep" (list "10")))))
                    :name "run-external-capture sigint test")))
      ;; The cleanup must run even when an assertion unwinds: the worker
      ;; writes the raw *FOREGROUND-PGID* global (not a thread-local
      ;; binding), so leaking it past this test would let a background
      ;; thread mutate state other tests read.
      (unwind-protect
           (progn
             (loop repeat 100
                   until (plusp nshell.infrastructure.acl::*foreground-pgid*)
                   do (sleep 0.05))
             (expect (plusp nshell.infrastructure.acl::*foreground-pgid*)
                     :to-be-truthy)
             (nshell.infrastructure.acl::%signal-foreground-process-group
              sb-unix:sigint)
             (sb-thread:join-thread worker)
             (expect 130 :to-equal (second captured))
             (expect 0 :to-equal nshell.infrastructure.acl::*foreground-pgid*))
        (when (sb-thread:thread-alive-p worker)
          (ignore-errors
           (nshell.infrastructure.acl::%signal-foreground-process-group
            sb-unix:sigint))
          (ignore-errors (sb-thread:join-thread worker :timeout 15)))
        (setf nshell.infrastructure.acl::*foreground-pgid* 0))))
