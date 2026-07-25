(in-package #:nshell/test)

;;; Tests for the cl-boundary-kit integration (src/presentation/repl-boundaries).
;;; Binding NSHELL.PRESENTATION::*BOUNDARIES* to a context of fakes makes the
;;; prompt and command-timing deterministic without touching the real host.

(describe "repl-boundaries-tests"
  (it "prompt-model-reads-hostname-and-cwd-from-boundaries"
    "With a fake host-info and working-directory boundary, the prompt model
reflects the injected values instead of the real machine."
    (let* ((host (cl-boundary-kit:make-test-host-info :hostname "ci-box"
                                                      :username "tester"))
           (wd (cl-boundary-kit:make-test-working-directory
                :initial #P"/home/tester/proj/"))
           (nshell.presentation::*boundaries*
             (cl-boundary-kit:make-boundary-context :host-info host :working-dir wd)))
      (let ((pm (nshell.presentation::%current-prompt-model 0 nil)))
        (expect "ci-box" :to-equal (nshell.domain.prompting:prompt-model-hostname pm))
        (expect "/home/tester/proj/" :to-equal
                (nshell.domain.prompting:prompt-model-cwd pm)))))

  (it "prompt-hostname-falls-back-to-localhost"
    "A boundary whose hostname resolves to NIL yields the localhost default."
    (let* ((host (cl-boundary-kit:make-host-info :hostname-fn (constantly nil)))
           (nshell.presentation::*boundaries*
             (cl-boundary-kit:make-boundary-context :host-info host)))
      (expect "localhost" :to-equal (nshell.presentation::boundary-hostname))))

  (it "boundary-accessors-default-to-real-when-unset"
    "With no context bound, the accessors still return usable real boundaries."
    (let ((nshell.presentation::*boundaries* nil))
      (expect (stringp (nshell.presentation::boundary-hostname)) :to-be-truthy)
      (expect (integerp (nshell.presentation::boundary-monotonic)) :to-be-truthy)))

  (it "command-timing-reads-a-fake-clock-deterministically"
    "A fake clock drives boundary-monotonic, so elapsed duration is exact."
    (let* ((clock (cl-boundary-kit:make-fake-clock :start 0 :monotonic-start 0))
           (nshell.presentation::*boundaries*
             (cl-boundary-kit:make-boundary-context :clock clock)))
      (let ((start (nshell.presentation::boundary-monotonic)))
        (cl-boundary-kit:advance-fake-clock clock 0 :monotonic-delta 500)
        (let ((elapsed (- (nshell.presentation::boundary-monotonic) start)))
          (expect 500 :to-equal elapsed)))))

  (it "real-boundary-context-exposes-every-boundary"
    "make-real-boundary-context wires all six boundaries used by the REPL edge."
    (let ((ctx (nshell.presentation::make-real-boundary-context)))
      (dolist (key '(:filesystem :host-info :working-dir :clock :environment :process))
        (expect (not (eq :missing
                         (cl-boundary-kit:boundary-context-get ctx key :missing)))
                :to-be-truthy)))))
