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

;; The signal the end-of-run rounds aim at a guard as its call ends. SIGHUP's
;; handler is the last one the guard puts back, so it lands in the guard most
;; often. Rounds go on until that has happened +END-OF-RUN-DELIVERIES+ times.
(defparameter +end-of-run-signal+ sb-unix:sighup)
(defparameter +end-of-run-deliveries+ 200)
(defparameter +end-of-run-max-rounds+ 50000)

(defun %deliver-when-run-ends (stop signal guard-handler-p ready returning)
  "Start a thread that sets the car of READY, waits until the car of
RETURNING is true and STOP's catch is gone, then at once simulates SIGNAL if
its installed handler is still one GUARD-HANDLER-P accepts. So the signal
lands while STOP's call is ending. Joining the thread returns :DELIVERED or
:NOT-DELIVERED."
  (sb-thread:make-thread
   (lambda ()
     (let ((deadline (+ (get-internal-real-time) (* 5 internal-time-units-per-second))))
       (flet ((spin-while (predicate)
                (loop while (and (funcall predicate)
                                 (< (get-internal-real-time) deadline)))))
         (setf (car ready) t)
         (spin-while (lambda () (not (car returning))))
         (spin-while (lambda () (nshell.infrastructure.acl::noninteractive-stop-armed-p stop)))
         (let ((handler (nshell.infrastructure.acl::lisp-signal-handler signal)))
           (if (and (functionp handler) (funcall guard-handler-p handler))
               (progn (funcall handler signal (sb-sys:int-sap 0) (sb-sys:int-sap 0))
                      :delivered)
               :not-delivered)))))
   :name "simulated signal at the end of a run"))

(defun %return-when-ready (ready returning)
  "A run's thunk: wait for the sender of %DELIVER-WHEN-RUN-ENDS, then return."
  (let ((deadline (+ (get-internal-real-time) (* 5 internal-time-units-per-second))))
    (loop until (or (car ready) (>= (get-internal-real-time) deadline))))
  (setf (car returning) t)
  :returned)

