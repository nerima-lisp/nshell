(in-package #:nshell/test)
(describe "e2e-signal-tests"
  (it "e2e-signal-constants-exist"
    (expect (nshell.domain.signals:signal-p nshell.domain.signals:+sigint+) :to-be-truthy)
    (expect (nshell.domain.signals:signal-p nshell.domain.signals:+sigterm+) :to-be-truthy)))
