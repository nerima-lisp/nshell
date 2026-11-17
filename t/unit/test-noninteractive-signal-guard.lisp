(in-package #:nshell/test)

;;; BUG-4: CALL-WITH-NONINTERACTIVE-SIGNALS and the stop reason that the
;;; --json deadline, the alternate screen and SIGINT/SIGTERM/SIGHUP share.
;;; No test sends a signal to this process. A delivery is simulated by
;;; calling, from another thread, the Lisp handler the SBCL runtime holds for
;;; the signal, which is what the runtime calls when the signal arrives.

(defun %guard-signal-state (signal)
  (list (nshell.infrastructure.acl::signal-disposition signal)
        (nshell.infrastructure.acl::lisp-signal-handler signal)))

(defun %guard-restore-signal-state (signal state)
  (destructuring-bind (disposition handler) state
    (if (eq disposition :ignore)
        (sb-sys:enable-interrupt signal :ignore)
        (nshell.infrastructure.acl::reinstall-lisp-signal-handler signal handler))))

(defmacro with-guard-signal-states (() &body body)
  "Run BODY and put SIGHUP, SIGINT and SIGTERM back as they were, whatever
BODY changed."
  (let ((states (gensym "STATES")))
    `(let ((,states (mapcar (lambda (signal) (cons signal (%guard-signal-state signal)))
                            (list sb-unix:sighup sb-unix:sigint sb-unix:sigterm))))
       (unwind-protect (progn ,@body)
         (loop for (signal . state) in ,states
               do (%guard-restore-signal-state signal state))))))

(defun %simulate-signal (signal &optional (original nil original-p))
  "Call SIGNAL's installed Lisp handler in a new thread, as the runtime does
when SIGNAL arrives there, and wait for it to return. With ORIGINAL, the
handler in place before the run, deliver nothing when that one is back: it
would act on this test process. Return :DELIVERED or :NOT-DELIVERED."
  (let ((handler (nshell.infrastructure.acl::lisp-signal-handler signal)))
    (if (or (not (functionp handler))
            (and original-p (eq handler original)))
        :not-delivered
        (sb-thread:join-thread
         (sb-thread:make-thread
          (lambda ()
            (funcall handler signal (sb-sys:int-sap 0) (sb-sys:int-sap 0))
            :delivered)
          :name "simulated signal delivery")
         :default nil :timeout 5))))

(defun %simulate-signal-when (predicate signal &key (delay 0) (seconds 10))
  "Start a thread that waits until PREDICATE is true and DELAY seconds more,
then simulates SIGNAL while the handler in place now is not back. Joining
the thread returns :DELIVERED or :NOT-DELIVERED."
  (let ((original (nshell.infrastructure.acl::lisp-signal-handler signal)))
    (sb-thread:make-thread
     (lambda ()
       (let ((deadline (+ (get-internal-real-time)
                          (* seconds internal-time-units-per-second))))
         (loop until (or (funcall predicate)
                         (>= (get-internal-real-time) deadline))
               do (sleep 0.02))
         (if (funcall predicate)
             (progn (sleep delay) (%simulate-signal signal original))
             :not-delivered)))
     :name "simulated signal sender")))

(defun %wait-for-sleep-forever ()
  (loop repeat 500 do (sleep 0.01))
  :not-interrupted)

(describe "noninteractive signal guard"
  (it "keeps the first stop reason, whichever comes first"
    (let ((stop (nshell.infrastructure.acl:make-noninteractive-stop)))
      (expect (nshell.infrastructure.acl:claim-noninteractive-stop stop :timeout)
              :to-be-truthy)
      (expect (nshell.infrastructure.acl:claim-noninteractive-stop stop sb-unix:sigint)
              :to-be-null)
      (expect (nshell.infrastructure.acl:claim-noninteractive-stop
               stop :interactive-program)
              :to-be-null)
      (expect (nshell.infrastructure.acl:noninteractive-stop-reason stop)
              :to-equal :timeout)
      (expect (nshell.infrastructure.acl:noninteractive-stop-signal stop) :to-be-null))
    (let ((stop (nshell.infrastructure.acl:make-noninteractive-stop)))
      (expect (nshell.infrastructure.acl:claim-noninteractive-stop stop sb-unix:sigterm)
              :to-be-truthy)
      (expect (nshell.infrastructure.acl:claim-noninteractive-stop stop :timeout)
              :to-be-null)
      (expect (nshell.infrastructure.acl:noninteractive-stop-signal stop)
              :to-equal sb-unix:sigterm)))

  (it "unwinds the run once and only records the signals after the first"
    (with-guard-signal-states ()
      (let* ((stop (nshell.infrastructure.acl:make-noninteractive-stop))
             (unwinds 0)
             (result
               (nshell.infrastructure.acl:call-with-noninteractive-signals
                stop
                (lambda ()
                  (expect (%simulate-signal sb-unix:sigint) :to-equal :delivered)
                  (%wait-for-sleep-forever))
                :before-unwind (lambda (signal)
                                 (declare (ignore signal))
                                 (incf unwinds))
                :after-signal (lambda (signal)
                                ;; Cleanup goes on through later signals.
                                (%simulate-signal sb-unix:sigterm)
                                (%simulate-signal sb-unix:sighup)
                                (sleep 0.2)
                                (list :cleaned-up signal)))))
        (expect result :to-equal (list :cleaned-up sb-unix:sigint))
        (expect unwinds :to-equal 1)
        (expect (nshell.infrastructure.acl:noninteractive-stop-reason stop)
                :to-equal sb-unix:sigint))))

  (it "lets a reason the run claimed first keep a later signal from unwinding it"
    (with-guard-signal-states ()
      (let* ((stop (nshell.infrastructure.acl:make-noninteractive-stop))
             (result
               (nshell.infrastructure.acl:call-with-noninteractive-signals
                stop
                (lambda ()
                  (nshell.infrastructure.acl:claim-noninteractive-stop stop :timeout)
                  (%simulate-signal sb-unix:sigterm)
                  (sleep 0.2)
                  :finished)
                :after-signal (lambda (signal) (list :interrupted signal)))))
        (expect result :to-equal :finished)
        (expect (nshell.infrastructure.acl:noninteractive-stop-reason stop)
                :to-equal :timeout))))

  (it "restores the handlers it replaced, the same Lisp functions"
    (with-guard-signal-states ()
      ;; Known handlers of this test's own, so a restore to SIG_DFL or to
      ;; whatever another test left cannot pass for the right one.
      (dolist (signal (list sb-unix:sigint sb-unix:sigterm))
        (sb-sys:enable-interrupt signal (lambda (signal info context)
                                          (declare (ignore signal info context)))))
      (let ((before (mapcar #'%guard-signal-state
                            (list sb-unix:sigint sb-unix:sigterm)))
            (inside nil))
        (loop for (nil handler) in before
              do (expect (functionp handler) :to-be-truthy))
        (nshell.infrastructure.acl:call-with-noninteractive-signals
         (nshell.infrastructure.acl:make-noninteractive-stop)
         (lambda ()
           (setf inside (mapcar #'%guard-signal-state
                                (list sb-unix:sigint sb-unix:sigterm)))))
        (loop for (nil inside-handler) in inside
              for (nil before-handler) in before
              do (expect (functionp inside-handler) :to-be-truthy)
                 (expect (eq inside-handler before-handler) :to-be-null))
        (loop for (disposition handler) in before
              for signal in (list sb-unix:sigint sb-unix:sigterm)
              for (after-disposition after-handler) = (%guard-signal-state signal)
              do (expect after-disposition :to-equal disposition)
                 (expect (eq after-handler handler) :to-be-truthy)))))

  (it "leaves a signal that was ignored on entry ignored"
    (with-guard-signal-states ()
      (sb-sys:enable-interrupt sb-unix:sighup :ignore)
      (let ((inside nil))
        (nshell.infrastructure.acl:call-with-noninteractive-signals
         (nshell.infrastructure.acl:make-noninteractive-stop)
         (lambda () (setf inside (%guard-signal-state sb-unix:sighup))))
        (expect inside :to-equal (list :ignore nil))
        (expect (%guard-signal-state sb-unix:sighup) :to-equal (list :ignore nil)))))

  (it "answers a signal during --json with E_INTERRUPTED and the output so far"
    (with-guard-signal-states ()
      (host-kit:with-temporary-directory (directory)
        (let* ((ready (format nil "~Aready" (sb-ext:native-namestring directory)))
               (before (mapcar #'%guard-signal-state
                               (list sb-unix:sighup sb-unix:sigint sb-unix:sigterm)))
               (sender (%simulate-signal-when (lambda () (probe-file ready))
                                              sb-unix:sigint)))
          (multiple-value-bind (envelope status seconds)
              (json-command (format nil "sh -c 'echo partial; : > ~A; sleep 30'" ready)
                            :timeout 20)
            (expect (sb-thread:join-thread sender :default nil :timeout 5) :to-equal :delivered)
            (expect status :to-equal 130)
            (expect (json-at envelope "error" "code") :to-equal "E_INTERRUPTED")
            (expect (json-at envelope "error" "message")
                    :to-equal "the run was interrupted by SIGINT")
            (expect (json-at envelope "stdout" "text") :to-equal (format nil "partial~%"))
            (expect seconds :to-be-less-than 5))
          ;; Restored once RUN-JSON-COMMAND has returned.
          (loop for state in before
                for signal in (list sb-unix:sighup sb-unix:sigint sb-unix:sigterm)
                for (disposition handler) = (%guard-signal-state signal)
                do (expect disposition :to-equal (first state))
                   (expect (eq handler (second state)) :to-be-truthy))))))

  (it "keeps E_TIMEOUT when a signal arrives while the deadline stops the run"
    (with-guard-signal-states ()
      (let* ((start (get-internal-real-time))
             ;; The deadline's cleanup lasts at least the 0.5 s grace period.
             (sender (%simulate-signal-when
                      (lambda () (>= (- (get-internal-real-time) start)
                                     (* 7/10 internal-time-units-per-second)))
                      sb-unix:sigterm)))
        (multiple-value-bind (envelope status)
            (json-command "sh -c 'trap \"\" TERM; sleep 30'" :timeout 1/2)
          (expect (sb-thread:join-thread sender :default nil :timeout 5) :to-equal :delivered)
          (expect status :to-equal 124)
          (expect (json-at envelope "error" "code") :to-equal "E_TIMEOUT")))))

  (it "keeps E_INTERACTIVE_PROGRAM when a signal arrives after the alternate screen"
    (with-guard-signal-states ()
      (with-noninteractive-test-state ()
        (host-kit:with-temporary-directory (directory)
          (let* ((ready (format nil "~Aready" (sb-ext:native-namestring directory)))
                 ;; The screen switches 0.2 s after READY; the cleanup it
                 ;; starts lasts at least the 0.5 s grace period, as the
                 ;; child ignores SIGTERM.
                 (sender (%simulate-signal-when (lambda () (probe-file ready))
                                                sb-unix:sigint :delay 1/2)))
            (multiple-value-bind (envelope status)
                (json-command (format nil "sh -c 'trap \"\" TERM; : > ~A; sleep 0.2; ~
                                           printf \"\\033[?1049h\"; sleep 30'"
                                      ready)
                              :timeout 20)
              (expect (sb-thread:join-thread sender :default nil :timeout 5) :to-equal :delivered)
              (expect status :to-equal 6)
              (expect (json-at envelope "error" "code") :to-equal "E_INTERACTIVE_PROGRAM")))))))

  (it "keeps E_INTERRUPTED when the deadline passes during its cleanup"
    (with-guard-signal-states ()
      (host-kit:with-temporary-directory (directory)
        (let* ((ready (format nil "~Aready" (sb-ext:native-namestring directory)))
               (sender (%simulate-signal-when (lambda () (probe-file ready))
                                              sb-unix:sighup)))
          ;; The child ignores SIGTERM, so the cleanup outlasts the deadline.
          (multiple-value-bind (envelope status)
              (json-command (format nil "sh -c 'trap \"\" TERM; : > ~A; sleep 30'" ready)
                            :timeout 1/2)
            (expect (sb-thread:join-thread sender :default nil :timeout 5) :to-equal :delivered)
            (expect status :to-equal 130)
            (expect (json-at envelope "error" "message")
                    :to-equal "the run was interrupted by SIGHUP"))))))

  (it "keeps the summary of a compilation the deadline cut short out of stderr"
    ;; The macro's expander sleeps while SBCL compiles the form, so the
    ;; deadline unwinds a compilation unit, which then prints a summary.
    (let ((envelope (json-command "(MACROLET ((M () (CL:SLEEP 30) NIL)) (M))"
                                  :timeout 1)))
      (expect (json-at envelope "error" "code") :to-equal "E_TIMEOUT")
      (expect (json-at envelope "stderr" "text") :to-equal ""))))
