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
  (it "spawn-pipeline-timeout-covers-orphaned-output-writer"
    (with-temporary-output-file (pid-file :prefix "nshell-pipeline-orphan")
      (let ((worker nil) (result nil) (failure nil) (joined nil))
        (unwind-protect
             (progn
               (setf worker
                     (sb-thread:make-thread
                      (lambda ()
                        (handler-case
                            (let ((nshell.infrastructure.acl:*external-command-timeout* 0.2))
                              (capture-standard-output
                                (setf result
                                      (nshell.infrastructure.acl:spawn-pipeline
                                       (list (nshell.domain.parsing:make-command-node
                                              "true" nil)
                                             (nshell.domain.parsing:make-command-node
                                              "/bin/sh"
                                              (list "-c" "sleep 30 & printf '%s' \"$!\" > \"$1\""
                                                    "nshell-test" pid-file)))))))
                          (error (condition) (setf failure condition))))))
               (setf joined (sb-thread:join-thread worker :timeout 3 :default :deadline))
               (expect nil :to-equal failure)
               (expect (eq :deadline joined) :to-be-null)
               (expect 124 :to-equal result))
          (let ((pid (ignore-errors
                       (parse-integer (host-kit:read-file-string pid-file)))))
            (when pid (ignore-errors (sb-posix:kill pid sb-unix:sigkill))))
          (when worker
            (sb-thread:join-thread worker :timeout 3 :default nil))))))

  (it "spawn-pipeline-captures-stderr-duplicated-before-stdout-file"
    (with-temporary-output-file (target :prefix "nshell-pipeline-stderr-snapshot")
      (let ((status nil))
        (expect "ERR" :to-equal
                (capture-standard-output
                  (setf status
                        (nshell.infrastructure.acl:spawn-pipeline
                         (list (nshell.domain.parsing:make-command-node
                                "/bin/sh" '("-c" "printf OUT; printf ERR >&2")))
                         :redirects (list (list (cons :2>&1 nil) (cons :> target)))))))
        (expect 0 :to-equal status)
        (expect "OUT" :to-equal (host-kit:read-file-string target)))))

  (it "spawn-pipeline-reaped-leader-still-terminates-descendants"
    (let ((processes nil) (child-pid nil))
      (unwind-protect
           (progn
             (setf processes
                   (nshell.infrastructure.acl:spawn-pipeline-async
                    (list (nshell.domain.parsing:make-command-node "true" nil)
                          (nshell.domain.parsing:make-command-node
                           "/bin/sh"
                           '("-c" "sleep 30 & printf '%s\\n' \"$!\"; wait")))
                    :default-output :stream))
             (expect 2 :to-equal (length processes))
             (setf child-pid
                   (parse-integer (read-line (sb-ext:process-output (second processes)))))
             (sb-ext:process-wait (first processes))
             (expect :exited :to-equal (sb-ext:process-status (first processes)))
             (expect (ignore-errors (sb-posix:getpgid
                                     (sb-ext:process-pid (first processes))))
                     :to-be-null)
             (nshell.infrastructure.acl::%terminate-pipeline-processes (reverse processes))
             (loop repeat 100
                   while (ignore-errors (sb-posix:kill child-pid 0) t)
                   do (sleep 0.01))
             (expect (ignore-errors (sb-posix:kill child-pid 0) t) :to-be-null))
        (when child-pid (ignore-errors (sb-posix:kill child-pid sb-unix:sigkill)))
        (nshell.infrastructure.acl::%abort-pipeline (reverse processes) nil))))

  (it "spawn-pipeline-redirect-dup-snapshots-earlier-output"
    (dolist (combined-p '(nil t))
      (with-temporary-output-file (first-target :prefix "nshell-pipeline-snapshot-first")
        (with-temporary-output-file (last-target :prefix "nshell-pipeline-snapshot-last")
          (expect 0 :to-equal
                  (nshell.infrastructure.acl:spawn-pipeline
                   (list (nshell.domain.parsing:make-command-node
                          "/bin/sh" '("-c" "printf OUT; printf ERR >&2")))
                   :redirects
                   (list (append (list (cons (if combined-p :&> :>) first-target))
                                 (unless combined-p (list (cons :2>&1 nil)))
                                 (list (cons :> last-target))))))
          (expect "ERR" :to-equal (host-kit:read-file-string first-target))
          (expect "OUT" :to-equal (host-kit:read-file-string last-target))))))

  (it "spawn-pipeline-closes-streams-after-command-resolution-error"
    (with-temporary-output-file (target :prefix "nshell-pipeline-resolution-error")
      (let ((open-output
              (symbol-function 'nshell.infrastructure.acl::%open-pipeline-output-redirect))
            (opened nil))
        (with-rebound-function
            (nshell.infrastructure.acl::%open-pipeline-output-redirect
             (lambda (&rest arguments)
               (multiple-value-bind (stream streams) (apply open-output arguments)
                 (push stream opened)
                 (values stream streams))))
          (with-rebound-function
              (nshell.infrastructure.acl::%resolve-external-command
               (lambda (&rest arguments)
                 (declare (ignore arguments))
                 (error "injected command resolution failure")))
            (expect 127 :to-equal
                    (nshell.infrastructure.acl:spawn-pipeline
                     (list (nshell.domain.parsing:make-command-node "true" nil))
                     :redirects (list (list (cons :> target))))))
          (expect 1 :to-equal (length opened))
          (unwind-protect
               (expect nil :to-equal (open-stream-p (first opened)))
            (close (first opened)))))))

  (it "spawn-pipeline-internal-fd-wrapper-survives-empty-shell-path"
    (let ((nshell.infrastructure.acl::*exported-environment* '("PATH="))
          (status nil))
      (expect "fd3" :to-equal
              (capture-standard-output
                (setf status
                      (nshell.infrastructure.acl:spawn-pipeline
                       (list (nshell.domain.parsing:make-command-node
                              "/bin/sh" '("-c" "printf fd3 >&3")))
                       :redirects
                       (list (list (cons :fd-dup
                                         (nshell.domain.parsing:make-redirect-fd-dup-target
                                          3 1))))))))
      (expect 0 :to-equal status)))

  (it "spawn-pipeline-closes-redirect-stream-after-later-open-fails"
    (with-temporary-output-file (target :prefix "nshell-pipeline-partial-redirect")
      (let ((open-output
              (symbol-function 'nshell.infrastructure.acl::%open-pipeline-output-redirect))
            (opened nil))
        (with-rebound-function
            (nshell.infrastructure.acl::%open-pipeline-output-redirect
             (lambda (&rest arguments)
               (when opened (error "injected second redirect failure"))
               (multiple-value-bind (stream streams) (apply open-output arguments)
                 (push stream opened)
                 (values stream streams))))
          (expect 127 :to-equal
                  (nshell.infrastructure.acl:spawn-pipeline
                   (list (nshell.domain.parsing:make-command-node "true" nil))
                   :redirects (list (list (cons :> target) (cons :2> target)))))
          (expect 1 :to-equal (length opened))
          (expect nil :to-equal (open-stream-p (first opened)))))))

  (it "spawn-pipeline-cleans-real-partial-launch-and-pipe-descriptors"
    (dolist (async-p '(nil t))
      (let ((spawn (symbol-function 'nshell.infrastructure.acl::%run-pipeline-command))
            (make-pipes (symbol-function 'nshell.infrastructure.acl::%make-pipeline-pipes))
            (processes nil)
            (descriptors nil))
        (with-rebound-function
            (nshell.infrastructure.acl::%make-pipeline-pipes
             (lambda (count)
               (let ((pipes (funcall make-pipes count)))
                 (setf descriptors (loop for pair in pipes append (copy-list pair)))
                 pipes)))
          (with-rebound-function
              (nshell.infrastructure.acl::%run-pipeline-command
               (lambda (&rest arguments)
                 (when processes (error "injected second-stage failure"))
                 (let ((process (apply spawn arguments)))
                   (push process processes)
                   process)))
            (expect (if async-p nil 127) :to-equal
                    (funcall (if async-p
                                 #'nshell.infrastructure.acl:spawn-pipeline-async
                                 #'nshell.infrastructure.acl:spawn-pipeline)
                             (loop repeat 3 collect
                               (nshell.domain.parsing:make-command-node "true" nil)))))
          (expect 1 :to-equal (length processes))
          (expect :signaled :to-equal (sb-ext:process-status (first processes)))
          (expect 4 :to-equal (length descriptors))
          (dolist (fd descriptors)
            (expect sb-posix:ebadf :to-equal
                    (handler-case (sb-posix:fcntl fd sb-posix:f-getfd)
                      (sb-posix:syscall-error (err)
                        (sb-posix:syscall-errno err)))))))))

  (it "spawn-pipeline-cleans-stages-on-callback-nonlocal-exit"
    (let ((spawn (symbol-function 'nshell.infrastructure.acl::%run-pipeline-command))
          (processes nil))
      (with-rebound-function
          (nshell.infrastructure.acl::%run-pipeline-command
           (lambda (&rest arguments)
             (let ((process (apply spawn arguments)))
               (push process processes)
               process)))
        (expect :escaped :to-equal
                (catch 'pipeline-escape
                  (nshell.infrastructure.acl:spawn-pipeline
                   (loop repeat 2 collect
                     (nshell.domain.parsing:make-command-node "true" nil))
                   :after-spawn (lambda () (throw 'pipeline-escape :escaped)))))
        (expect 2 :to-equal (length processes))
        (expect t :to-equal
                (every (lambda (process)
                         (eq :signaled (sb-ext:process-status process))) processes)))))

  (it "spawn-pipeline-internal-helper-survives-shell-path-change"
    (let ((nshell.infrastructure.acl::*exported-environment* '("PATH=/bin:/usr/bin"))
          (status nil))
      (expect (format nil "helper-path~%") :to-equal
              (capture-standard-output
                (setf status
                      (nshell.infrastructure.acl:spawn-pipeline
                       (list (nshell.domain.parsing:make-command-node
                              "echo" '("helper-path"))
                             (nshell.domain.parsing:make-command-node "cat" nil))))))
      (expect 0 :to-equal status)))

  (it "spawn-pipeline-holds-all-stages-in-one-group-before-release"
    (dolist (async-p '(nil t))
      (let ((spawn (symbol-function 'nshell.infrastructure.acl::%run-pipeline-command))
            (processes nil)
            (observed nil))
        (with-rebound-function
            (nshell.infrastructure.acl::%run-pipeline-command
             (lambda (&rest arguments)
               (let ((process (apply spawn arguments)))
                 (when process (push process processes))
                 process)))
          (let ((result
                  (funcall (if async-p
                               #'nshell.infrastructure.acl:spawn-pipeline-async
                               #'nshell.infrastructure.acl:spawn-pipeline)
                           (loop repeat 3 collect
                             (nshell.domain.parsing:make-command-node "true" nil))
                           :after-spawn
                           (lambda ()
                             (setf observed
                                   (mapcar (lambda (process)
                                             (list (sb-ext:process-status process)
                                                   (sb-posix:getpgid
                                                    (sb-ext:process-pid process))))
                                           processes))))))
            (when async-p
              (dolist (process result) (sb-ext:process-wait process)))
            (expect 3 :to-equal (length processes))
            (expect (make-list 3 :initial-element
                               (list :stopped
                                     (sb-ext:process-pid (car (last processes)))))
                    :to-equal observed)
            (expect '(0 0 0) :to-equal
                    (mapcar #'nshell.infrastructure.acl:process-exit-status-code
                            processes)))))))

  (it "spawn-pipeline-aborts-real-stages-when-after-spawn-fails"
    (dolist (async-p '(nil t))
      (let ((spawn (symbol-function 'nshell.infrastructure.acl::%run-pipeline-command))
            (processes nil)
            (outputs nil))
        (with-rebound-function
            (nshell.infrastructure.acl::%run-pipeline-command
             (lambda (&rest arguments)
               (let ((process (apply spawn arguments)))
                 (when process (push process processes))
                 (when (sb-ext:process-output process)
                   (push (sb-ext:process-output process) outputs))
                 process)))
          (let ((result
                  (funcall (if async-p
                               #'nshell.infrastructure.acl:spawn-pipeline-async
                               #'nshell.infrastructure.acl:spawn-pipeline)
                           (loop repeat 2 collect
                             (nshell.domain.parsing:make-command-node "true" nil))
                           :default-output :stream
                           :after-spawn (lambda () (error "injected launch failure")))))
            (expect (if async-p nil 127) :to-equal result)
            (expect 2 :to-equal (length processes))
            (expect nil :to-equal (some #'sb-ext:process-alive-p processes))
            (expect 1 :to-equal (length outputs))
            (expect nil :to-equal (some #'open-stream-p outputs))
            (expect t :to-equal
                    (every (lambda (process)
                             (eq :signaled (sb-ext:process-status process)))
                           processes)))))))

  (it "foreground-external-command-timeout-is-nil-by-default-for-noninteractive-output"
    "With *EXTERNAL-COMMAND-TIMEOUT* left at its production default (now NIL),
%FOREGROUND-EXTERNAL-COMMAND-TIMEOUT must return NIL even when
*STANDARD-OUTPUT* is not an interactive terminal -- pre-fix the default was
30, so this same non-interactive check would have returned 30 (a truthy,
enforced timeout) instead."
    (let ((*standard-output* (make-string-output-stream)))
      (expect (nshell.infrastructure.acl::%foreground-external-command-timeout)
              :to-be nil)))

  (it "foreground-process-group-macro-runs-body-without-a-pgid"
    "The foreground-group wrapper preserves execution when no group is available."
    (let ((ran nil))
      (nshell.infrastructure.acl::%with-foreground-process-group-if (nil)
        (setf ran t))
      (expect t :to-equal ran)))

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
                                "trap \"\" TERM; sleep 30 & echo $! > \"$1\"; wait"
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
    ;; PATH-resolved "sleep" (coreutils), not "/bin/sleep": the Nix build
    ;; sandbox has no /bin beyond sh, so the absolute path resolves to
    ;; command-not-found (127) there and the pgid is never registered -- the
    ;; same reason the sibling tests use PATH-resolved "echo" and "sh". A
    ;; plain external sleeper also dies BY the forwarded SIGINT (130), where
    ;; an SBCL child would catch it and exit 1.
    (let* ((captured nil)
           (worker (sb-thread:make-thread
                    (lambda ()
                      (setf captured
                            (multiple-value-list
                             (nshell.infrastructure.acl:run-external-capture
                              "sleep" (list "10")))))
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
