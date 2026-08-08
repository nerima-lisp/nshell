(in-package #:nshell/benchmark)

(progn
  (defparameter +default-process-samples+ 100)
  (defparameter +minimum-process-samples-for-p99+ 100)

  (defun %validate-process-samples (samples)
    (unless (>= samples +minimum-process-samples-for-p99+)
      (error "NSHELL_BENCH_PROCESS_SAMPLES must be at least ~D so p99 is not merely the maximum sample"
             +minimum-process-samples-for-p99+))
    samples)

  (defun %process-versions (jobs)
    (let ((versions (make-hash-table :test #'equal)))
      (dolist (job jobs versions)
        (let* ((subject (getf job :subject))
               (name (getf subject :name)))
          (multiple-value-bind (version presentp) (gethash name versions)
            (declare (ignore version))
            (unless presentp
              (setf (gethash name versions) (%process-version subject)))))))))
(defparameter +default-process-timeout+ 30)
(progn
  (defparameter +sentinel+ "nshell-bench-sentinel")
  (defparameter +default-process-order-seed+ 20260726))

(defun %process-environment-integer (name default)
  (let ((value (host-kit:getenv name)))
    (if (and value (plusp (length value)))
        (or (ignore-errors (parse-integer value))
            (error "~A must be an integer" name))
        default)))

(defun %available-program (name) (loop for directory in (host-kit:split-string (or (host-kit:getenv "PATH") "") :separator (list #\:)) for path = (merge-pathnames name (host-kit:ensure-directory-pathname directory)) when (probe-file path) return (namestring path)))

(defun %process-subjects ()
  (list
    (list :name "nshell" :path (host-kit:getenv "NSHELL_BENCH_NSHELL_BIN")
          :missing-reason "NSHELL_BENCH_NSHELL_BIN is unset or does not name an existing file"
          :version-arguments '("--version") :sentinel-arguments (list "-c" (format nil "printf ~A" +sentinel+)))
    (list :name "fish" :path (%available-program "fish") :missing-reason "fish is not on PATH"
          :version-arguments '("--version") :sentinel-arguments (list "--no-config" "-c" (format nil "printf ~A" +sentinel+)))
    (list :name "zsh" :path (%available-program "zsh") :missing-reason "zsh is not on PATH"
          :version-arguments '("--version") :sentinel-arguments (list "-f" "-c" (format nil "printf ~A" +sentinel+)))
    (list :name "bash" :path (%available-program "bash") :missing-reason "bash is not on PATH"
          :version-arguments '("--version") :sentinel-arguments (list "--noprofile" "--norc" "-c" (format nil "printf ~A" +sentinel+)))))

(defun %run-process-sample (command timeout expected-output)
  (let ((start (get-internal-real-time)))
    (let* ((result (host-kit:run-program (first command) (rest command)
                                         :timeout timeout))
           (output (host-kit:process-result-stdout result))
           (error-output (host-kit:process-result-stderr result))
           (status (host-kit:process-result-exit-code result)))
      (unless (and (zerop status)
                   (or (null expected-output) (string= output expected-output)))
        (error "Command ~S failed (status ~A, stdout ~S, stderr ~S)"
               command status output error-output))
      (/ (* 1000.0d0 (- (get-internal-real-time) start))
         internal-time-units-per-second))))

(defun %write-process-result
    (stream subject scenario status measured-samples configured-samples timeout version
     order-seed execution-order &optional reason)
  (let ((statistics (and measured-samples (%latency-statistics measured-samples))))
    (write-char #\{ stream)
    (flet ((key (name) (%write-json-string name stream) (write-char #\: stream))
           (separator () (write-char #\, stream))
           (string-array (values)
             (write-char #\[ stream)
             (loop for value in values
                   for first = t then nil
                   do (unless first (write-char #\, stream))
                      (%write-json-string value stream))
             (write-char #\] stream)))
      (key "schema_version") (write-string "2" stream) (separator)
      (key "source_revision")
      (%write-json-string
        (or (host-kit:getenv "NSHELL_BENCH_SOURCE_REVISION")
            (handler-case
                (string-trim (list #\Space #\Tab #\Newline #\Return)
                             (host-kit:process-result-stdout
                              (host-kit:run-program "git" '("rev-parse" "HEAD"))))
              (error () "unknown")))
        stream)
      (separator)
      (key "cpu_model") (%write-json-string (machine-type) stream) (separator)
      (key "benchmark") (%write-json-string "shell-process-launch" stream) (separator)
      (key "scope") (%write-json-string "fresh-process-warm-fs launch latency; each sample starts a new process without clearing OS filesystem or executable caches" stream) (separator)
      (key "subject") (%write-json-string (getf subject :name) stream) (separator)
      (key "executable_path") (%write-json-string (or (getf subject :path) "") stream) (separator)
      (key "version_output") (%write-json-string version stream) (separator)
      (key "os") (%write-json-string (software-type) stream) (separator)
      (key "os_version") (%write-json-string (software-version) stream) (separator)
      (key "architecture") (%write-json-string (machine-type) stream) (separator)
      (key "configured_samples") (format stream "~D" configured-samples) (separator)
      (key "timeout_seconds") (format stream "~D" timeout) (separator)
      (key "order_seed") (format stream "~D" order-seed) (separator)
      (key "execution_order") (string-array execution-order) (separator)
      (key "scenario") (%write-json-string scenario stream) (separator)
      (key "status") (%write-json-string status stream) (separator)
      (key "comparable") (write-string "false" stream) (separator)
      (key "comparison_reason")
      (%write-json-string
        "Workloads and shell semantics differ, and OS filesystem and executable cache state is uncontrolled"
        stream)
      (separator)
      (key "ranking_eligible") (write-string "false" stream) (separator)
      (key "cache_state") (%write-json-string "fresh-process-warm-fs" stream) (separator)
      (key "sample_unit") (%write-json-string "milliseconds-per-process" stream) (separator)
      (key "raw_samples_ms") (%write-json-number-array (or measured-samples '()) stream)
      (when statistics
        (separator) (key "statistics_ms") (write-char #\{ stream)
        (key "min") (%write-json-number (getf statistics :minimum) stream) (separator)
        (key "p50") (%write-json-number (getf statistics :p50) stream) (separator)
        (key "p95") (%write-json-number (getf statistics :p95) stream) (separator)
        (key "p99") (%write-json-number (getf statistics :p99) stream) (separator)
        (key "max") (%write-json-number (getf statistics :maximum) stream) (separator)
        (key "mean") (%write-json-number (getf statistics :mean) stream) (separator)
        (key "mad") (%write-json-number (getf statistics :mad) stream)
        (write-char #\} stream))
      (when reason
        (separator) (key "reason") (%write-json-string reason stream))
      (write-char #\} stream)
      (terpri stream))))

(progn
  (defun %make-process-jobs ()
    (loop for subject in (%process-subjects)
          append
            (list
            (list :subject subject :scenario "startup-version"
                  :arguments (getf subject :version-arguments) :expected nil
                  :latencies nil :failure nil)
            (list :subject subject :scenario "cli-sentinel"
                  :arguments (getf subject :sentinel-arguments) :expected +sentinel+
                  :latencies nil :failure nil))))

  (defun %shuffle-process-jobs (jobs state)
    (let ((items (coerce jobs 'vector)))
      (loop for index from (1- (length items)) downto 1
            do (setf state (mod (+ (* state 1103515245) 12345) 2147483648))
               (rotatef (aref items index) (aref items (mod state (1+ index)))))
      (values (coerce items 'list) state)))

  (defun %process-job-label (round job)
    (format nil "round=~D:~A/~A" round
            (getf (getf job :subject) :name) (getf job :scenario)))

  (defun %process-version (subject)
    (let ((path (getf subject :path)))
      (if (and path (probe-file path))
          (handler-case
              (string-trim (list #\Space #\Tab #\Newline #\Return)
                           (host-kit:process-result-stdout
                            (host-kit:run-program path (getf subject :version-arguments))))
            (error () "unknown"))
          "unknown")))

  (defun %process-job-available-p (job)
    (let ((path (getf (getf job :subject) :path)))
      (and path (plusp (length path)) (probe-file path)))))

(defun run-process-benchmark (&key (jsonl-stream *standard-output*))
  (let* ((samples (%validate-process-samples
                   (%process-environment-integer
                     "NSHELL_BENCH_PROCESS_SAMPLES" +default-process-samples+)))
         (timeout (%process-environment-integer
                    "NSHELL_BENCH_PROCESS_TIMEOUT" +default-process-timeout+))
         (order-seed (%process-environment-integer
                       "NSHELL_BENCH_PROCESS_SEED" +default-process-order-seed+))
         (jobs (%make-process-jobs))
         (versions (%process-versions jobs))
         (execution-order '())
         (failures '()))
    (unless (plusp timeout) (error "NSHELL_BENCH_PROCESS_TIMEOUT must be positive"))
    (unless (not (minusp order-seed)) (error "NSHELL_BENCH_PROCESS_SEED must be non-negative"))
    (format t "~&Shell process-launch benchmark: fresh-process-warm-fs; each sample starts a new process, and OS caches are not cleared.~%")
    (format t "Reproduce: NSHELL_BENCH_MODE=process NSHELL_BENCH_PROCESS_SAMPLES=~D NSHELL_BENCH_PROCESS_TIMEOUT=~D NSHELL_BENCH_PROCESS_SEED=~D NSHELL_BENCH_NSHELL_BIN=/absolute/path/to/nshell sbcl --script scripts/benchmark-completion.lisp~%"
            samples timeout order-seed)
    (format t "Cross-shell comparison is excluded because command workloads and shell semantics are not equivalent.~%")
    (let ((state order-seed))
      (dotimes (round samples)
        (multiple-value-bind (ordered-jobs next-state) (%shuffle-process-jobs jobs state)
          (setf state next-state)
          (dolist (job ordered-jobs)
            (when (and (%process-job-available-p job) (null (getf job :failure)))
              (push (%process-job-label round job) execution-order)
              (handler-case
                  (push (%run-process-sample
                          (cons (getf (getf job :subject) :path) (getf job :arguments))
                          timeout (getf job :expected))
                        (getf job :latencies))
                (error (condition)
                  (setf (getf job :failure) (princ-to-string condition))
                  (push job failures))))))))
    (setf execution-order (nreverse execution-order))
    (dolist (job jobs)
      (let* ((subject (getf job :subject))
             (latencies (nreverse (getf job :latencies)))
             (failure (getf job :failure))
             (available (%process-job-available-p job))
             (status (cond (failure "failed") (available "ok") (t "skipped")))
             (reason (or failure (unless available (getf subject :missing-reason)))))
        (when latencies
          (format t "~&~A/~A: p50=~,3F ms (~D samples)~%"
                  (getf subject :name) (getf job :scenario)
                  (getf (%latency-statistics latencies) :p50) (length latencies)))
        (%write-process-result
          jsonl-stream subject (getf job :scenario) status latencies samples timeout
          (gethash (getf subject :name) versions) order-seed execution-order reason)))
    (when failures
      (error "~D process benchmark command~:P failed" (length failures)))
    (values)))
