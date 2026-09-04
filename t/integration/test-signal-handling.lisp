(in-package #:nshell/test)

(describe "signal-handling-tests"
  (it "rejects-invalid-domain-signal-values"
    "Signal value objects enforce their keyword and POSIX number invariants."
    (dolist (arguments '((:sigint 0)
                         (:sigint 65)
                         ("sigint" 2)))
      (destructuring-bind (name number) arguments
        (expect (lambda ()
                  (nshell.domain.signals:make-signal name number))
                :to-throw 'error))))

  (it "compares signal value objects by name and number"
    (let ((sigint (nshell.domain.signals:make-signal :sigint 2))
          (other-name (nshell.domain.signals:make-signal :sigterm 2))
          (other-number (nshell.domain.signals:make-signal :sigint 15)))
      (expect (nshell.domain.signals:signal= sigint sigint) :to-be-truthy)
      (expect (nshell.domain.signals:signal= sigint other-name) :to-be-falsy)
      (expect (nshell.domain.signals:signal= sigint other-number) :to-be-falsy)
      (expect (nshell.domain.signals:signal= sigint :sigint) :to-be-falsy)
      (expect :sigint :to-equal (nshell.domain.signals:signal-name sigint))
      (expect 2 :to-equal (nshell.domain.signals:signal-number sigint))))

  (it "signal-constants-and-mapping-exist"
    "Signal constants can be mapped between OS and domain values."
    (expect (nshell.domain.signals:signal-p
         (nshell.infrastructure.acl:os-signal->domain :sigint)) :to-be-truthy)
    (expect (nshell.domain.signals:signal-p
         (nshell.infrastructure.acl:os-signal->domain :sigchld)) :to-be-truthy)
    (expect :sigint :to-be (nshell.infrastructure.acl:domain-signal->os nshell.domain.signals:+sigint+)))

  (it "signal-mapping-covers-the-supported-boundary"
    "Every supported OS signal name round-trips through the domain boundary."
    (dolist (name '(:sigint :sigterm :sigtstp :sigcont :sigchld :sigwinch))
      (let ((domain-signal (nshell.infrastructure.acl:os-signal->domain name)))
        (expect t :to-be (nshell.domain.signals:signal-p domain-signal))
        (expect name :to-be
                (nshell.infrastructure.acl:domain-signal->os domain-signal)))))

  (it "signal-mapping-rejects-unknown-os-names"
    "Unknown OS names remain outside the domain signal boundary."
    (expect nil :to-be
            (nshell.infrastructure.acl:os-signal->domain :not-a-signal)))

  (it "process-signal-classification-accepts-domain-and-os-designators"
    "Process control predicates classify both domain signals and OS designators."
    (dolist (case '((:sigstop t nil)
                    (:sigtstp t nil)
                    (:sigcont nil t)
                    (:sigterm nil nil)
                    (nil nil nil)))
      (destructuring-bind (signal stop-p continue-p) case
        (expect stop-p :to-be
                (nshell.infrastructure.acl:process-stop-signal-p signal))
        (expect continue-p :to-be
                (nshell.infrastructure.acl:process-continue-signal-p signal))))
    (expect t :to-be
            (nshell.infrastructure.acl:process-stop-signal-p
             (nshell.domain.signals:make-signal :sigstop 19)))
    (expect t :to-be
            (nshell.infrastructure.acl:process-continue-signal-p
             (nshell.domain.signals:make-signal :sigcont 18))))

  (it "install-signal-handlers-does-not-crash"
    "Installing signal handlers should complete without killing the shell."
    (expect t :to-be (nshell.infrastructure.acl:install-signal-handlers)))

  (it "sigwinch-notification-is-consumed-once"
    "Terminal resize notifications are delivered to the main loop once."
    (let ((nshell.infrastructure.acl::*terminal-resized* nil))
      (nshell.infrastructure.acl::shell-sigwinch-handler nil nil nil)
      (expect t :to-be
              (nshell.infrastructure.acl:consume-terminal-resize-p))
      (expect nil :to-be
              (nshell.infrastructure.acl:consume-terminal-resize-p))))

  (it "sigchld-notification-is-consumed-once"
    "Child-process notifications are acknowledged once outside the signal handler."
    (let ((nshell.infrastructure.acl::*children-changed* nil))
      (nshell.infrastructure.acl::shell-sigchld-handler nil nil nil)
      (expect t :to-be
              (nshell.infrastructure.acl:consume-children-changed-p))
      (expect nil :to-be
              (nshell.infrastructure.acl:consume-children-changed-p))))
  (it "sigint-notification-is-consumed-once"
  "SIGINT notifications are delivered to the input loop once."
  (let ((nshell.infrastructure.acl::*sigint-received* t))
    (expect t :to-be
            (nshell.infrastructure.acl:consume-sigint-received-p))
    (expect nil :to-be
            (nshell.infrastructure.acl:consume-sigint-received-p))))

  (it "sigint-handler-forwards-to-tracked-foreground-pgid"
    "SIGINT forwarding targets the tracked foreground process group."
    (let ((calls nil)
          (nshell.infrastructure.acl::*shell-pgid* 1000)
          (nshell.infrastructure.acl::*foreground-pgid* 4321)
          (nshell.infrastructure.acl::*sigint-received* nil))
      (with-temporary-function
          ('nshell.infrastructure.acl::%send-process-group-signal
           (lambda (pgid signal)
             (push (list pgid signal) calls)))
        (nshell.infrastructure.acl::shell-sigint-handler nil nil nil)
        (expect (list (list 4321 sb-unix:sigint)) :to-equal calls)
        (expect (null nshell.infrastructure.acl::*sigint-received*) :to-be-falsy))))

  (it "sigint-handler-does-not-target-shell-pgid"
    "SIGINT forwarding ignores the shell's own process group."
    (let ((calls nil)
          (nshell.infrastructure.acl::*shell-pgid* 1000)
          (nshell.infrastructure.acl::*foreground-pgid* 1000)
          (nshell.infrastructure.acl::*sigint-received* nil))
      (with-temporary-function
          ('nshell.infrastructure.acl::%send-process-group-signal
           (lambda (pgid signal)
             (push (list pgid signal) calls)))
        (nshell.infrastructure.acl::shell-sigint-handler nil nil nil)
        (expect calls :to-be-null)
        (expect (null nshell.infrastructure.acl::*sigint-received*) :to-be-falsy))))

  (it "sigtstp-handler-drops-ctrl-z-while-a-foreground-child-is-tracked"
    "SIGTSTP is neither forwarded nor self-applied while a foreground child
is registered: the only wait that registers one without handing over the
terminal (RUN-EXTERNAL-CAPTURE's COMMUNICATE) cannot observe a stopped
child, so forwarding would wedge the shell behind a suspended process and
self-suspending would stop the shell mid-command. Stop-capable waits hand
the terminal to the child's own process group, so their Ctrl-Z is delivered
by the kernel and never reaches this handler."
    (let ((calls nil)
          (nshell.infrastructure.acl::*shell-pgid* 1000)
          (nshell.infrastructure.acl::*foreground-pgid* 4321))
      (with-temporary-functions
          (('nshell.infrastructure.acl::%send-process-group-signal
            (lambda (pgid signal)
              (push (list pgid signal) calls)))
           ('nshell.infrastructure.acl:kill-process
            (lambda (pid signal)
              (push (list :self pid signal) calls))))
        (nshell.infrastructure.acl::shell-sigtstp-handler nil nil nil)
        (expect calls :to-be-null))))

  (it "sigtstp-handler-suspends-the-shell-without-a-foreground-child"
    "SIGTSTP restores the terminal and suspends the shell when idle."
    (let ((calls nil)
          (nshell.infrastructure.acl::*shell-pgid* 1000)
          (nshell.infrastructure.acl::*foreground-pgid* 0))
      (with-temporary-functions
          (('nshell.infrastructure.acl::%signal-foreground-process-group
            (lambda (signal)
              (declare (ignore signal))
              nil))
           ('nshell.infrastructure.terminal:restore-terminal-mode
            (lambda () (push :restore-terminal calls)))
           ('nshell.infrastructure.acl:kill-process
            (lambda (pid signal)
              (push (list :self pid signal) calls)))
           ('nshell.infrastructure.acl::current-process-id
            (lambda () 1000)))
        (nshell.infrastructure.acl::shell-sigtstp-handler nil nil nil)
        (expect 2 :to-be (length calls))
        (expect t :to-be
                (some (lambda (call)
                        (equal :restore-terminal call))
                      calls)))
        (expect t :to-be
                (some (lambda (call)
                        (equal (list :self 1000 sb-unix:sigtstp) call))
                      calls))))

  (it "sigcont-handler-reenables-raw-mode-and-reclaims-terminal"
    "SIGCONT restores interactive terminal ownership."
    (let ((calls nil))
      (with-temporary-functions
          (('nshell.infrastructure.terminal:enable-raw-mode
            (lambda () (push :enable-raw-mode calls)))
           ('nshell.infrastructure.acl:set-foreground-pgroup
            (lambda (pgid) (push (list :foreground pgid) calls)))
           ('nshell.infrastructure.acl::current-process-id
            (lambda () 1000)))
        (nshell.infrastructure.acl::shell-sigcont-handler nil nil nil)
        (expect '((:foreground 1000) :enable-raw-mode) :to-equal calls))))

  (it "foreground-forwarding-clears-stale-pgid-errors"
    "Foreground process-group races must not escape from signal handlers."
    (let ((calls nil)
          (nshell.infrastructure.acl::*shell-pgid* 1000)
          (nshell.infrastructure.acl::*foreground-pgid* 4321))
      (with-temporary-function
          ('nshell.infrastructure.acl::%send-process-group-signal
           (lambda (pgid signal)
             (push (list pgid signal) calls)
             (error "stale foreground process group")))
        (expect 4321 :to-equal (nshell.infrastructure.acl::%signal-foreground-process-group
                sb-unix:sigint))
        (expect (list (list 4321 sb-unix:sigint)) :to-equal calls)
        (expect 0 :to-equal nshell.infrastructure.acl::*foreground-pgid*))))

  (it "foreground-process-group-context-restores-previous-pgid"
    "Foreground process-group context tracks the child pgid and restores the shell pgid."
    (let ((sets nil)
          (nshell.infrastructure.acl::*shell-pgid* 1000)
          (nshell.infrastructure.acl::*foreground-pgid* 0))
      (with-temporary-functions
          (('nshell.infrastructure.acl:get-foreground-pgroup
            (lambda () 1000))
           ('nshell.infrastructure.acl:set-foreground-pgroup
            (lambda (pgid)
              (push pgid sets)
              pgid)))
        (let ((result (nshell.infrastructure.acl::%call-with-foreground-process-group
                       4321
                       (lambda ()
                         (expect 4321 :to-equal nshell.infrastructure.acl::*foreground-pgid*)
                         (expect '(4321) :to-equal sets)
                         :done))))
          (expect :done :to-be result)
          (expect 0 :to-equal nshell.infrastructure.acl::*foreground-pgid*)
          (expect '(1000 4321) :to-equal sets)))))

  (it "foreground-process-group-context-restores-after-error"
    "Foreground process-group context must restore shell state when the command fails."
    (let ((sets nil)
          (nshell.infrastructure.acl::*shell-pgid* 1000)
          (nshell.infrastructure.acl::*foreground-pgid* 0))
      (with-temporary-functions
          (('nshell.infrastructure.acl:get-foreground-pgroup
            (lambda () 1000))
           ('nshell.infrastructure.acl:set-foreground-pgroup
            (lambda (pgid)
              (push pgid sets)
              pgid)))
        (let ((result
                (handler-case
                    (nshell.infrastructure.acl::%call-with-foreground-process-group
                     4321
                     (lambda () (error "foreground command failed")))
                  (error () :caught))))
          (expect :caught :to-be result)
          (expect 0 :to-equal nshell.infrastructure.acl::*foreground-pgid*)
          (expect '(1000 4321) :to-equal sets)))))

  (it "reap-children-empty-when-no-children"
    "Reaping with no changed children returns an empty list."
    (expect (listp (nshell.infrastructure.acl:reap-children)) :to-be-truthy))

  (it "reap-children-exposes-typed-child-status"
    "Child reaping exposes a typed boundary instead of raw pid/status conses."
    (let ((status (nshell.infrastructure.acl::%make-child-status 123 0)))
      (expect (nshell.infrastructure.acl:child-status-p status) :to-be-truthy)
      (expect 123 :to-equal (nshell.infrastructure.acl:child-status-pid status))
      (expect 0 :to-equal (nshell.infrastructure.acl:child-status-status status))))

  (it "rejects-unsupported-signal-designators"
    "The signal ACL rejects names that are neither OS numbers nor domain signals."
    (expect (lambda ()
              (nshell.infrastructure.acl::%signal-number :not-a-signal))
            :to-throw 'error))

  (it "current-shell-pgid-falls-back-to-process-id"
    "A missing shell process-group id falls back to the current process id."
    (let ((nshell.infrastructure.acl::*shell-pgid* nil))
      (expect (sb-posix:getpid)
              :to-equal
              (nshell.infrastructure.acl::%current-shell-pgid))))

  (it "assign-process-group-validates-and-forwards-positive-identifiers"
    "Valid process-group assignments use the syscall seam and invalid ids are ignored."
    (let ((calls nil))
      (with-temporary-function
          ('nshell.infrastructure.acl:set-process-group
           (lambda (pid pgid)
             (push (list pid pgid) calls)))
        (expect 4321 :to-equal
                (nshell.infrastructure.acl::%assign-process-group 1234 4321))
        (expect '((1234 4321)) :to-equal calls)
        (expect (nshell.infrastructure.acl::%assign-process-group 0 4321)
                :to-be-null)
        (expect '((1234 4321)) :to-equal calls))))

  (it "invalid-foreground-process-group-runs-thunk-without-terminal-access"
    "An invalid process-group id leaves terminal state untouched while running the thunk."
    (let ((called nil)
          (nshell.infrastructure.acl::*foreground-pgid* 777))
      (expect :done :to-be
              (nshell.infrastructure.acl::%call-with-foreground-process-group
               0
               (lambda ()
                 (setf called t)
                 :done)))
      (expect called :to-be-truthy)
      (expect 777 :to-equal nshell.infrastructure.acl::*foreground-pgid*)))

  (it "decodes-no-child-wait-status-as-running"
    "A wait result with no child is represented as a running status."
    (multiple-value-bind (pid state detail)
        (nshell.infrastructure.acl::%decode-wait-status 0 0)
      (expect 0 :to-equal pid)
      (expect :running :to-be state)
      (expect nil :to-be detail)))

  (it "decodes-exited-wait-status"
    "A normally exited child exposes its exit code."
    (multiple-value-bind (pid state detail)
        (nshell.infrastructure.acl::%decode-wait-status 321
                                                        (ash 17 8))
      (expect 321 :to-equal pid)
      (expect :exited :to-be state)
      (expect 17 :to-equal detail)))

  (it "decodes-signaled-wait-status"
    "A signaled child exposes the terminating signal."
    (multiple-value-bind (pid state detail)
        (nshell.infrastructure.acl::%decode-wait-status 321 15)
      (expect 321 :to-equal pid)
      (expect :signaled :to-be state)
      (expect 15 :to-equal detail))))
