(in-package #:nshell/test)

(def-suite signal-handling-tests
  :description "Signal handling integration tests"
  :in nshell-tests)

(in-suite signal-handling-tests)

(test signal-constants-and-mapping-exist
  "Signal constants can be mapped between OS and domain values."
  (is (nshell.domain.signals:signal-p
       (nshell.infrastructure.acl:os-signal->domain :sigint)))
  (is (nshell.domain.signals:signal-p
       (nshell.infrastructure.acl:os-signal->domain :sigchld)))
  (is (eq :sigint
          (nshell.infrastructure.acl:domain-signal->os nshell.domain.signals:+sigint+))))

(test install-signal-handlers-does-not-crash
  "Installing signal handlers should complete without killing the shell."
  (is (eq t (nshell.infrastructure.acl:install-signal-handlers))))

(test sigint-handler-forwards-to-tracked-foreground-pgid
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
      (is (equal (list (list 4321 sb-unix:sigint)) calls))
      (is (not (null nshell.infrastructure.acl::*sigint-received*))))))

(test sigint-handler-does-not-target-shell-pgid
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
      (is (null calls))
      (is (not (null nshell.infrastructure.acl::*sigint-received*))))))

(test sigtstp-handler-forwards-to-tracked-foreground-pgid
  "SIGTSTP is forwarded to the foreground job instead of suspending the shell."
  (let ((calls nil)
        (nshell.infrastructure.acl::*shell-pgid* 1000)
        (nshell.infrastructure.acl::*foreground-pgid* 4321))
    (with-temporary-function
        ('nshell.infrastructure.acl::%send-process-group-signal
         (lambda (pgid signal)
           (push (list pgid signal) calls)))
      (nshell.infrastructure.acl::shell-sigtstp-handler nil nil nil)
      (is (equal (list (list 4321 sb-unix:sigtstp)) calls)))))

(test foreground-forwarding-clears-stale-pgid-errors
  "Foreground process-group races must not escape from signal handlers."
  (let ((calls nil)
        (nshell.infrastructure.acl::*shell-pgid* 1000)
        (nshell.infrastructure.acl::*foreground-pgid* 4321))
    (with-temporary-function
        ('nshell.infrastructure.acl::%send-process-group-signal
         (lambda (pgid signal)
           (push (list pgid signal) calls)
           (error "stale foreground process group")))
      (is (= 4321
             (nshell.infrastructure.acl::%signal-foreground-process-group
              sb-unix:sigint)))
      (is (equal (list (list 4321 sb-unix:sigint)) calls))
      (is (= 0 nshell.infrastructure.acl::*foreground-pgid*)))))

(test foreground-process-group-context-restores-previous-pgid
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
                       (is (= 4321 nshell.infrastructure.acl::*foreground-pgid*))
                       (is (equal '(4321) sets))
                       :done))))
        (is (eq :done result))
        (is (= 0 nshell.infrastructure.acl::*foreground-pgid*))
        (is (equal '(1000 4321) sets))))))

(test foreground-process-group-context-restores-after-error
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
        (is (eq :caught result))
        (is (= 0 nshell.infrastructure.acl::*foreground-pgid*))
        (is (equal '(1000 4321) sets))))))

(test reap-children-empty-when-no-children
  "Reaping with no changed children returns an empty list."
  (is (listp (nshell.infrastructure.acl:reap-children))))
