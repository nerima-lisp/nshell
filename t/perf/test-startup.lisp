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
                      (let* ((program (append (list sbcl "--noinform")
                                              (%asdf-bootstrap-forms (namestring root))
                                              (list "--eval" "(asdf:load-system :nshell)"
                                                    "--eval" "(sb-ext:quit :unix-status 0)")))
                             (result (host-kit:run-program (first program) (rest program)
                                                           :directory root
                                                           :timeout 60)))
                        (host-kit:process-result-exit-code result)))))))
      (expect 0 :to-equal exit-code)
      (expect elapsed :to-be-less-than 20.0)))
  (it "startup-history-membership-work-scales-linearly"
    "Loading unique histories grows membership checks with the record count."
    (let ((probe-count 0)
          (original-probe
            (symbol-function
             'nshell.infrastructure.persistence::%history-record-entry-active-p)))
      (labels ((run-size (count)
                 (let* ((test-path
                          (format nil "/tmp/nshell-test-history-startup-~d-~d"
                                  count (random 1000000)))
                        (history (history-kit:make-history :capacity 256))
                        (nshell.infrastructure.persistence:*history-file-path-override*
                          (pathname test-path))
                        (nshell.presentation::*history-seen-command-texts*
                          (make-hash-table :test #'equal)))
                   (unwind-protect
                        (progn
                          (with-open-file (stream test-path :direction :output
                                                  :if-exists :supersede
                                                  :if-does-not-exist :create)
                            (dotimes (index count)
                              (nshell.infrastructure.persistence::%append-history-record
                               stream
                               (nshell.infrastructure.persistence::%make-history-record-from-values
                                :text (format nil "echo startup-~d" index)
                                :timestamp (+ 1700000000 index)
                                :cwd "/perf"
                                :exit-code 0
                                :duration-ms 1
                                :origin :typed
                                :host "startup-test"))))
                          (let ((before probe-count))
                            (let ((seeded
                                    (with-rebound-function
                                        (nshell.infrastructure.persistence::%history-record-entry-active-p
                                         (lambda (entry active-entries)
                                           (incf probe-count)
                                           (funcall original-probe
                                                    entry active-entries)))
                                      (nshell.presentation::%seed-history-from-file history))))
                              (expect seeded :to-be-truthy))
                            (let* ((entries (history-kit:history-entries history))
                                   (newest-entry (first entries))
                                   (oldest-retained-entry (car (last entries)))
                                   (record
                                     (nshell.infrastructure.persistence:history-record-for-entry
                                      history newest-entry)))
                              (expect 256 :to-equal (length entries))
                              (expect (format nil "echo startup-~d" (1- count))
                                      :to-equal
                                      (history-kit:history-entry-text newest-entry))
                              (expect (format nil "echo startup-~d" (- count 256))
                                      :to-equal
                                      (history-kit:history-entry-text oldest-retained-entry))
                              (expect "startup-test" :to-equal
                                      (nshell.infrastructure.persistence:history-record-host
                                       record)))
                            (expect count :to-equal
                                    (hash-table-count
                                     nshell.presentation::*history-seen-command-texts*))
                            (expect 256 :to-equal
                                    (hash-table-count
                                     (gethash
                                      history
                                      nshell.infrastructure.persistence::*history-record-tables*)))
                            (- probe-count before)))
                     (remhash history
                              nshell.infrastructure.persistence::*history-record-tables*)
                     (when (probe-file test-path)
                       (delete-file test-path))
                     (let ((lock-path
                             (nshell.infrastructure.persistence::%history-lock-path
                              test-path)))
                       (when (probe-file lock-path)
                         (delete-file lock-path)))))))
        (let ((small-probes (run-size 1000))
              (large-probes (run-size 10000)))
          (expect 1000 :to-equal small-probes)
          (expect 10000 :to-equal large-probes)
          (expect (* 10 small-probes) :to-equal large-probes))))))
