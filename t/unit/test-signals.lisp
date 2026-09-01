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
      (expect (nshell.domain.signals:signal-p sig) :to-be-truthy)
      (expect :sigint :to-be (nshell.domain.signals:signal-name sig))
      (expect 2 :to-be (nshell.domain.signals:signal-number sig))))

  (it "signal-equality"
    (let ((a (nshell.domain.signals:make-signal :sigterm 15))
          (b (nshell.domain.signals:make-signal :sigterm 15))
          (c (nshell.domain.signals:make-signal :sigint 2)))
      (expect (nshell.domain.signals:signal= a b) :to-be-truthy)
      (expect (nshell.domain.signals:signal= a c) :to-be-falsy)))

  (it "signal-equality-rejects-non-signals-and-partial-matches"
    (let ((sigint (nshell.domain.signals:make-signal :sigint 2))
          (same-name (nshell.domain.signals:make-signal :sigint 15))
          (same-number (nshell.domain.signals:make-signal :sigterm 2)))
      (dolist (other (list nil :sigint same-name same-number))
        (expect (nshell.domain.signals:signal= sigint other) :to-be-falsy))
      (expect (nshell.domain.signals:signal= nil sigint) :to-be-falsy)))

  (it "known-signal-constants"
    (dolist (expected '( (:sigint . 2) (:sigterm . 15) (:sigcont . 18) (:sigchld . 17)))
      (let ((signal (symbol-value
                     (find-symbol (format nil "+~A+" (car expected))
                                  '#:nshell.domain.signals))))
        (expect (nshell.domain.signals:signal-p signal) :to-be-truthy)
        (expect (car expected) :to-be (nshell.domain.signals:signal-name signal))
        (expect (cdr expected) :to-be (nshell.domain.signals:signal-number signal))))))
