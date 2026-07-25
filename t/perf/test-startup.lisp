(in-package #:nshell/test)

(defun %elapsed-real-seconds (thunk)
  (let ((start (get-internal-real-time)))
    (funcall thunk)
    (/ (- (get-internal-real-time) start)
       internal-time-units-per-second)))

(defun %test-startup-shell-context ()
  (make-test-shell-context :running t))

(describe "startup-performance-tests"
  (it "startup-hot-context-composition-under-budget"
    "Composing an interactive shell context remains cheap."
    (let ((elapsed (%elapsed-real-seconds
                    (lambda ()
                      (dotimes (i 200)
                        (%test-startup-shell-context))))))
      (expect elapsed :to-be-less-than 2.0)))

  (it "startup-cold-asdf-load-under-budget"
    "A cold SBCL process can load the nshell system within an interactive budget."
    ;; Reuses t/e2e/test-smoke.lisp's %asdf-bootstrap-forms so this
    ;; subprocess's central-registry carries the same dependency roots
    ;; (including transitive ones like cl-log-kit) as the e2e bootstrap,
    ;; rather than a second, easily-stale hand-rolled list.
    (let* ((root (asdf:system-source-directory :nshell))
           (sbcl (current-sbcl-executable))
           (exit-code nil)
           (elapsed
             (%elapsed-real-seconds
              (lambda ()
                (setf exit-code
                      (nth-value 2
                        (uiop:run-program
                         (append (list sbcl "--noinform")
                                 (%asdf-bootstrap-forms (namestring root))
                                 (list "--eval" "(asdf:load-system :nshell)"
                                       "--eval" "(sb-ext:quit :unix-status 0)"))
                         :directory root
                         :output nil
                         :error-output nil
                         :ignore-error-status t
                         :timeout 60)))))))
      (expect 0 :to-equal exit-code)
      (expect elapsed :to-be-less-than 20.0))))