(defun %install-test-signal-handlers (&optional (handler (lambda (signal info context)
                                                          (declare (ignore signal info context)))))
  "Make HANDLER the handler of SIGHUP, SIGINT and SIGTERM, so that nothing this
test passes on can act on the test process."
  (dolist (signal (list sb-unix:sighup sb-unix:sigint sb-unix:sigterm))
    (sb-sys:enable-interrupt signal handler)))

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

  (it "records the signal that ended an inner call in the outer stop without unwinding it"
    ;; The --mcp server inside, RUN-JSON-COMMAND's guard inside that: the run
    ;; answers the signal and the server only learns of it afterwards.
    (with-guard-signal-states ()
      (let* ((outer (nshell.infrastructure.acl:make-noninteractive-stop))
             (steps '())
             (result
               (nshell.infrastructure.acl:call-with-noninteractive-signals
                outer
                (lambda ()
                  (push (nshell.infrastructure.acl:call-with-noninteractive-signals
                         (nshell.infrastructure.acl:make-noninteractive-stop)
                         (lambda ()
                           (expect (%simulate-signal sb-unix:sigterm) :to-equal :delivered)
                           (%wait-for-sleep-forever))
                         :after-signal (lambda (signal) (list :inner signal)))
                        steps)
                  ;; Still running here: the outer call was not unwound.
                  (push (nshell.infrastructure.acl:noninteractive-stop-signal outer) steps)
                  :outer-finished)
                :after-signal (lambda (signal) (list :outer signal)))))
        (expect (reverse steps) :to-equal (list (list :inner sb-unix:sigterm) sb-unix:sigterm))
        (expect result :to-equal (list :outer sb-unix:sigterm)))))

  (it "records in the outer stop a signal that an inner run with another reason leaves alone"
    ;; An --mcp run that the deadline stops: the run keeps E_TIMEOUT, and the
    ;; server still ends after it.
    (with-guard-signal-states ()
      (let* ((outer (nshell.infrastructure.acl:make-noninteractive-stop))
             (inner-stop (nshell.infrastructure.acl:make-noninteractive-stop))
             (inner nil)
             (result
               (nshell.infrastructure.acl:call-with-noninteractive-signals
                outer
                (lambda ()
                  (setf inner
                        (nshell.infrastructure.acl:call-with-noninteractive-signals
                         inner-stop
                         (lambda ()
                           (nshell.infrastructure.acl:claim-noninteractive-stop
                            inner-stop :timeout)
                           (expect (%simulate-signal sb-unix:sigterm) :to-equal :delivered)
                           :timed-out)
                         :after-signal (lambda (signal) (list :inner signal))))
                  :outer-finished)
                :after-signal (lambda (signal) (list :outer signal)))))
        (expect inner :to-equal :timed-out)
        (expect (nshell.infrastructure.acl:noninteractive-stop-reason inner-stop)
                :to-equal :timeout)
        (expect result :to-equal (list :outer sb-unix:sigterm)))))

  (it "records in the outer stop a signal that reaches an inner call as it ends"
    ;; The --mcp server: a signal that the run's guard takes after its run is
    ;; over, before its handlers are back, must still end the server. Each
    ;; round aims the signal at that moment; it lands just before or after
    ;; the guard has chosen its result.
    (with-guard-signal-states ()
      (%install-test-signal-handlers)
      (let ((original (nshell.infrastructure.acl::lisp-signal-handler +end-of-run-signal+))
            (delivered 0)
            (missed 0))
        (loop repeat +end-of-run-max-rounds+
              while (< delivered +end-of-run-deliveries+)
              do (let ((outer (nshell.infrastructure.acl:make-noninteractive-stop))
                       (inner (nshell.infrastructure.acl:make-noninteractive-stop))
                       (ready (list nil))
                       (returning (list nil))
                       (outcome nil))
                   (nshell.infrastructure.acl:call-with-noninteractive-signals
                    outer
                    (lambda ()
                      (let* ((outer-handler (nshell.infrastructure.acl::lisp-signal-handler
                                             +end-of-run-signal+))
                             (sender (%deliver-when-run-ends
                                      inner +end-of-run-signal+
                                      (lambda (handler)
                                        (not (or (eq handler original)
                                                 (eq handler outer-handler))))
                                      ready returning)))
                        (nshell.infrastructure.acl:call-with-noninteractive-signals
                         inner (lambda () (%return-when-ready ready returning))
                         :after-signal (lambda (signal) (list :inner signal)))
                        (setf outcome (sb-thread:join-thread sender :default nil :timeout 10))))
                    :after-signal (lambda (signal) (list :outer signal)))
                   (when (eq outcome :delivered)
                     (incf delivered)
                     (unless (eql (nshell.infrastructure.acl:noninteractive-stop-signal outer)
                                  +end-of-run-signal+)
                       (incf missed)))))
        (expect delivered :to-equal +end-of-run-deliveries+)
        (expect missed :to-equal 0))))

  (it "passes a signal that reaches a finished run's guard to the handler it replaced"
    ;; Batch and --json: no enclosing guard, and the run is over. The signal
    ;; is either the run's (AFTER-SIGNAL) or reaches the handler that is in
    ;; place again once the call returns, never neither.
    (with-guard-signal-states ()
      (let ((passed-on (list 0)))
        (%install-test-signal-handlers (lambda (signal info context)
                                         (declare (ignore signal info context))
                                         (sb-ext:atomic-incf (car passed-on))))
        (let ((original (nshell.infrastructure.acl::lisp-signal-handler +end-of-run-signal+))
              (delivered 0)
              (missed 0))
          (loop repeat +end-of-run-max-rounds+
                while (< delivered +end-of-run-deliveries+)
                do (let* ((stop (nshell.infrastructure.acl:make-noninteractive-stop))
                          (ready (list nil))
                          (returning (list nil))
                          (before (car passed-on))
                          (sender (%deliver-when-run-ends
                                   stop +end-of-run-signal+
                                   (lambda (handler) (not (eq handler original)))
                                   ready returning))
                          (result (nshell.infrastructure.acl:call-with-noninteractive-signals
                                   stop (lambda () (%return-when-ready ready returning))
                                   :after-signal (lambda (signal) (list :interrupted signal))))
                          (outcome (sb-thread:join-thread sender :default nil :timeout 10)))
                     (when (eq outcome :delivered)
                       (incf delivered)
                       (unless (or (equal result (list :interrupted +end-of-run-signal+))
                                   (> (car passed-on) before))
                         (incf missed)))))
          (expect delivered :to-equal +end-of-run-deliveries+)
          (expect missed :to-equal 0)))))

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
      (expect (json-at envelope "stderr" "text") :to-equal "")))

  (it "restores the handlers and starts afresh after every run of an MCP-style session"
    ;; As run-mcp-server calls it: one shell state kept across runs, one
    ;; session, NSHELL_AGENT=1 with the approved verdict. The runs happen in a
    ;; thread other than the initial one, so the interrupt must reach the
    ;; thread that called RUN-JSON-COMMAND.
    (with-guard-signal-states ()
      (dolist (signal (list sb-unix:sigint sb-unix:sigterm))
        (sb-sys:enable-interrupt signal (lambda (signal info context)
                                          (declare (ignore signal info context)))))
      (host-kit:with-temporary-directory (directory)
        (let* ((ready (format nil "~Aready" (sb-ext:native-namestring directory)))
               (interrupted (format nil "sh -c 'echo partial; : > ~A; sleep 30'" ready))
               (signals (list sb-unix:sighup sb-unix:sigint sb-unix:sigterm))
               (before (mapcar #'%guard-signal-state signals))
               (results
                 (sb-thread:join-thread
                  (sb-thread:make-thread
                   (lambda ()
                     (nshell.presentation::%initialize-batch-state)
                     (loop for (input signal) in (list (list "echo one" nil)
                                                       (list interrupted sb-unix:sigint)
                                                       (list "echo three" nil))
                           for seq from 1
                           collect
                           (let ((sender (and signal
                                              (%simulate-signal-when
                                               (lambda () (probe-file ready)) signal))))
                             (multiple-value-bind (json status)
                                 (nshell.feature.machine:run-json-command
                                  input :timeout 20
                                        :environment-agent-p t
                                        :approved-verdict
                                        (nshell.feature.machine::%classify-input input)
                                        :reset-state-p nil
                                        :session "s_guard" :output-session nil :seq seq)
                               (list (json-kit:parse json) status
                                     (and sender (sb-thread:join-thread
                                                  sender :default nil :timeout 5))
                                     (mapcar #'%guard-signal-state signals))))))
                   :name "mcp-style runs")
                  :default nil :timeout 60)))
          (expect (length results) :to-equal 3)
          (loop for (envelope status delivered after) in results
                for seq from 1
                do (expect (json-at envelope "session") :to-equal "s_guard")
                   (expect (json-at envelope "seq") :to-equal seq)
                   (loop for (disposition handler) in after
                         for (before-disposition before-handler) in before
                         do (expect disposition :to-equal before-disposition)
                            (expect (eq handler before-handler) :to-be-truthy))
                   (if (= seq 2)
                       (progn
                         (expect delivered :to-equal :delivered)
                         (expect status :to-equal 130)
                         (expect (json-at envelope "error" "code") :to-equal "E_INTERRUPTED")
                         (expect (json-at envelope "stdout" "text")
                                 :to-equal (format nil "partial~%")))
                       ;; A stop reason never outlives its run.
                       (progn
                         (expect status :to-equal 0)
                         (expect (json-at envelope "ok") :to-equal t)))))))))
