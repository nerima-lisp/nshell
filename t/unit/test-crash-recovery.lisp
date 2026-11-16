;;; Tests for recovery from unexpected errors and crash logs (task P0-4,
;;; design decisions D-50 and D-51).
(in-package #:nshell/test)

(defmacro with-crash-test-environment ((&rest bindings) &body body)
  "Run BODY with the process environment variables in BINDINGS, a list of
(NAME VALUE) forms, set (VALUE NIL unsets NAME); restore them afterwards."
  (let ((saved (loop repeat (length bindings) collect (gensym "SAVED-"))))
    `(let ,(loop for (name) in bindings
                 for variable in saved
                 collect `(,variable (host-kit:getenv ,name)))
       (unwind-protect
            (progn
              ,@(loop for (name value) in bindings
                      collect `(let ((value ,value))
                                 (if value
                                     (sb-posix:setenv ,name value 1)
                                     (sb-posix:unsetenv ,name))))
              ,@body)
         ,@(loop for (name) in bindings
                 for variable in saved
                 collect `(if ,variable
                              (sb-posix:setenv ,name ,variable 1)
                              (sb-posix:unsetenv ,name)))))))

(defmacro with-crash-state-home ((state-home) &body body)
  "Bind STATE-HOME to a new temporary directory, with a trailing slash, and run
BODY with XDG_STATE_HOME set to it."
  (let ((root (gensym "ROOT-")))
    `(host-kit:with-temporary-directory (,root)
       (let ((,state-home (namestring (uiop:ensure-directory-pathname ,root))))
         (with-crash-test-environment (("XDG_STATE_HOME" ,state-home))
           ,@body)))))

(defmacro with-crashing-builtin ((name condition-form) &body body)
  "Run BODY with a test-only builtin NAME that signals CONDITION-FORM with
ERROR. It exists only in the isolated registry WITH-STUBBED-COMMAND-BUILTIN
binds, so no production command line can reach it."
  `(with-stubbed-command-builtin ((,name (error ,condition-form)))
     ,@body))

(defun %crash-log-files (state-home)
  (directory (merge-pathnames "nshell/crash/*.log" state-home)))

(defun %crash-file-mode (path)
  (logand #o777 (sb-posix:stat-mode (sb-posix:stat (namestring path)))))

(defun %read-crash-log (path)
  (uiop:read-file-string path))

(defun %crash-record-for (condition frame-names)
  (nshell.infrastructure.persistence::%make-crash-record
   :condition condition :frame-names frame-names :frame-arguments nil))

(describe "crash-recovery-repl-iteration"
  (it "a-crashing-command-returns-to-the-prompt-and-logs-under-xdg-state-home"
    (with-crash-state-home (state-home)
      (with-repl-test-state
        (with-crashing-builtin ("p04-crash" "p04 unit failure")
          (let* ((continuation nil)
                 (output (capture-standard-output
                           (setf continuation
                                 (nshell.presentation::%execute-command-line
                                  "p04-crash")))))
            (expect (functionp continuation) :to-be-truthy)
            (expect (search "nshell error: p04 unit failure" output) :to-be-truthy)
            (expect (search "nshell: crash log: " output) :to-be-truthy)
            (expect (search "Backtrace" output) :to-be-null)
            (expect 1 :to-equal nshell.presentation::*last-exit-code*)
            (expect t :to-equal nshell.presentation::*running*)
            (let ((logs (%crash-log-files state-home)))
              (expect 1 :to-equal (length logs))
              (expect (namestring
                       (truename (format nil "~anshell/crash/" state-home)))
                      :to-equal
                      (namestring (make-pathname :name nil :type nil
                                                 :defaults (first logs))))
              (let ((text (%read-crash-log (first logs))))
                (expect (search "condition: COMMON-LISP:SIMPLE-ERROR" text)
                        :to-be-truthy)
                (expect (search "p04 unit failure" text) :to-be-truthy)
                (expect (search "backtrace:" text) :to-be-truthy)))
            (let ((recovery (capture-standard-output
                              (nshell.presentation::%execute-command-line
                               "echo P04_AFTER"))))
              (expect (search "P04_AFTER" recovery) :to-be-truthy)))))))

  (it "the-crash-log-directory-falls-back-to-local-state-under-home"
    (expect "/home/p04/.local/state/nshell/crash/"
            :to-equal (nshell.domain.crash:crash-log-directory nil "/home/p04"))
    (expect "/home/p04/.local/state/nshell/crash/"
            :to-equal (nshell.domain.crash:crash-log-directory "" "/home/p04/"))
    (expect "/home/p04/.local/state/nshell/crash/"
            :to-equal (nshell.domain.crash:crash-log-directory "relative/state"
                                                               "/home/p04"))
    (expect "/xdg/state/nshell/crash/"
            :to-equal (nshell.domain.crash:crash-log-directory "/xdg/state/"
                                                               "/home/p04")))

  (it "an-unset-xdg-state-home-writes-the-log-under-home"
    (host-kit:with-temporary-directory (root)
      (let ((home (string-right-trim
                   "/" (namestring (uiop:ensure-directory-pathname root)))))
        (with-crash-test-environment (("XDG_STATE_HOME" nil) ("HOME" home))
          (let ((shown (nshell.infrastructure.persistence:write-crash-report
                        (%crash-record-for (make-condition 'simple-error
                                                           :format-control "x"
                                                           :format-arguments nil)
                                           nil))))
            (expect (search "~/.local/state/nshell/crash/" shown) :to-be-truthy)
            (expect 1 :to-equal
                    (length (directory
                             (format nil "~a/.local/state/nshell/crash/*.log"
                                     home)))))))))

  (it "an-input-processing-crash-preserves-input-and-logs"
    (with-crash-state-home (state-home)
      (with-repl-test-state
        (let ((nshell.presentation::*input-state*
                (nshell.presentation::make-repl-input-state
                 :buffer "echo P04" :cursor-pos 8)))
          (with-temporary-functions
              (('nshell.presentation::reduce-input-state
                (lambda (state event)
                  (declare (ignore state event))
                  (error "p04 reducer failure")))
               ('nshell.presentation::render-prompt-cont (lambda () nil)))
            (let ((output (capture-standard-output
                            (nshell.presentation::%process-input-event
                             (nshell.domain.input:make-key-event :ctrl-f)))))
              (expect (search "input processing failed; input was preserved" output)
                      :to-be-truthy)
              (expect (search "nshell: crash log: " output) :to-be-truthy)
              (expect "echo P04" :to-equal
                      (nshell.presentation:input-state-buffer
                       nshell.presentation::*input-state*))
              (expect 1 :to-equal (length (%crash-log-files state-home)))))))))

  (it "a-crashing-trampoline-step-is-logged-and-redraws-the-prompt"
    (with-crash-state-home (state-home)
      (with-repl-test-state
        (let* ((continuation nil)
               (output (capture-standard-output
                         (setf continuation
                               (nshell.presentation::%call-repl-step-with-crash-recovery
                                (lambda () (error "p04 step failure")))))))
          (expect (functionp continuation) :to-be-truthy)
          (expect (search "nshell error: p04 step failure" output) :to-be-truthy)
          (expect 1 :to-equal (length (%crash-log-files state-home)))))))

  (it "terminal-mode-failures-and-interrupts-are-not-treated-as-crashes"
    (with-crash-state-home (state-home)
      (expect (lambda ()
                (nshell.presentation::%call-repl-step-with-crash-recovery
                 (lambda ()
                   (error 'nshell.infrastructure.terminal:terminal-mode-operation-failed
                          :operation "tcsetattr" :fd 0 :reason "test"))))
              :to-throw 'nshell.infrastructure.terminal:terminal-mode-operation-failed)
      (let ((on-crash-called-p nil))
        (expect :propagated
                :to-equal
                (handler-case
                    (nshell.presentation::call-with-crash-capture
                     (lambda ()
                       (error (make-condition 'sb-sys:interactive-interrupt)))
                     (lambda (crash)
                       (declare (ignore crash))
                       (setf on-crash-called-p t)))
                  (sb-sys:interactive-interrupt () :propagated)))
        (expect on-crash-called-p :to-be-falsy))
      (expect nil :to-equal (%crash-log-files state-home))))

  (it "every-later-trampoline-step-is-guarded"
    (with-crash-state-home (state-home)
      (with-repl-test-state
        (let ((calls nil))
          (with-temporary-function
              ('nshell.presentation::render-prompt-cont
               (lambda ()
                 (push :render calls)
                 nshell.presentation::+repl-exit+))
            (capture-standard-output
              (expect nshell.presentation::+repl-exit+
                      :to-equal
                      (nshell.presentation:trampoline
                       (nshell.presentation::%guard-repl-continuation
                        (lambda ()
                          (push :first calls)
                          (lambda ()
                            (push :second calls)
                            (error "p04 second step"))))))))
          (expect '(:first :second :render) :to-equal (reverse calls))
          (expect 1 :to-equal (length (%crash-log-files state-home))))))))

(describe "crash-recovery-log-files"
  (it "the-directory-is-0700-and-the-file-0600-even-under-a-restrictive-umask"
    (with-crash-state-home (state-home)
      (let ((previous (sb-posix:umask #o277)))
        (unwind-protect
             (nshell.infrastructure.persistence:write-crash-report
              (%crash-record-for (make-condition 'simple-error
                                                 :format-control "mode"
                                                 :format-arguments nil)
                                 nil))
          (sb-posix:umask previous)))
      (expect #o700 :to-equal (%crash-file-mode
                               (format nil "~anshell" state-home)))
      (expect #o700 :to-equal (%crash-file-mode
                               (format nil "~anshell/crash" state-home)))
      (let ((logs (%crash-log-files state-home)))
        (expect 1 :to-equal (length logs))
        (expect #o600 :to-equal (%crash-file-mode (first logs))))))

  (it "an-existing-crash-directory-is-tightened-to-0700"
    (with-crash-state-home (state-home)
      (let ((directory (format nil "~anshell/crash/" state-home)))
        (ensure-directories-exist directory)
        (sb-posix:chmod (string-right-trim "/" directory) #o755)
        (nshell.infrastructure.persistence:write-crash-report
         (%crash-record-for (make-condition 'simple-error
                                            :format-control "mode"
                                            :format-arguments nil)
                            nil))
        (expect #o700 :to-equal (%crash-file-mode
                                 (string-right-trim "/" directory))))))

  (it "log-names-are-utc-timestamps-and-a-taken-name-gets-a-suffix"
    (expect "19700101T000000.000000Z.log"
            :to-equal (nshell.domain.crash:crash-log-file-name 0 0))
    (expect "20261116T081530.000042Z-2.log"
            :to-equal (nshell.domain.crash:crash-log-file-name 1794816930 42 2))
    (expect "2026-11-16T08:15:30.000042Z"
            :to-equal (nshell.domain.crash:crash-time-string 1794816930 42))
    (host-kit:with-temporary-directory (root)
      (let* ((directory (namestring (uiop:ensure-directory-pathname root)))
             (taken (concatenate 'string directory
                                 "19700101T000000.000000Z.log")))
        (with-open-file (stream taken :direction :output)
          (write-string "earlier crash" stream))
        (multiple-value-bind (fd path)
            (nshell.infrastructure.persistence::%open-new-crash-log directory 0 0)
          (sb-posix:close fd)
          (expect (concatenate 'string directory "19700101T000000.000000Z-1.log")
                  :to-equal path))
        (expect "earlier crash" :to-equal (uiop:read-file-string taken)))))

  (it "home-becomes-tilde-wherever-it-ends-a-path-component"
    (expect "~/src and ~ and (~)"
            :to-equal (nshell.domain.crash:replace-home-directory
                       "/home/p04/src and /home/p04 and (/home/p04)" "/home/p04/"))
    ;; HOME inside a longer value is replaced too (P0-6 review); a longer
    ;; component name such as p04user is not HOME.
    (expect "/home/p04user/x /x~/y prefix~/locale"
            :to-equal (nshell.domain.crash:replace-home-directory
                       "/home/p04user/x /x/home/p04/y prefix/home/p04/locale"
                       "/home/p04"))
    (expect "/etc/passwd"
            :to-equal (nshell.domain.crash:replace-home-directory "/etc/passwd" "/"))
    (expect "/etc/passwd"
            :to-equal (nshell.domain.crash:replace-home-directory "/etc/passwd" ""))
    (expect "/etc/passwd"
            :to-equal (nshell.domain.crash:replace-home-directory "/etc/passwd" nil)))

  (it "the-log-redacts-secrets-and-shows-home-as-tilde"
    (let ((text (nshell.domain.crash:render-crash-log
                 :time "2026-11-16T08:15:30.000042Z"
                 :condition-type 'simple-error
                 :message "token ghp_abcdefghijklmnopqrstuvwxyz0123 in /home/p04/project"
                 :frame-names '(error nshell.application:dispatch-builtin)
                 :frame-arguments '("\"Bearer abcdefghijklmnopqrstuvwx\""
                                    "\"/home/p04/.ssh/id_ed25519\"")
                 :home "/home/p04"
                 :lisp-version "SBCL test")))
      (expect (search "ghp_abcdefghijklmnopqrstuvwxyz0123" text) :to-be-null)
      (expect (search "abcdefghijklmnopqrstuvwx" text) :to-be-null)
      (expect (search "id_ed25519" text) :to-be-null)
      (expect (search "/home/p04" text) :to-be-null)
      (expect (search "token [REDACTED] in ~/project" text) :to-be-truthy)
      (expect (search "Bearer [REDACTED]" text) :to-be-truthy)
      (expect (search "  1: NSHELL.APPLICATION:DISPATCH-BUILTIN" text) :to-be-truthy)
      (expect (search "place: COMMON-LISP:SIMPLE-ERROR in NSHELL.APPLICATION:DISPATCH-BUILTIN"
                      text)
              :to-be-truthy)))

  (it "batch-and-script-crashes-write-logs-but-script-syntax-errors-do-not"
    (with-crash-state-home (state-home)
      (with-repl-test-state
        (with-crashing-builtin ("p04-crash" "p04 batch failure")
          (let ((error-output
                  (with-output-to-string (*error-output*)
                    (let ((*standard-output* (make-broadcast-stream)))
                      (expect 1 :to-equal
                              (nshell.presentation::run-repl-batch
                               :line "p04-crash"))))))
            (expect (search "nshell error: p04 batch failure" error-output)
                    :to-be-truthy)
            (expect (search "nshell: crash log: " error-output) :to-be-truthy))
          (expect 1 :to-equal (length (%crash-log-files state-home)))
          (host-kit:with-temporary-directory (root)
            (let ((script (namestring (merge-pathnames "crash.nsh" root)))
                  (broken (namestring (merge-pathnames "broken.nsh" root))))
              (with-open-file (stream script :direction :output)
                (write-line "p04-crash" stream))
              (with-open-file (stream broken :direction :output)
                (write-line "(echo \"unterminated" stream))
              (let ((*error-output* (make-broadcast-stream))
                    (*standard-output* (make-broadcast-stream)))
                (expect 1 :to-equal
                        (nshell.presentation::run-repl-script script)))
              (expect 2 :to-equal (length (%crash-log-files state-home)))
              (let ((diagnostic
                      (with-output-to-string (*error-output*)
                        (let ((*standard-output* (make-broadcast-stream)))
                          (nshell.presentation::run-repl-script broken)))))
                (expect (search "nshell: crash log" diagnostic) :to-be-null)
                (expect (search "broken.nsh" diagnostic) :to-be-truthy))
              (expect 2 :to-equal (length (%crash-log-files state-home)))))))))

  (it "a-fifo-in-place-of-the-crash-directory-is-reported-without-blocking"
    ;; Opening a FIFO for reading blocks until a writer appears, so the crash
    ;; runs in a thread with a bounded wait: a regression fails, not hangs.
    (with-crash-state-home (state-home)
      (let ((fifo (format nil "~anshell/crash" state-home)))
        (ensure-directories-exist (format nil "~anshell/" state-home))
        (sb-posix:mkfifo fifo #o600)
        (flet ((run-bounded (function)
                 (let ((thread (sb-thread:make-thread function
                                                      :name "p04-fifo-crash")))
                   (multiple-value-bind (result status)
                       (sb-thread:join-thread thread :default :timeout
                                                     :timeout 10)
                     (declare (ignore status))
                     (when (eq result :timeout)
                       ;; Release the blocked reader so the thread can end.
                       (ignore-errors
                         (sb-posix:close
                          (sb-posix:open fifo (logior sb-posix:o-wronly
                                                      sb-posix:o-nonblock))))
                       (ignore-errors (sb-thread:join-thread thread :timeout 5)))
                     result))))
          (let ((interactive
                  (run-bounded
                   (lambda ()
                     (with-repl-test-state
                       (with-crashing-builtin ("p04-crash" "p04 fifo failure")
                         (let* ((continuation nil)
                                (output (capture-standard-output
                                          (setf continuation
                                                (nshell.presentation::%execute-command-line
                                                 "p04-crash")))))
                           (list (functionp continuation)
                                 (not (null (search "nshell: crash log not written: "
                                                    output)))
                                 nshell.presentation::*running*))))))))
            (expect '(t t t) :to-equal interactive))
          (let ((batch
                  (run-bounded
                   (lambda ()
                     (with-repl-test-state
                       (with-crashing-builtin ("p04-crash" "p04 fifo failure")
                         (let* ((status nil)
                                (error-output
                                  (with-output-to-string (*error-output*)
                                    (let ((*standard-output* (make-broadcast-stream)))
                                      (setf status
                                            (nshell.presentation::run-repl-batch
                                             :line "p04-crash"))))))
                           (list status
                                 (not (null (search "nshell: crash log not written: "
                                                    error-output)))))))))))
            (expect '(1 t) :to-equal batch))))))

  (it "a-log-write-failure-is-reported-and-the-repl-continues"
    (host-kit:with-temporary-directory (root)
      (let ((blocker (namestring (merge-pathnames "not-a-directory" root))))
        (with-open-file (stream blocker :direction :output)
          (write-string "x" stream))
        (with-crash-test-environment (("XDG_STATE_HOME" blocker))
          (with-repl-test-state
            (with-crashing-builtin ("p04-crash" "p04 unwritable")
              (let* ((continuation nil)
                     (output (capture-standard-output
                               (setf continuation
                                     (nshell.presentation::%execute-command-line
                                      "p04-crash")))))
                (expect (functionp continuation) :to-be-truthy)
                (expect (search "nshell error: p04 unwritable" output)
                        :to-be-truthy)
                (expect (search "nshell: crash log not written: " output)
                        :to-be-truthy)
                (expect t :to-equal nshell.presentation::*running*)))))))))

(describe "crash-recovery-same-place"
  (it "the-place-is-the-condition-type-and-the-innermost-nshell-frame"
    (expect "COMMON-LISP:SIMPLE-ERROR in NSHELL.APPLICATION:DISPATCH-BUILTIN"
            :to-equal
            (nshell.domain.crash:crash-place
             'simple-error
             '(error nshell.user::p04-user-function
               nshell.application:dispatch-builtin
               nshell.presentation::%execute-command-line)))
    (expect "COMMON-LISP:TYPE-ERROR in (COMMON-LISP:LAMBDA (NSHELL.APPLICATION::X) :IN NSHELL.APPLICATION:DISPATCH-BUILTIN)"
            :to-equal
            (nshell.domain.crash:crash-place
             'type-error
             '(car (lambda (nshell.application::x)
                    :in nshell.application:dispatch-builtin))))
    (expect "COMMON-LISP:SIMPLE-ERROR in no nshell frame"
            :to-equal
            (nshell.domain.crash:crash-place 'simple-error
                                             '(error nshell/test::p04-frame)))
    (expect (nshell.domain.crash:nshell-frame-name-p 'nshell::main) :to-be-truthy)
    (expect (nshell.domain.crash:nshell-frame-name-p "foreign function") :to-be-falsy))

  (it "three-crashes-in-a-row-at-one-place-reach-the-threshold"
    (let* ((first (nshell.domain.crash:crash-streak-advance nil "A"))
           (second (nshell.domain.crash:crash-streak-advance first "A"))
           (third (nshell.domain.crash:crash-streak-advance second "A"))
           (other (nshell.domain.crash:crash-streak-advance second "B")))
      (expect 2 :to-equal (nshell.domain.crash:crash-streak-count second))
      (expect (nshell.domain.crash:crash-streak-repeated-p second) :to-be-falsy)
      (expect 3 :to-equal (nshell.domain.crash:crash-streak-count third))
      (expect (nshell.domain.crash:crash-streak-repeated-p third) :to-be-truthy)
      (expect 1 :to-equal (nshell.domain.crash:crash-streak-count other))))

  (it "the-third-crash-lists-jobs-before-asking-about-a-safe-restart"
    (with-repl-test-state
      (let ((nshell.presentation::*interactive-terminal-installed-p* t)
            (nshell.presentation::*crash-streak* nil)
            (nshell.presentation::*safe-reexec-requested-p* nil)
            (asked 0)
            (crash (%crash-record-for (make-condition 'simple-error
                                                      :format-control "x"
                                                      :format-arguments nil)
                                      '(nshell.application:dispatch-builtin))))
        (with-temporary-functions
            (('nshell.application:jobs
              (lambda (&optional monitor)
                (declare (ignore monitor))
                (list (nshell.application::make-job-listing 1 "Running" "sleep 30"))))
             ('nshell.presentation::%read-safe-reexec-answer
              (lambda () (incf asked) :no)))
          (let ((quiet (capture-standard-output
                         (expect (nshell.presentation::%note-interactive-crash crash)
                                 :to-be-falsy)
                         (expect (nshell.presentation::%note-interactive-crash crash)
                                 :to-be-falsy))))
            (expect 0 :to-equal asked)
            (expect "" :to-equal quiet))
          (let* ((output (capture-standard-output
                           (expect (nshell.presentation::%note-interactive-crash crash)
                                   :to-be-falsy)))
                 (job (search "[1] Running sleep 30" output))
                 (question (search "Restart nshell with --safe?" output)))
            (expect 1 :to-equal asked)
            (expect (search "occurred 3 times in a row (COMMON-LISP:SIMPLE-ERROR in NSHELL.APPLICATION:DISPATCH-BUILTIN)"
                            output)
                    :to-be-truthy)
            (expect (and job question (< job question)) :to-be-truthy)
            (expect nshell.presentation::*crash-streak* :to-be-null)
            (expect nshell.presentation::*safe-reexec-requested-p* :to-be-falsy))))))

  (it "accepting-the-restart-ends-the-session-only-from-the-executable"
    (with-repl-test-state
      (let ((nshell.presentation::*interactive-terminal-installed-p* t)
            (nshell.presentation::*crash-streak* nil)
            (nshell.presentation::*safe-reexec-requested-p* nil)
            (executable nil)
            (crash (%crash-record-for (make-condition 'simple-error
                                                      :format-control "x"
                                                      :format-arguments nil)
                                      '(nshell.application:dispatch-builtin))))
        (with-temporary-functions
            (('nshell.application:jobs (lambda (&optional monitor)
                                         (declare (ignore monitor))
                                         nil))
             ('nshell.presentation::%read-safe-reexec-answer (lambda () :yes))
             ('nshell.infrastructure.acl:current-executable-path
              (lambda () executable)))
          (let ((output (capture-standard-output
                          (dotimes (i 3)
                            (expect (nshell.presentation::%note-interactive-crash crash)
                                    :to-be-falsy)))))
            (expect (search "nshell: no running jobs" output) :to-be-truthy)
            (expect (search "cannot restart" output) :to-be-truthy)
            (expect nshell.presentation::*safe-reexec-requested-p* :to-be-falsy))
          (setf executable "/opt/p04/bin/nshell")
          (capture-standard-output
            (dotimes (i 2)
              (nshell.presentation::%note-interactive-crash crash))
            (expect (nshell.presentation::%note-interactive-crash crash)
                    :to-be-truthy))
          (expect nshell.presentation::*safe-reexec-requested-p* :to-be-truthy)))))

  (it "end-of-input-at-the-question-ends-the-session-without-restarting"
    (with-repl-test-state
      (let ((nshell.presentation::*interactive-terminal-installed-p* t)
            (nshell.presentation::*crash-streak* nil)
            (nshell.presentation::*safe-reexec-requested-p* nil)
            (crash (%crash-record-for (make-condition 'simple-error
                                                      :format-control "x"
                                                      :format-arguments nil)
                                      nil)))
        (with-temporary-functions
            (('nshell.application:jobs (lambda (&optional monitor)
                                         (declare (ignore monitor))
                                         nil))
             ('nshell.presentation::%read-safe-reexec-answer (lambda () :eof)))
          (capture-standard-output
            (dotimes (i 2)
              (nshell.presentation::%note-interactive-crash crash))
            (expect (nshell.presentation::%note-interactive-crash crash)
                    :to-be-truthy))
          (expect nshell.presentation::*safe-reexec-requested-p* :to-be-falsy)))))

  (it "batch-sessions-and-completed-commands-do-not-build-a-streak"
    (with-crash-state-home (state-home)
      (with-repl-test-state
        (with-temporary-function
            ('nshell.presentation::%read-safe-reexec-answer
             (lambda () (error "the question must not be asked")))
          (with-crashing-builtin ("p04-crash" "p04 streak")
            (let ((nshell.presentation::*crash-streak* nil))
              (capture-standard-output
                (dotimes (i 4)
                  (nshell.presentation::%execute-command-line "p04-crash")))
              (expect nshell.presentation::*crash-streak* :to-be-null)
              (let ((nshell.presentation::*interactive-terminal-installed-p* t))
                (capture-standard-output
                  (nshell.presentation::%execute-command-line "p04-crash")
                  (nshell.presentation::%execute-command-line "p04-crash"))
                (expect 2 :to-equal (nshell.domain.crash:crash-streak-count
                                     nshell.presentation::*crash-streak*))
                (capture-standard-output
                  (nshell.presentation::%execute-command-line "true"))
                (expect nshell.presentation::*crash-streak* :to-be-null))))))))

  (it "classified-nshell-diagnostics-write-no-log-and-leave-the-streak-alone"
    (with-crash-state-home (state-home)
      (with-repl-test-state
        (with-temporary-function
            ('nshell.presentation::%read-safe-reexec-answer
             (lambda () (error "the question must not be asked")))
          (with-stubbed-command-builtin
              (("p04-classified"
                (error 'nshell.application:command-argument-type-error
                       :value 42 :source-span nil)))
            (let ((nshell.presentation::*interactive-terminal-installed-p* t)
                  (nshell.presentation::*crash-streak*
                    (cons "COMMON-LISP:SIMPLE-ERROR in NSHELL.APPLICATION:DISPATCH-BUILTIN"
                          2)))
              (let ((output (capture-standard-output
                              (dotimes (i 3)
                                (nshell.presentation::%execute-command-line
                                 "p04-classified")))))
                (expect (search "nshell error: " output) :to-be-truthy)
                (expect (search "crash log" output) :to-be-null))
              (expect 1 :to-equal nshell.presentation::*last-exit-code*)
              (expect (cons "COMMON-LISP:SIMPLE-ERROR in NSHELL.APPLICATION:DISPATCH-BUILTIN"
                            2)
                      :to-equal nshell.presentation::*crash-streak*)
              (let ((error-output
                      (with-output-to-string (*error-output*)
                        (let ((*standard-output* (make-broadcast-stream)))
                          (expect 1 :to-equal
                                  (nshell.presentation::run-repl-batch
                                   :line "p04-classified"))))))
                (expect (search "nshell error: " error-output) :to-be-truthy)
                (expect (search "crash log" error-output) :to-be-null))
              (expect nil :to-equal (%crash-log-files state-home))))))))

  (it "user-lisp-errors-at-the-prompt-write-no-log-and-never-ask"
    (with-crash-state-home (state-home)
      (with-repl-test-state
        (with-temporary-function
            ('nshell.presentation::%read-safe-reexec-answer
             (lambda () (error "the question must not be asked")))
          (let ((nshell.presentation::*interactive-terminal-installed-p* t)
                (nshell.presentation::*crash-streak* nil))
            (let ((output (capture-standard-output
                            (dotimes (i 3)
                              (nshell.presentation::%execute-command-line
                               "(car 1)")))))
              (expect (search "nshell error: The value" output) :to-be-truthy)
              (expect (search "crash log" output) :to-be-null)
              (expect (search "Restart nshell" output) :to-be-null))
            (expect 1 :to-equal nshell.presentation::*last-exit-code*)
            (expect t :to-equal nshell.presentation::*running*)
            (expect nshell.presentation::*crash-streak* :to-be-null)
            (expect nil :to-equal (%crash-log-files state-home)))))))

  (it "a-builtin-failing-under-user-code-is-still-a-crash"
    (with-crash-state-home (state-home)
      (with-repl-test-state
        (with-crashing-builtin ("p04-crash" "p04 builtin under user code")
          (let ((nshell.presentation::*interactive-terminal-installed-p* t)
                (nshell.presentation::*crash-streak* nil))
            (let ((output (capture-standard-output
                            (nshell.presentation::%execute-command-line
                             "(p04-crash)"))))
              (expect (search "nshell error: p04 builtin under user code" output)
                      :to-be-truthy)
              (expect (search "nshell: crash log: " output) :to-be-truthy))
            (expect "COMMON-LISP:SIMPLE-ERROR in NSHELL.APPLICATION:DISPATCH-BUILTIN"
                    :to-equal (car nshell.presentation::*crash-streak*))
            (expect 1 :to-equal (nshell.domain.crash:crash-streak-count
                                 nshell.presentation::*crash-streak*))
            (expect 1 :to-equal (length (%crash-log-files state-home))))))))

  (it "user-lisp-errors-in-batch-and-scripts-exit-1-without-a-log"
    (with-crash-state-home (state-home)
      (with-repl-test-state
        (let ((error-output
                (with-output-to-string (*error-output*)
                  (let ((*standard-output* (make-broadcast-stream)))
                    (expect 1 :to-equal
                            (nshell.presentation::run-repl-batch :line "(car 1)"))))))
          (expect (search "nshell error: The value" error-output) :to-be-truthy)
          (expect (search "crash log" error-output) :to-be-null))
        (host-kit:with-temporary-directory (root)
          (let ((script (namestring (merge-pathnames "user-error.nsh" root))))
            (with-open-file (stream script :direction :output)
              (write-line "(car 1)" stream))
            (let ((error-output
                    (with-output-to-string (*error-output*)
                      (let ((*standard-output* (make-broadcast-stream)))
                        (expect 1 :to-equal
                                (nshell.presentation::run-repl-script script))))))
              (expect (search "crash log" error-output) :to-be-null))))
        (expect nil :to-equal (%crash-log-files state-home)))))

  (it "an-error-the-evaluator-signals-itself-stays-a-crash"
    ;; DOLIST over a non-list is rejected by %EVAL-DOLIST-FORM, an nshell frame
    ;; inside the user-code boundary, so it is logged.
    (with-crash-state-home (state-home)
      (with-repl-test-state
        (let ((output (capture-standard-output
                        (nshell.presentation::%execute-command-line
                         "(dolist (x 1) x)"))))
          (expect (search "nshell: crash log: " output) :to-be-truthy))
        (let ((logs (%crash-log-files state-home)))
          (expect 1 :to-equal (length logs))
          (expect (search "place: COMMON-LISP:TYPE-ERROR in NSHELL.APPLICATION::%EVAL-DOLIST-FORM"
                          (%read-crash-log (first logs)))
                  :to-be-truthy)))))

  (it "the-safe-restart-keeps-compatible-flags-and-execs-the-executable"
    (expect '("--safe" "--private" "-i")
            :to-equal
            (nshell.domain.crash:safe-reexec-arguments
             '("--private" "--config" "/p04/init.lisp" "-i" "--private" "--safe")))
    (let ((exec-call nil))
      (with-temporary-functions
          (('nshell.infrastructure.acl:current-executable-path
            (lambda () "/opt/p04/bin/nshell"))
           ('nshell.infrastructure.acl:current-process-arguments
            (lambda () '("--no-history" "--config" "/p04/init.lisp")))
           ('nshell.infrastructure.acl:exec-program
            (lambda (program arguments)
              (setf exec-call (list program arguments))
              0)))
        (capture-standard-output (nshell.presentation::%reexec-with-safe-mode)))
      (expect '("/opt/p04/bin/nshell" ("--safe" "--no-history"))
              :to-equal exec-call))))

(describe "crash-recovery-storage-conditions"
  (it "storage-conditions-are-captured-without-printing-arguments"
    (let ((storage (nshell.infrastructure.persistence:capture-crash
                    (make-condition 'storage-condition)))
          (ordinary (nshell.infrastructure.persistence:capture-crash
                     (make-condition 'simple-error :format-control "x"
                                                   :format-arguments nil))))
      (expect (nshell.infrastructure.persistence:crash-record-frame-names storage)
              :to-be-truthy)
      (expect (nshell.infrastructure.persistence:crash-record-frame-arguments storage)
              :to-be-null)
      (expect (nshell.infrastructure.persistence:crash-record-frame-arguments ordinary)
              :to-be-truthy)))

  (it "stack-and-heap-exhaustion-take-the-command-crash-path"
    (loop for (condition-type expected-line)
            in '((sb-kernel::control-stack-exhausted
                  "condition: SB-KERNEL::CONTROL-STACK-EXHAUSTED")
                 (sb-kernel::heap-exhausted-error
                  "condition: SB-KERNEL::HEAP-EXHAUSTED-ERROR")
                 (storage-condition
                  "condition: COMMON-LISP:STORAGE-CONDITION"))
          do
      (with-crash-state-home (state-home)
        (with-repl-test-state
          (with-stubbed-command-builtin
              (("p04-exhaust" (error (make-condition condition-type))))
            (let ((output (capture-standard-output
                            (nshell.presentation::%execute-command-line
                             "p04-exhaust"))))
              (expect (search "nshell: storage exhausted" output) :to-be-truthy)
              (expect (search "nshell: crash log: " output) :to-be-truthy)
              (expect t :to-equal nshell.presentation::*running*)
              (let ((logs (%crash-log-files state-home)))
                (expect 1 :to-equal (length logs))
                (expect (search expected-line (%read-crash-log (first logs)))
                        :to-be-truthy)))))))))
