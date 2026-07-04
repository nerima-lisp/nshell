(in-package #:nshell/test)

(def-suite startup-performance-tests
  :description "Startup performance regression tests"
  :in nshell-tests)

(in-suite startup-performance-tests)

(defun %elapsed-real-seconds (thunk)
  (let ((start (get-internal-real-time)))
    (funcall thunk)
    (/ (- (get-internal-real-time) start)
       internal-time-units-per-second)))

(defun %test-startup-shell-context ()
  (let ((filesystem-fns (list :list-dir (lambda (dir)
                                          (declare (ignore dir))
                                          nil)
                              :stat (lambda (path)
                                      (declare (ignore path))
                                      nil)
                              :cwd (lambda () #p"/tmp/")
                              :chdir (lambda (path)
                                       (declare (ignore path))
                                       t)))
        (process-fns (list :run-external (lambda (command args)
                                           (declare (ignore command args))
                                           0)))
        (terminal-fns (list :get-size (lambda () (values 80 24)))))
    (nshell.application:make-shell-context
     :history (nshell.domain.history:make-command-history)
     :config (nshell.domain.configuration:default-config)
     :knowledge-base (nshell.domain.completion:make-empty-knowledge-base)
     :environment (nshell.domain.environment:make-default-environment)
     :dispatcher (nshell.application:make-event-dispatcher)
     :job-monitor (nshell.domain.job-control:make-job-monitor)
     :alias-table (make-hash-table :test #'equal)
     :abbreviation-table (make-hash-table :test #'equal)
     :function-table (make-hash-table :test #'equal)
     :filesystem-fns filesystem-fns
     :process-fns process-fns
     :terminal-fns terminal-fns
     :execution-strategy :cps
     :running t)))

(test startup-hot-context-composition-under-budget
  "Composing an interactive shell context remains cheap."
  (let ((elapsed (%elapsed-real-seconds
                  (lambda ()
                    (dotimes (i 200)
                      (%test-startup-shell-context))))))
    (is (< elapsed 2.0)
        "Composed 200 shell contexts in ~,3f seconds; expected < 2.0 seconds."
        elapsed)))

(test startup-cold-asdf-load-under-budget
  "A cold SBCL process can load the nshell system within an interactive budget."
  (let* ((root (asdf:system-source-directory :nshell))
         (sbcl (current-sbcl-executable))
         (elapsed
           (%elapsed-real-seconds
            (lambda ()
              (uiop:run-program
               (list sbcl
                     "--noinform"
                     "--eval" "(require :asdf)"
                     "--eval" "(push (truename \"./\") asdf:*central-registry*)"
                     "--eval" "(asdf:load-system :nshell)"
                     "--eval" "(sb-ext:quit :unix-status 0)")
               :directory root
               :output nil
               :error-output nil
               :timeout 60)))))
    (is (< elapsed 20.0)
        "Cold ASDF load took ~,3f seconds; expected < 20.0 seconds."
        elapsed)))
