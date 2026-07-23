(in-package #:nshell/test)

(defun %elapsed-real-seconds (thunk)
  (let ((start (get-internal-real-time)))
    (funcall thunk)
    (/ (- (get-internal-real-time) start)
       internal-time-units-per-second)))

(defun %test-startup-shell-context ()
  (make-test-shell-context :running t))

(defun %startup-asdf-bootstrap-args (root)
  ;; See tests/e2e/test-smoke.lisp's %asdf-bootstrap-forms: ask the parent
  ;; process where it actually resolved cl-prolog rather than guessing a
  ;; sibling-checkout path, so this also works in a hermetic build sandbox.
  (let ((cl-prolog-root
          (namestring (asdf:system-source-directory :cl-prolog))))
    (list "--eval" "(require :asdf)"
          "--eval" (format nil "(pushnew (truename ~S) asdf:*central-registry* :test #'equal)" root)
          "--eval" (format nil "(pushnew (truename ~S) asdf:*central-registry* :test #'equal)" cl-prolog-root))))

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
    (let* ((root (asdf:system-source-directory :nshell))
           (sbcl (current-sbcl-executable))
           (elapsed
             (%elapsed-real-seconds
              (lambda ()
                (uiop:run-program
                 (append (list sbcl "--noinform")
                         (%startup-asdf-bootstrap-args (namestring root))
                         (list "--eval" "(asdf:load-system :nshell)"
                               "--eval" "(sb-ext:quit :unix-status 0)"))
                 :directory root
                 :output nil
                 :error-output nil
                 :timeout 60)))))
      (expect elapsed :to-be-less-than 20.0))))
