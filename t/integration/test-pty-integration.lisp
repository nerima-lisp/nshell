(in-package #:nshell/test)

(defun pty-test-read-available (fd &key (timeout-usec 500000) (limit 4096))
  (let ((buffer (make-array limit :element-type '(unsigned-byte 8))))
    (sb-alien:with-alien ((read-fds (sb-alien:struct sb-unix:fd-set)))
      (sb-unix:fd-zero (sb-alien:addr read-fds))
      (sb-unix:fd-set fd (sb-alien:addr read-fds))
      (multiple-value-bind (ready errno)
          (sb-unix:unix-fast-select (1+ fd) (sb-alien:addr read-fds) nil nil 0 timeout-usec)
        (declare (ignore errno))
        (when (and ready (plusp ready) (sb-unix:fd-isset fd (sb-alien:addr read-fds)))
          (let ((count (ignore-errors
                         (nshell.infrastructure.acl:pty-read fd buffer limit))))
            (when (and count (plusp count))
              (octets->string buffer count))))))))

(defun pty-test-read-until (fd needle &key (attempts 20) (sleep-seconds 0.05))
  (let ((output ""))
    (dotimes (i attempts output)
      (let ((chunk (pty-test-read-available fd)))
        (when chunk
          (setf output (concatenate 'string output chunk))
          (when (search needle output :test #'char-equal)
            (return output)))
        (unless chunk
          (sleep sleep-seconds))))))

(defun pty-test-close-process (pty)
  (when pty
    (ignore-errors
      (nshell.infrastructure.acl:kill-process
       (- (nshell.infrastructure.acl:pty-process-pgid pty)) :sigcont))
    (ignore-errors
      (nshell.infrastructure.acl:kill-process
       (- (nshell.infrastructure.acl:pty-process-pgid pty)) :sigterm))
    (ignore-errors (close (nshell.infrastructure.acl:pty-process-stream pty)))))

(defun pty-test-wait-for-state (pid states &key (attempts 40) (untraced t))
  (loop repeat attempts
        for status = (multiple-value-list
                      (nshell.infrastructure.acl:wait-job
                       pid
                       :untraced untraced
                       :nohang t))
        when (member (second status) states)
          do (return status)
        do (sleep 0.05)))

(defmacro with-readiness-pipe ((read-fd write-fd) &body body)
  `(multiple-value-bind (,read-fd ,write-fd) (sb-posix:pipe)
     (unwind-protect
          (progn ,@body)
       (nshell.infrastructure.acl::%pty-close-fd ,read-fd)
       (nshell.infrastructure.acl::%pty-close-fd ,write-fd))))

(describe "pty-readiness-protocol"
  (it "validates PTY spawn input before opening resources"
    (expect (nshell.infrastructure.acl::%validate-pty-spawn-input
             "/bin/sh" '("-c" "true") 24 80)
            :to-be-truthy)
    (expect (lambda ()
              (nshell.infrastructure.acl::%validate-pty-spawn-input
               nil '() 24 80))
            :to-throw 'type-error)
    (expect (lambda ()
              (nshell.infrastructure.acl::%validate-pty-spawn-input
               "/bin/sh" '("-c" 1) 24 80))
            :to-throw 'error)
    (expect (lambda ()
              (nshell.infrastructure.acl::%validate-pty-spawn-input
               "/bin/sh" '() 0 80))
            :to-throw 'error))

  (it "reports invalid terminal setup descriptors"
    "Terminal setup failures remain visible at the child boundary."
    (expect (lambda ()
              (nshell.infrastructure.acl::%claim-controlling-terminal -1 1))
            :to-throw 'error)
    (expect (lambda ()
              (nshell.infrastructure.acl::%redirect-pty-slave -1))
            :to-throw 'error))

  (it "encodes argv and environment entries as a null-terminated vector"
    "The exec boundary receives stable C strings and a trailing null pointer."
    (let ((vector (nshell.infrastructure.acl::%make-c-string-vector
                   '("program" "--flag"))))
      (unwind-protect
           (progn
             (expect "program" :to-equal (sb-alien:deref vector 0))
             (expect "--flag" :to-equal (sb-alien:deref vector 1))
             (expect nil :to-equal (sb-alien:deref vector 2)))
        (nshell.infrastructure.acl::%free-c-string-vector vector))))

  (it "releases an absent C string vector during partial setup cleanup"
    "Failure cleanup is idempotent when allocation did not complete."
    (expect (nshell.infrastructure.acl::%free-c-string-vector nil)
            :to-be-null))

  (it "round-trips the child readiness byte through a pipe"
    "The parent/child synchronization byte is a strict one-byte protocol."
    (with-readiness-pipe (read-fd write-fd)
      (expect t :to-equal
              (nshell.infrastructure.acl::%pty-write-ready-byte
               write-fd
               nshell.infrastructure.acl::+pty-child-ready-ok+))
      (expect nshell.infrastructure.acl::+pty-child-ready-ok+
              :to-equal
              (nshell.infrastructure.acl::%pty-read-ready-byte read-fd))))

  (it "signals readiness and closes the writer in one operation"
    "Child setup owns the notification descriptor after publishing its state."
    (with-readiness-pipe (read-fd write-fd)
      (nshell.infrastructure.acl::%signal-pty-child-ready
       write-fd
       nshell.infrastructure.acl::+pty-child-ready-ok+)
      (setf write-fd nil)
      (expect nshell.infrastructure.acl::+pty-child-ready-ok+
              :to-equal
              (nshell.infrastructure.acl::%pty-read-ready-byte read-fd))
      (expect (lambda ()
                (nshell.infrastructure.acl::%pty-read-ready-byte read-fd))
              :to-throw 'error)))

  (it "accepts nil when closing an optional file descriptor"
    "Cleanup paths may receive no descriptor after a partial PTY setup."
    (expect (nshell.infrastructure.acl::%pty-close-fd nil)
            :to-be-null))

  (it "rejects a readiness pipe that closes before sending a byte"
    "The parent must distinguish an incomplete child setup from success."
    (with-readiness-pipe (read-fd write-fd)
      (nshell.infrastructure.acl::%pty-close-fd write-fd)
      (setf write-fd nil)
      (expect (lambda ()
                (nshell.infrastructure.acl::%pty-read-ready-byte read-fd))
              :to-throw 'error)))

  (it "rejects a readiness read when the descriptor is invalid"
    "A syscall failure must remain distinct from an orderly pipe close."
    (expect (lambda ()
              (nshell.infrastructure.acl::%pty-read-ready-byte -1))
            :to-throw 'error))

  (it "rejects a readiness byte that reports child setup failure"
    "The parent propagates the child-side setup failure as an error."
    (with-readiness-pipe (read-fd write-fd)
      (expect t :to-equal
              (nshell.infrastructure.acl::%pty-write-ready-byte
               write-fd
               nshell.infrastructure.acl::+pty-child-ready-error+))
      (expect (lambda ()
                (nshell.infrastructure.acl::%wait-for-pty-child-ready
                 read-fd
                 -1))
              :to-throw 'error)))

)

(describe "pty-low-level-io"
  (it "reports failed reads and writes"
    (let ((buffer (make-array 1 :element-type '(unsigned-byte 8))))
      (expect (lambda ()
                (nshell.infrastructure.acl:pty-read -1 buffer 1))
              :to-throw 'error)
      (expect (lambda ()
                (nshell.infrastructure.acl:pty-write -1 buffer))
              :to-throw 'error)))

  (it "accepts absent descriptors during pair cleanup"
    (expect (nshell.infrastructure.acl:pty-close nil nil)
            :to-be-truthy)
    (expect (nshell.infrastructure.acl:pty-close -1 -1)
            :to-be-truthy)))

(describe "pty-foreground-integration-tests"
  (it "pty-spawn-creates-process-with-master-fd"
    "PTY-SPAWN starts a subprocess and exposes its PTY master fd."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "requires a usable PTY"
    (let ((pty nil))
      (unwind-protect
           (progn
             (setf pty (nshell.infrastructure.acl:pty-spawn "/bin/sh" '("-c" "echo pty-ready")))
             (expect (nshell.infrastructure.acl:pty-process-p pty) :to-be-truthy)
             (expect (plusp (nshell.infrastructure.acl:pty-process-pid pty)) :to-be-truthy)
             (expect (integerp (nshell.infrastructure.acl:pty-process-master-fd pty)) :to-be-truthy)
             (expect (search "pty-ready"
                         (pty-test-read-until
                          (nshell.infrastructure.acl:pty-process-master-fd pty)
                          "pty-ready")) :to-be-truthy))
        (pty-test-close-process pty))))

  (it "pty-spawn-cleans-up-when-child-exec-fails"
    "A failed exec is reported after the PTY descriptors and child are cleaned up."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "requires a usable PTY"
      (expect (lambda ()
                (nshell.infrastructure.acl:pty-spawn
                 "/definitely/not-an-nshell-program" '()))
              :to-throw 'error)))

  (it "pty-basic-io-roundtrip-through-cat"
    "PTY master can drive an interactive child with bidirectional I/O."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "requires /bin/cat"
    (let ((pty nil))
      (unwind-protect
           (progn
             (setf pty (nshell.infrastructure.acl:pty-spawn "/bin/cat" '()))
             (nshell.infrastructure.acl:pty-write
              (nshell.infrastructure.acl:pty-process-master-fd pty)
              (string->octets (line "hello-from-pty")))
             (expect (search "hello-from-pty"
                         (pty-test-read-until
                          (nshell.infrastructure.acl:pty-process-master-fd pty)
                          "hello-from-pty")) :to-be-truthy))
        (pty-test-close-process pty)))))

  (it "pty-spawn-propagates-window-size"
    "PTY-SPAWN propagates rows/cols to the child terminal."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "requires external stty/sleep"
    (let ((pty nil))
      (unwind-protect
           (progn
             (setf pty (nshell.infrastructure.acl:pty-spawn
                        "/bin/sh" '("-c" "sleep 0.1; stty size")
                        :rows 37 :cols 123))
             (expect (search "37 123"
                         (pty-test-read-until
                          (nshell.infrastructure.acl:pty-process-master-fd pty)
                          "37 123")) :to-be-truthy))
        (pty-test-close-process pty)))))

  (it "pty-foreground-suspend-resume"
    "A stopped PTY foreground process can be continued and observed to exit."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "requires a usable PTY"
    (let ((pty nil))
      (unwind-protect
           (progn
             (setf pty (nshell.infrastructure.acl:pty-spawn
                        "/bin/sh" '("-c" "kill -STOP $$; echo resumed")))
             (loop repeat 20
                   for status = (multiple-value-list
                                 (nshell.infrastructure.acl:wait-job
                                  (nshell.infrastructure.acl:pty-process-pid pty)
                                  :untraced t
                                  :nohang t))
                   when (eq (second status) :stopped)
                     do (return)
                   do (sleep 0.05))
             (nshell.infrastructure.acl:kill-process
              (- (nshell.infrastructure.acl:pty-process-pgid pty)) :sigcont)
             (expect (search "resumed"
                         (pty-test-read-until
                          (nshell.infrastructure.acl:pty-process-master-fd pty)
                          "resumed")) :to-be-truthy)
             (loop repeat 20
                   for status = (multiple-value-list
                                 (nshell.infrastructure.acl:wait-job
                                  (nshell.infrastructure.acl:pty-process-pid pty)
                                  :nohang t))
                   when (member (second status) '(:exited :signaled :no-child))
                     do (return)
                   do (sleep 0.05)))
        (pty-test-close-process pty)))))

  (it "pty-spawn-delivers-terminal-generated-sigint"
    "PTY-SPAWN delivers master-written ETX as SIGINT to the foreground process group."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "requires /bin/sh"
    (let ((pty nil))
      (unwind-protect
           (progn
             (setf pty (nshell.infrastructure.acl:pty-spawn
                        "/bin/sh"
                        '("-c" "trap 'echo got-int; exit 42' INT; echo ready; while :; do sleep 1; done")))
             (expect (search "ready"
                         (pty-test-read-until
                          (nshell.infrastructure.acl:pty-process-master-fd pty)
                          "ready")) :to-be-truthy)
             (nshell.infrastructure.acl:pty-write
              (nshell.infrastructure.acl:pty-process-master-fd pty)
              (string (code-char 3)))
             (expect (search "got-int"
                         (pty-test-read-until
                          (nshell.infrastructure.acl:pty-process-master-fd pty)
                          "got-int")) :to-be-truthy)
             (let ((status (pty-test-wait-for-state
                            (nshell.infrastructure.acl:pty-process-pid pty)
                            '(:exited))))
               (expect (null status) :to-be-falsy)
               (expect (second status) :to-be :exited)
               (expect (third status) :to-equal 42)))
        (pty-test-close-process pty)))))

  (it "pty-spawn-delivers-terminal-generated-sigtstp"
    "PTY-SPAWN delivers master-written SUB as SIGTSTP to the foreground process group."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "requires /bin/sh"
    (let ((pty nil))
      (unwind-protect
           (progn
             (setf pty (nshell.infrastructure.acl:pty-spawn
                        "/bin/sh"
                        '("-c" "trap 'echo got-tstp; kill -STOP $$' TSTP; echo ready; while :; do sleep 1; done")))
             (expect (search "ready"
                         (pty-test-read-until
                          (nshell.infrastructure.acl:pty-process-master-fd pty)
                          "ready")) :to-be-truthy)
             (nshell.infrastructure.acl:pty-write
              (nshell.infrastructure.acl:pty-process-master-fd pty)
              (string (code-char 26)))
             (expect (search "got-tstp"
                         (pty-test-read-until
                          (nshell.infrastructure.acl:pty-process-master-fd pty)
                          "got-tstp")) :to-be-truthy)
             (let ((status (pty-test-wait-for-state
                            (nshell.infrastructure.acl:pty-process-pid pty)
                            '(:stopped))))
               (expect (null status) :to-be-falsy)
               (expect (second status) :to-be :stopped)))
        (pty-test-close-process pty))))))
)
