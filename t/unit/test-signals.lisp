(in-package #:nshell/test)

(describe "signal-tests"
  (it "signal-raw-constructor-is-internal-boundary"
    "Signals are created through the domain factory rather than raw struct construction."
    (multiple-value-bind (copy-symbol copy-status)
        (find-symbol "COPY-OS-SIGNAL" '#:nshell.domain.signals)
      (expect (fboundp 'nshell.domain.signals:make-signal) :to-be-truthy)
      (expect (fboundp 'nshell.domain.signals::%make-signal) :to-be-truthy)
      (expect (fboundp 'nshell.domain.signals::%allocate-signal) :to-be-truthy)
      (expect (or (null copy-status)
              (not (fboundp copy-symbol))) :to-be-truthy))
    (expect (lambda () (nshell.domain.signals:make-signal "sigint" 2)) :to-throw 'type-error)
    (expect (lambda () (nshell.domain.signals:make-signal :sigint 0)) :to-throw 'type-error)
    (expect (lambda () (nshell.domain.signals:make-signal :sigint 65)) :to-throw 'type-error)
    (expect (lambda () (nshell.domain.signals:make-signal :sigint "2")) :to-throw 'type-error))

  (it "signal-creation"
    (let ((sig (nshell.domain.signals:make-signal :sigint 2)))
      (expect (nshell.domain.signals:signal-p sig) :to-be-truthy)))

  (it "signal-equality"
    (let ((a (nshell.domain.signals:make-signal :sigterm 15))
          (b (nshell.domain.signals:make-signal :sigterm 15))
          (c (nshell.domain.signals:make-signal :sigint 2)))
      (expect (nshell.domain.signals:signal= a b) :to-be-truthy)
      (expect (nshell.domain.signals:signal= a c) :to-be-falsy)))

  (it "known-signal-constants"
    (expect (nshell.domain.signals:signal-p nshell.domain.signals:+sigint+) :to-be-truthy)
    (expect (nshell.domain.signals:signal-p nshell.domain.signals:+sigterm+) :to-be-truthy)
    (expect (nshell.domain.signals:signal-p nshell.domain.signals:+sigcont+) :to-be-truthy)
    (expect (nshell.domain.signals:signal-p nshell.domain.signals:+sigchld+) :to-be-truthy)))
