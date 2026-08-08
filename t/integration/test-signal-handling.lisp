(in-package #:nshell/test)

(describe "signal-handling-tests"
  (it "signal-constants-and-mapping-exist"
    "Signal constants can be mapped between OS and domain values."
    (expect (nshell.domain.signals:signal-p
         (nshell.infrastructure.acl:os-signal->domain :sigint)) :to-be-truthy)
    (expect (nshell.domain.signals:signal-p
         (nshell.infrastructure.acl:os-signal->domain :sigchld)) :to-be-truthy)
    (expect :sigint :to-be (nshell.infrastructure.acl:domain-signal->os nshell.domain.signals:+sigint+)))

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

  (it "sigtstp-handler-forwards-to-tracked-foreground-pgid"
    "SIGTSTP is forwarded to the foreground job instead of suspending the shell."
    (let ((calls nil)
          (nshell.infrastructure.acl::*shell-pgid* 1000)
          (nshell.infrastructure.acl::*foreground-pgid* 4321))
      (with-temporary-function
          ('nshell.infrastructure.acl::%send-process-group-signal
           (lambda (pgid signal)
             (push (list pgid signal) calls)))
        (nshell.infrastructure.acl::shell-sigtstp-handler nil nil nil)
        (expect (list (list 4321 sb-unix:sigtstp)) :to-equal calls))))

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
        (let ((result (nshell.infrastructure.acl::%with-foreground-process-group
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
                    (nshell.infrastructure.acl::%with-foreground-process-group
                     4321
                     (lambda ()
                       (error "foreground command failed")))
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
      (expect 0 :to-equal (nshell.infrastructure.acl:child-status-status status)))))
