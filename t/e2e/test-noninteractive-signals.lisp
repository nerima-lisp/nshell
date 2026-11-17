(in-package #:nshell/test)

(defvar *noninteractive-signal-source-root* nil)

(defun %signal-e2e-wait (predicate description &optional (seconds 30))
  (let ((deadline (+ (get-internal-real-time)
                     (* seconds internal-time-units-per-second))))
    (loop
      (when (funcall predicate) (return t))
      (when (>= (get-internal-real-time) deadline)
        (error "Timed out waiting for ~A" description))
      (sleep 0.02))))

(defun %signal-e2e-read (path)
  (if (probe-file path) (uiop:read-file-string path) ""))

(defun %signal-e2e-pids (path)
  (loop for line in (uiop:split-string (%signal-e2e-read path)
                                      :separator '(#\Newline))
        unless (zerop (length line))
          collect (parse-integer line)))

(defun %signal-e2e-group-gone-p (pgid)
  (handler-case
      (progn (sb-posix:kill (- pgid) 0) nil)
    (sb-posix:syscall-error (condition)
      (if (= sb-posix:esrch (sb-posix:syscall-errno condition))
          t
          (error condition)))))

(defun %signal-e2e-open-fifo-writer (path)
  "Open the FIFO at PATH for writing without blocking and return the file
descriptor, or NIL when no process has it open for reading (ENXIO)."
  (handler-case (sb-posix:open path (logior sb-posix:o-wronly sb-posix:o-nonblock))
    (sb-posix:syscall-error (condition)
      (if (= sb-posix:enxio (sb-posix:syscall-errno condition))
          nil
          (error condition)))))

(defun %signal-e2e-clean-groups (directory)
  (dolist (file (directory (merge-pathnames "*.pids" directory)))
    (let ((pgid (first (%signal-e2e-pids file))))
      (when pgid
        (assert (and (> pgid 1)
                     (/= pgid (sb-posix:getpid))
                     (/= pgid (sb-posix:getpgrp))))
        (ignore-errors (sb-posix:kill (- pgid) sb-unix:sigkill))))))

(defun %signal-e2e-fixture (directory name &key ignore-term-p quiet-p)
  (let ((script (merge-pathnames (format nil "~A.sh" name) directory))
        (pids (merge-pathnames (format nil "~A.pids" name) directory))
        (trap-file (merge-pathnames (format nil "~A.trap" name) directory)))
    (with-open-file (out script :direction :output :if-exists :supersede)
      (if ignore-term-p
          (format out "trap '' TERM~%")
          (format out "trap 'printf TERM > ~A; exit 0' TERM~%"
                  (namestring trap-file)))
      (format out "trap 'printf HUP > ~A; exit 0' HUP~%"
              (namestring trap-file))
      ;; QUIET-P for a background job: --json does not capture what a
      ;; background job writes, which reaches nshell's own stdout.
      (unless quiet-p
        (format out "printf 'partial\\n'~%"))
      (format out "sleep 30 &~%printf '%s\\n%s\\n' \"$$\" \"$!\" > ~A~%wait~%"
              (namestring pids)))
    (values (format nil "sh ~A" (namestring script)) pids trap-file)))

(defun %signal-e2e-environment (directory agent-p)
  (let* ((overrides
           (append
            (list "NSHELL_AI_COMMAND=/nonexistent"
                  (format nil "HOME=~Ahome" directory)
                  (format nil "XDG_CONFIG_HOME=~Aconfig" directory)
                  (format nil "XDG_DATA_HOME=~Adata" directory)
                  (format nil "XDG_STATE_HOME=~Astate" directory)
                  (format nil "XDG_CACHE_HOME=~Acache" directory))
            (when agent-p (list "NSHELL_AGENT=1"))))
         (names (mapcar (lambda (entry) (subseq entry 0 (position #\= entry)))
                        overrides)))
    (append overrides
            (remove-if
             (lambda (entry)
               (member (subseq entry 0 (position #\= entry))
                       (cons "NSHELL_AGENT" names) :test #'string=))
             (%e2e-child-environment)))))

(defun %signal-e2e-run (directory arguments ready-files signal
                         &key input agent-p second-signal ready-p)
  "Run nshell with ARGUMENTS in DIRECTORY, send it SIGNAL once every file in
READY-FILES has content and, with READY-P, once that function of no
arguments returns true, and return its stdout, stderr and exit status."
  (let* ((root (or *noninteractive-signal-source-root*
                   (asdf:system-source-directory :nshell)))
         (stdout (merge-pathnames "stdout" directory))
         (stderr (merge-pathnames "stderr" directory))
         (source-file (merge-pathnames "loaded-source" directory))
         (stdin (merge-pathnames "stdin" directory))
         (program nil)
         (bootstrap
           (format nil
                   "(progn
                      (let ((*standard-output* (make-broadcast-stream))
                            (*error-output* (make-broadcast-stream))
                            (*trace-output* (make-broadcast-stream)))
                        (asdf:load-system :nshell))
                      (with-open-file (out ~S :direction :output)
                        (write-line (namestring (asdf:system-source-directory :nshell)) out))
                      (let ((sb-ext:*posix-argv* (list ~{~S~^ ~})))
                        (funcall (find-symbol ~S ~S))))"
                   (namestring source-file)
                   (cons "nshell" (append '("--no-config" "--no-history") arguments))
                   "MAIN" "NSHELL")))
    (dolist (name '("home/" "config/" "data/" "state/" "cache/"))
      (ensure-directories-exist (merge-pathnames name directory)))
    (with-open-file (out stdin :direction :output)
      (when input (write-string input out)))
    (unwind-protect
         (progn
           (setf program
                 (sb-ext:run-program
                  (%absolute-sbcl-executable)
                  (append '("--noinform" "--disable-debugger")
                          (%asdf-bootstrap-forms (namestring root))
                          (list "--eval" bootstrap))
                  :wait nil :directory directory
                  :input stdin :output stdout :error stderr
                  :environment (%signal-e2e-environment directory agent-p)))
           (%signal-e2e-wait
            (lambda ()
              (and (probe-file source-file)
                   (every (lambda (path)
                            (and (probe-file path)
                                 (plusp (length (%signal-e2e-read path)))))
                          ready-files)
                   (or (not ready-p) (funcall ready-p))))
            "the command readiness files")
           (expect (truename (string-trim '(#\Newline)
                                         (%signal-e2e-read source-file)))
                   :to-equal (truename root))
           (sb-posix:kill (sb-ext:process-pid program) signal)
           (when second-signal
             (sleep 0.2)
             (sb-posix:kill (sb-ext:process-pid program) second-signal))
           (%signal-e2e-wait
            (lambda () (not (sb-ext:process-alive-p program)))
            "the interrupted nshell to exit" 10)
           (sb-ext:process-wait program)
           (values (%signal-e2e-read stdout)
                   (%signal-e2e-read stderr)
                   (sb-ext:process-exit-code program)))
      (when (and program (sb-ext:process-alive-p program))
        (sb-ext:process-kill program sb-unix:sigkill)
        (sb-ext:process-wait program))
      (when program (sb-ext:process-close program)))))

(defun %signal-e2e-expect-envelope (stdout stderr status signal-name)
  (expect status :to-equal 130)
  (expect stderr :to-equal "")
  (expect (count #\Newline stdout) :to-equal 1)
  (let ((envelope (json-kit:parse stdout)))
    (expect (machine-envelope-failures envelope) :to-be-null)
    (expect (json-at envelope "ok") :to-be json-kit:+json-false+)
    (expect (json-at envelope "status") :to-equal 130)
    (expect (json-at envelope "error" "code") :to-equal "E_INTERRUPTED")
    (expect (json-at envelope "error" "message")
            :to-equal (format nil "the run was interrupted by ~A" signal-name))
    envelope))

(defun %signal-e2e-expect-gone (pids-file)
  (let ((pids (%signal-e2e-pids pids-file)))
    (expect (length pids) :to-equal 2)
    (%signal-e2e-wait (lambda () (%signal-e2e-group-gone-p (first pids)))
                      "the interrupted process group to disappear" 3)
    (expect (json-wait-until-dead pids 1) :to-be-null)))

(describe "noninteractive signal e2e"
  (it "bug4-json-signals-stop-descendants-and-return-one-envelope"
    (let ((agent-p nil))
      (dolist (signal (list (list sb-unix:sigint "SIGINT")
                           (list sb-unix:sigterm "SIGTERM")
                           (list sb-unix:sighup "SIGHUP")))
        (host-kit:with-temporary-directory (directory)
          (unwind-protect
               (multiple-value-bind (command pids trap-file)
                   (%signal-e2e-fixture directory "child")
                 (multiple-value-bind (stdout stderr status)
                     (%signal-e2e-run
                      directory (list "--json" "--command" command)
                      (list pids) (first signal) :agent-p agent-p)
                   (%signal-e2e-expect-envelope stdout stderr status (second signal))
                   (expect (%signal-e2e-read trap-file) :to-equal "TERM")
                   (%signal-e2e-expect-gone pids)))
            (%signal-e2e-clean-groups directory))))))

  (it "bug4-agent-json-signals-stop-the-child-and-return-one-envelope"
    ;; NSHELL_AGENT=1 refuses sh, whose script it cannot check, so the child
    ;; is cat reading a FIFO, which classifies :safe and blocks. The test
    ;; holds the FIFO's write end open, so cat waits in read; a FIFO opened
    ;; for writing without blocking fails with ENXIO once no process has it
    ;; open for reading, which shows that cat is gone.
    (dolist (signal (list (list sb-unix:sigint "SIGINT")
                         (list sb-unix:sigterm "SIGTERM")
                         (list sb-unix:sighup "SIGHUP")))
      (host-kit:with-temporary-directory (directory)
        (let ((fifo (namestring (merge-pathnames "fifo" directory)))
              (writer nil))
          (sb-posix:mkfifo fifo #o600)
          (unwind-protect
               (multiple-value-bind (stdout stderr status)
                   (%signal-e2e-run directory
                                    (list "--json" "--command" (format nil "cat ~A" fifo))
                                    nil (first signal)
                                    :agent-p t
                                    :ready-p (lambda ()
                                               (setf writer (%signal-e2e-open-fifo-writer fifo))))
                 (let ((envelope (%signal-e2e-expect-envelope stdout stderr status
                                                              (second signal))))
                   (expect (json-at envelope "safety" "level") :to-equal "safe"))
                 (%signal-e2e-wait (lambda ()
                                     (let ((probe (%signal-e2e-open-fifo-writer fifo)))
                                       (when probe (sb-posix:close probe))
                                       (null probe)))
                                   "the interrupted cat to close the FIFO" 3))
            (when writer (sb-posix:close writer)))))))

  (it "bug4-json-preserves-partial-output-and-stops-background-groups"
    (host-kit:with-temporary-directory (directory)
      (unwind-protect
           (multiple-value-bind (foreground foreground-pids)
               (%signal-e2e-fixture directory "foreground")
             (multiple-value-bind (background background-pids)
                 (%signal-e2e-fixture directory "background" :quiet-p t)
               (multiple-value-bind (stdout stderr status)
                   (%signal-e2e-run
                    directory
                    (list "--json" "--command"
                          (format nil "~A & ~A" background foreground))
                    (list foreground-pids background-pids) sb-unix:sigterm)
                 (let ((envelope (%signal-e2e-expect-envelope stdout stderr status "SIGTERM")))
                   (expect (search "partial" (json-at envelope "stdout" "text"))
                           :to-be-truthy))
                 (%signal-e2e-expect-gone foreground-pids)
                 (%signal-e2e-expect-gone background-pids))))
        (%signal-e2e-clean-groups directory))))

  (it "bug4-json-sigint-keeps-the-output-of-earlier-commands"
    (host-kit:with-temporary-directory (directory)
      (unwind-protect
           (multiple-value-bind (command pids)
               (%signal-e2e-fixture directory "child" :quiet-p t)
             (multiple-value-bind (stdout stderr status)
                 (%signal-e2e-run directory
                                  (list "--json" "--command"
                                        (format nil "echo early; ~A" command))
                                  (list pids) sb-unix:sigint)
               (let ((envelope (%signal-e2e-expect-envelope stdout stderr status "SIGINT")))
                 (expect (json-at envelope "stdout" "text") :to-equal (format nil "early~%")))
               (%signal-e2e-expect-gone pids)))
        (%signal-e2e-clean-groups directory))))

  (it "bug4-json-continues-a-stopped-child-so-its-sigterm-trap-runs"
    ;; A stopped process acts on SIGTERM only once continued; without SIGCONT
    ;; the SIGKILL that follows removes it before its trap can run.
    (host-kit:with-temporary-directory (directory)
      (let* ((script (merge-pathnames "stopped.sh" directory))
             (pids (merge-pathnames "stopped.pids" directory))
             (trap-file (merge-pathnames "stopped.trap" directory))
             (resumed (merge-pathnames "stopped.resumed" directory))
             (pid nil))
        (unwind-protect
             (progn
               (with-open-file (out script :direction :output)
                 ;; RESUMED appears only if the shell goes on past its own
                 ;; SIGSTOP before the test stops it.
                 (format out "trap 'printf TERM > ~A; exit 0' TERM~%~
                              printf '%s\\n' \"$$\" > ~A~%kill -STOP $$~%~
                              printf resumed > ~A~%sleep 30~%"
                         (namestring trap-file) (namestring pids)
                         (namestring resumed)))
               (multiple-value-bind (stdout stderr status)
                   (%signal-e2e-run
                    directory (list "--json" "--command" (format nil "sh ~A" (namestring script)))
                    (list pids) sb-unix:sigint
                    :ready-p (lambda ()
                               ;; Without ps (the Nix build sandbox has none),
                               ;; the stop shows as the shell not reaching the
                               ;; line after kill -STOP within half a second.
                               (setf pid (first (%signal-e2e-pids pids)))
                               (sleep 0.5)
                               (expect (probe-file resumed) :to-be-null)
                               t))
                 (%signal-e2e-expect-envelope stdout stderr status "SIGINT"))
               (expect (%signal-e2e-read trap-file) :to-equal "TERM")
               (%signal-e2e-wait (lambda () (%signal-e2e-group-gone-p pid))
                                 "the stopped process group to disappear" 3))
          (%signal-e2e-clean-groups directory)))))

  (it "bug4-json-repeated-signals-do-not-interrupt-cleanup"
    (host-kit:with-temporary-directory (directory)
      (unwind-protect
           (multiple-value-bind (command pids)
               (%signal-e2e-fixture directory "child" :ignore-term-p t)
             (multiple-value-bind (stdout stderr status)
                 (%signal-e2e-run directory (list "--json" "--command" command)
                                  (list pids) sb-unix:sigint
                                  :second-signal sb-unix:sigterm)
               (%signal-e2e-expect-envelope stdout stderr status "SIGINT")
               (%signal-e2e-expect-gone pids)))
        (%signal-e2e-clean-groups directory))))

  (it "bug4-json-interrupts-lisp-without-an-external-process"
    (host-kit:with-temporary-directory (directory)
      (let* ((ready (merge-pathnames "lisp-ready" directory))
             (input (format nil
                            "(progn (with-open-file (out ~S :DIRECTION :OUTPUT) (write-line ~S out)) (loop))"
                            (namestring ready) "ready")))
        (multiple-value-bind (stdout stderr status)
            (%signal-e2e-run directory (list "--json" "--command" input)
                             (list ready) sb-unix:sigint)
          (%signal-e2e-expect-envelope stdout stderr status "SIGINT")))))

  (it "bug4-batch-entry-points-report-signal-status-without-crash-logs"
    (dolist (mode '(:command :stdin :script :agent))
      (dolist (signal (list (list sb-unix:sigint 130 "SIGINT")
                           (list sb-unix:sigterm 143 "SIGTERM")
                           (list sb-unix:sighup 129 "SIGHUP")))
        (host-kit:with-temporary-directory (directory)
          (unwind-protect
               (multiple-value-bind (command pids)
                   (%signal-e2e-fixture directory "child")
                 (let ((script (merge-pathnames "run.nsh" directory)))
                   (with-open-file (out script :direction :output)
                     (format out "echo before~%~A~%echo after~%" command))
                   (multiple-value-bind (stdout stderr status)
                       (%signal-e2e-run
                        directory
                        (case mode
                          ((:command :agent) (list "--command" command))
                          (:stdin nil)
                          (:script (list (namestring script))))
                        (list pids) (first signal)
                        :input (when (eq mode :stdin) (format nil "~A~%" command))
                        :agent-p (eq mode :agent))
                     (expect status :to-equal (second signal))
                     (expect stderr :to-equal
                             (format nil "nshell: interrupted by ~A~%" (third signal)))
                     (expect (search "partial" stdout) :to-be-truthy)
                     (when (eq mode :script)
                       (expect (search "before" stdout) :to-be-truthy)
                       (expect (search "after" stdout) :to-be-null))
                     (expect (directory (merge-pathnames "state/nshell/crash/*" directory))
                             :to-be-null)
                     (%signal-e2e-expect-gone pids))))
            (%signal-e2e-clean-groups directory))))))

  (it "bug4-batch-sighup-reaches-background-jobs-only-on-hangup"
    (dolist (signal (list sb-unix:sighup sb-unix:sigint sb-unix:sigterm))
      (host-kit:with-temporary-directory (directory)
        (unwind-protect
             (multiple-value-bind (foreground foreground-pids)
                 (%signal-e2e-fixture directory "foreground")
               (multiple-value-bind (background background-pids trap-file)
                   (%signal-e2e-fixture directory "background")
                 (%signal-e2e-run
                  directory
                  (list "--command" (format nil "~A & ~A" background foreground))
                  (list foreground-pids background-pids) signal)
                 (%signal-e2e-expect-gone foreground-pids)
                 (if (= signal sb-unix:sighup)
                     (progn
                       (%signal-e2e-wait
                        (lambda () (string= "HUP" (%signal-e2e-read trap-file)))
                        "the background SIGHUP trap" 3)
                       (expect (%signal-e2e-read trap-file) :to-equal "HUP"))
                     (progn
                       (expect (probe-file trap-file) :to-be-null)
                       (expect (json-pid-alive-p (first (%signal-e2e-pids background-pids)))
                               :to-be-truthy)))))
          (%signal-e2e-clean-groups directory))))))
