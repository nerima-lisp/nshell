(in-package #:nshell/test)

;;; These tests check that the per-key measurement in t/perf/key-cost.lisp
;;; observes what it claims to. They do not assert current per-key costs:
;;; scripts/perf/b3-measure.sh records those and the G3 gate compares them.

(defun %key-cost-temporary-path (name)
  (merge-pathnames (format nil "nshell-key-cost-test-~a-~d" name (random 1000000))
                   (uiop:temporary-directory)))

(describe "key-cost-measurement-tests"
  (it "key-cost-io-hooks-count-known-file-calls"
    "Opening, writing and probing a file are seen by the Lisp-level hooks."
    (let ((path (%key-cost-temporary-path "file")))
      (unwind-protect
           (nshell.perf.key-cost:with-io-hooks ()
             (multiple-value-bind (result counts)
                 (nshell.perf.key-cost:call-counting-io
                  (lambda ()
                    (with-open-file (stream path :direction :output
                                                 :if-does-not-exist :create)
                      (write-line "x" stream))
                    (probe-file path)))
               (expect result :to-be-truthy)
               (destructuring-bind (stat file-io spawn)
                   (nshell.perf.key-cost:io-counts-lisp-totals counts)
                 (expect stat :to-be-greater-than-or-equal 1)
                 (expect file-io :to-be-greater-than-or-equal 1)
                 (expect spawn :to-equal 0))))
        (when (probe-file path)
          (delete-file path)))))

  (it "key-cost-io-hooks-count-process-spawn"
    "Starting a child process through host-kit is counted as a spawn."
    (nshell.perf.key-cost:with-io-hooks ()
      (multiple-value-bind (result counts)
          (nshell.perf.key-cost:call-counting-io
           (lambda () (host-kit:run-program "/bin/sh" '("-c" "exit 0"))))
        (expect 0 :to-equal (host-kit:process-result-exit-code result))
        (expect (third (nshell.perf.key-cost:io-counts-lisp-totals counts))
                :to-be-greater-than-or-equal 1))))

  (it "key-cost-io-hooks-count-only-inside-the-window"
    "Calls made outside CALL-COUNTING-IO leave the counters at zero."
    (nshell.perf.key-cost:with-io-hooks ()
      (probe-file "/")
      (multiple-value-bind (result counts)
          (nshell.perf.key-cost:call-counting-io (lambda () :idle))
        (expect result :to-be :idle)
        (expect (nshell.perf.key-cost:io-counts-lisp-totals counts)
                :to-equal '(0 0 0)))))

  (it "key-cost-io-hooks-are-removed-after-a-non-local-exit"
    "Leaving WITH-IO-HOOKS by an error restores every hooked function."
    (let ((original (symbol-function 'sb-unix:unix-open)))
      (expect (block escape
                (handler-bind ((error (lambda (condition)
                                        (declare (ignore condition))
                                        (return-from escape :escaped))))
                  (nshell.perf.key-cost:with-io-hooks ()
                    (expect (member 'sb-unix:unix-open
                                    (nshell.perf.key-cost:installed-io-hooks))
                            :to-be-truthy)
                    (error "leave the hooks"))))
              :to-be :escaped)
      (expect (nshell.perf.key-cost:installed-io-hooks) :to-be-null)
      (expect (symbol-function 'sb-unix:unix-open) :to-be original)
      (expect (sb-int:encapsulated-p 'sb-unix:unix-open
                                     'nshell.perf.key-cost::key-cost-counter)
              :to-be-falsy)))

  (it "key-cost-precise-bytes-consed-reads-a-known-allocation"
    "A 1.6 MB allocation, the scale of one key's consing, reads within 5%."
    ;; Single readings of small allocations are not reliable once the heap is
    ;; fragmented (see the comment above PRECISE-BYTES-CONSED), and the gate
    ;; compares megabytes per key, so the check uses that scale. A collection
    ;; inside a window can shift one reading, hence the median of five.
    (let* ((expected (* 100000 2 sb-vm:n-word-bytes))
           (lists nil)
           (readings
             (loop repeat 5
                   collect (let ((start (nshell.perf.key-cost:precise-bytes-consed)))
                             (push (make-list 100000) lists)
                             (- (nshell.perf.key-cost:precise-bytes-consed) start))))
           (median (nth 2 (sort readings #'<))))
      (expect (length lists) :to-equal 5)
      (expect median :to-be-greater-than-or-equal (* 0.95 expected))
      (expect median :to-be-less-than-or-equal (* 1.05 expected))))

  (it "key-cost-marks-ttl-dependent-scenarios-outside-the-io-gate"
    "Only the warm-cache scenario is excluded from the I/O gate, and the JSON says so."
    (expect (loop for scenario in (nshell.perf.key-cost:default-scenarios nil)
                  unless (nshell.perf.key-cost::scenario-io-gate scenario)
                    collect (nshell.perf.key-cost::scenario-name scenario))
            :to-equal '("path-20k-type-warm"))
    (let ((json (with-output-to-string (stream)
                  (nshell.perf.key-cost:write-results-json
                   (list (nshell.perf.key-cost::make-scenario-result
                          :name "gated" :keys 1 :bytes '(10) :stat-per-key 1
                          :file-io-per-key 1 :spawn-per-key 0)
                         (nshell.perf.key-cost::make-scenario-result
                          :name "ungated" :keys 1 :bytes '(10) :stat-per-key 1
                          :file-io-per-key 1 :spawn-per-key 0 :io-gate nil))
                   stream))))
      (expect (search "\"spawn_per_key\":0,\"io_gate\":true}" json) :to-be-truthy)
      (expect (search "\"spawn_per_key\":0,\"io_gate\":false}" json) :to-be-truthy)))

  (it "key-cost-drives-keys-through-an-isolated-repl-session"
    "Measured keys reach the REPL, allocate, and leave process state as it was."
    (let ((fixture (nshell.perf.key-cost:make-fixture :history-count 20
                                                      :big-entry-count 10))
          (home (sb-posix:getenv "HOME"))
          (cwd (sb-posix:getcwd))
          (input-state nshell.presentation::*input-state*))
      (unwind-protect
           (let ((results (nshell.perf.key-cost:measure-scenarios
                           fixture :samples 2 :warmup 1
                                   :names '("bare-type-1" "history-prev"))))
             (expect (mapcar #'nshell.perf.key-cost:scenario-result-name results)
                     :to-equal '("bare-type-1" "history-prev"))
             (dolist (result results)
               (expect (nshell.perf.key-cost:scenario-result-keys result) :to-equal 2)
               (expect (length (nshell.perf.key-cost:scenario-result-bytes result))
                       :to-equal 2)
               (expect (every #'plusp (nshell.perf.key-cost:scenario-result-bytes result))
                       :to-be-truthy)
               (expect (nshell.perf.key-cost:scenario-result-hook-counts result)
                       :to-be-truthy)))
        (nshell.perf.key-cost:remove-fixture fixture))
      (expect (sb-posix:getenv "HOME") :to-equal home)
      (expect (sb-posix:getcwd) :to-equal cwd)
      (expect nshell.presentation::*input-state* :to-be input-state)
      (expect (nshell.perf.key-cost:installed-io-hooks) :to-be-null)
      (expect (probe-file (nshell.perf.key-cost:fixture-root fixture)) :to-be-null))))
