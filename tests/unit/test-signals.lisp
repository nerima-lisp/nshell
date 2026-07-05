(in-package #:nshell/test)

(def-suite signal-tests
  :description "Signal value object tests"
  :in nshell-tests)

(in-suite signal-tests)

(test signal-raw-constructor-is-internal-boundary
  "Signals are created through the domain factory rather than raw struct construction."
  (multiple-value-bind (copy-symbol copy-status)
      (find-symbol "COPY-OS-SIGNAL" '#:nshell.domain.signals)
    (is (fboundp 'nshell.domain.signals:make-signal))
    (is (fboundp 'nshell.domain.signals::%make-signal))
    (is (fboundp 'nshell.domain.signals::%allocate-signal))
    (is (or (null copy-status)
            (not (fboundp copy-symbol)))))
  (signals type-error
    (nshell.domain.signals:make-signal "sigint" 2))
  (signals type-error
    (nshell.domain.signals:make-signal :sigint 0))
  (signals type-error
    (nshell.domain.signals:make-signal :sigint 65))
  (signals type-error
    (nshell.domain.signals:make-signal :sigint "2")))

(test signal-creation
  (let ((sig (nshell.domain.signals:make-signal :sigint 2)))
    (is (nshell.domain.signals:signal-p sig))))

(test signal-equality
  (let ((a (nshell.domain.signals:make-signal :sigterm 15))
        (b (nshell.domain.signals:make-signal :sigterm 15))
        (c (nshell.domain.signals:make-signal :sigint 2)))
    (is (nshell.domain.signals:signal= a b))
    (is (not (nshell.domain.signals:signal= a c)))))

(test known-signal-constants
  (is (nshell.domain.signals:signal-p nshell.domain.signals:+sigint+))
  (is (nshell.domain.signals:signal-p nshell.domain.signals:+sigterm+))
  (is (nshell.domain.signals:signal-p nshell.domain.signals:+sigcont+))
  (is (nshell.domain.signals:signal-p nshell.domain.signals:+sigchld+)))
