(in-package #:nshell/benchmark)

(defparameter +default-warmup+ 20)

(defparameter +default-samples+ 100)

(defparameter +default-batch+ 100)

(defparameter +default-cold-samples+ 20)

(defun %positive-environment-integer (name default)
  (let ((value (host-kit:getenv name)))
    (if value (let ((parsed (parse-integer value :junk-allowed nil)))
        (unless (plusp parsed)
          (error "~A must be a positive integer, got ~S" name value))
        parsed)
      default)))

(defun %candidate-signature (candidates)
  (mapcar
    (lambda (candidate)
      (list (candidate-text candidate) (candidate-kind candidate)))
    candidates))

(defun %result-checksum (candidates)
  (loop for candidate in candidates
        sum (+ (length (candidate-text candidate)) (sxhash (candidate-kind candidate)))))

(defun %assert-result (name thunk expected)
  (let ((actual (%candidate-signature (funcall thunk))))
    (unless (equal expected actual)
      (error
        "~A correctness oracle failed.~%Expected: ~S~%Actual: ~S"
        name
        expected
        actual))))

(defun %make-fixed-kb-workload ()
  (let ((kb (make-empty-knowledge-base)))
    (dotimes (index 1000)
      (kb-add-command kb (format nil "bench-command-~4,'0D" index)))
    (dotimes (index 100)
      (kb-add-option kb "bench-command-0500" (format nil "--option-~3,'0D" index)))
    (values
      (lambda ()
        (complete kb "bench-command-0500 --option-01"))
      (loop for index from 10 below 20
            collect (list (format nil "--option-~3,'0D" index) :option)))))

(progn
  (defun %make-fixed-rule-kb-workload ()
    (let ((kb nshell.domain.completion::*built-in-rule-knowledge-base*))
      (values
        (lambda () (complete kb "git --ver"))
        '(("--version" :option))
        (+ (length (nshell.domain.completion::rule-knowledge-base-facts kb))
           (length (nshell.domain.completion::rule-knowledge-base-rules kb))))))

  (defun %make-fixed-path-workload ()
    (let* ((kb (make-empty-knowledge-base))
           (entries (list #P"/fixture/zzbench-alpha" #P"/fixture/zzbench-beta"))
           (directory-files-fn
             (lambda (directory)
               (declare (ignore directory))
               entries))
           (executable-p-fn
             (lambda (entry)
               (declare (ignore entry))
               t))
           (directory-stamp-fn
             (lambda (directory)
               (declare (ignore directory))
               0)))
      (nshell.domain.completion::%invalidate-path-command-cache)
      (values
        (lambda ()
          (let ((*path-command-directory-files-fn* directory-files-fn)
                (*path-command-executable-p-fn* executable-p-fn)
                (*path-command-directory-stamp-fn* directory-stamp-fn))
            (complete kb "zzbench-" :path "/fixture")))
        '(("zzbench-alpha" :command) ("zzbench-beta" :command))))))

(defun %make-cold-path-workload (directory-map-fn)
  (let* ((kb (make-empty-knowledge-base))
         (directories
           (loop for index below 8
                 collect (format nil "/fixture/cck-~D" index)))
         (entries-by-directory (make-hash-table :test #'equal))
         (directory-files-fn
           (lambda (directory)
             (sleep 0.002d0)
             (copy-list (gethash (namestring directory) entries-by-directory))))
         (executable-p-fn
           (lambda (entry)
             (declare (ignore entry))
             t))
         (directory-stamp-fn
           (lambda (directory)
             (declare (ignore directory))
             0)))
    (loop for directory in directories
          for index from 0
          do (setf (gethash directory entries-by-directory)
                   (list (pathname (format nil "~A/nshell-~D" directory index)))))
    (values
      (lambda ()
        (let ((*path-command-directory-files-fn* directory-files-fn)
              (*path-command-executable-p-fn* executable-p-fn)
              (*path-command-directory-stamp-fn* directory-stamp-fn)
              (*path-command-directory-map-fn* directory-map-fn))
          (nshell.domain.completion::%invalidate-path-command-cache)
          (complete
            kb
            "nshell-"
            :path (format nil "~{~A~^:~}" directories))))
      (loop for index below 8
            collect (list (format nil "nshell-~D" index) :command)))))

(defun %warm-up (thunk warmup batch)
  (dotimes (sample warmup)
    (declare (ignore sample))
    (dotimes (iteration batch)
      (declare (ignore iteration))
      (%result-checksum (funcall thunk)))))

(defun %measure-latency (thunk samples batch)
  (let ((measurements '())
        (checksum 0))
    (dotimes (sample samples)
      (declare (ignore sample))
      (let ((start (get-internal-real-time)))
        (dotimes (iteration batch)
          (declare (ignore iteration))
          (incf checksum (%result-checksum (funcall thunk))))
        (push
          (/
            (* 1000.0d0 (- (get-internal-real-time) start))
            internal-time-units-per-second
            batch)
          measurements)))
    (values (nreverse measurements) checksum)))

(defun %percentile (sorted-samples fraction)
  (let* ((count (length sorted-samples))
         (index (max 0 (1- (ceiling (* fraction count))))))
    (nth index sorted-samples)))

(progn
  (defun %latency-statistics (samples)
    (let* ((sorted (sort (copy-list samples) #'<))
           (median (%percentile sorted 0.50d0)))
      (list
        :minimum (first sorted)
        :p50 median
        :p95 (%percentile sorted 0.95d0)
        :p99 (%percentile sorted 0.99d0)
        :maximum (car (last sorted))
        :mean (/ (reduce #'+ sorted) (length sorted))
        :mad (%percentile
               (sort (mapcar (lambda (sample) (abs (- sample median))) sorted) #'<)
               0.50d0))))

  (defun %write-json-string (value stream)
    (write-char #\" stream)
    (loop for character across value
          for code = (char-code character)
          do (case character
               (#\" (write-string "\\\"" stream))
               (#\\ (write-string "\\\\" stream))
               (#\Backspace (write-string "\\b" stream))
               (#\Page (write-string "\\f" stream))
               (#\Newline (write-string "\\n" stream))
               (#\Return (write-string "\\r" stream))
               (#\Tab (write-string "\\t" stream))
               (otherwise
                 (if (< code 32)
                     (format stream "\\u~4,'0X" code)
                     (write-char character stream)))))
    (write-char #\" stream))

  (defun %write-json-number (value stream)
    (format stream "~,9F" (coerce value 'double-float)))

  (defun %write-json-number-array (values stream)
    (write-char #\[ stream)
    (loop for value in values
          for first = t then nil
          do (unless first (write-char #\, stream))
             (%write-json-number value stream))
    (write-char #\] stream))

  (defun %write-json-result
      (stream name fixture-cardinality expected-count statistics latencies
       bytes-per-operation latency-checksum allocation-checksum warmup samples batch)
    (write-char #\{ stream)
    (flet ((key (name)
             (%write-json-string name stream)
             (write-char #\: stream))
           (separator () (write-char #\, stream)))
      (key "schema_version") (write-string "1" stream) (separator)
      (progn (key "source_revision") (%write-json-string (or (host-kit:getenv "NSHELL_BENCH_SOURCE_REVISION") (handler-case (string-trim (list #\Space #\Tab #\Newline #\Return) (host-kit:process-result-stdout (host-kit:run-program "git" '("rev-parse" "HEAD")))) (error () "unknown"))) stream) (separator) (key "cpu_model") (%write-json-string (machine-type) stream) (separator) (key "benchmark")) (%write-json-string "nshell-completion" stream) (separator)
      (key "scope")
      (%write-json-string
        "synthetic warm in-process completion API; excludes cold-cache, shell integration, and subprocess startup"
        stream)
      (separator)
      (key "scenario") (%write-json-string name stream) (separator)
      (progn (key "ranking_eligible") (write-string "false" stream) (separator) (key "cache_state")) (%write-json-string "warm" stream) (separator)
      (key "sample_unit")
      (%write-json-string "batch-average-ms-per-operation" stream)
      (separator)
      (key "raw_samples_ms_per_op") (%write-json-number-array latencies stream) (separator)
      (key "statistics_ms_per_op") (write-char #\{ stream)
      (key "min") (%write-json-number (getf statistics :minimum) stream) (separator)
      (key "p50") (%write-json-number (getf statistics :p50) stream) (separator)
      (key "p95") (%write-json-number (getf statistics :p95) stream) (separator)
      (key "p99") (%write-json-number (getf statistics :p99) stream) (separator)
      (key "max") (%write-json-number (getf statistics :maximum) stream) (separator)
      (key "mean") (%write-json-number (getf statistics :mean) stream) (separator)
      (key "mad") (%write-json-number (getf statistics :mad) stream)
      (write-char #\} stream) (separator)
      (key "timer") (write-char #\{ stream)
      (key "clock") (%write-json-string "get-internal-real-time" stream) (separator)
      (key "units_per_second") (format stream "~D" internal-time-units-per-second) (separator)
      (key "resolution_ms")
      (%write-json-number (/ 1000.0d0 internal-time-units-per-second) stream)
      (write-char #\} stream) (separator)
      (key "runtime") (write-char #\{ stream)
      (key "implementation") (%write-json-string (lisp-implementation-type) stream) (separator)
      (key "implementation_version")
      (%write-json-string (lisp-implementation-version) stream) (separator)
      (key "os") (%write-json-string (software-type) stream) (separator)
      (key "os_version") (%write-json-string (software-version) stream) (separator)
      (key "architecture") (%write-json-string (machine-type) stream)
      (write-char #\} stream) (separator)
      (key "parameters") (write-char #\{ stream)
      (key "warmup_batches") (format stream "~D" warmup) (separator)
      (key "samples") (format stream "~D" samples) (separator)
      (key "batch_size") (format stream "~D" batch) (separator)
      (key "warmup_iterations") (format stream "~D" (* warmup batch)) (separator)
      (key "measured_iterations") (format stream "~D" (* samples batch))
      (write-char #\} stream) (separator)
      (key "fixture") (write-char #\{ stream)
      (key "cardinality") (format stream "~D" fixture-cardinality) (separator)
      (key "expected_candidates") (format stream "~D" expected-count)
      (write-char #\} stream) (separator)
      (key "allocation_bytes_per_op")
      (if bytes-per-operation
          (%write-json-number bytes-per-operation stream)
          (write-string "null" stream))
      (separator)
      (key "checksums") (write-char #\{ stream)
      (key "latency") (format stream "~D" latency-checksum) (separator)
      (key "allocation") (format stream "~D" allocation-checksum)
      (write-char #\} stream))
    (write-char #\} stream)
    (terpri stream)
    (finish-output stream)))

(defun %measure-allocation (thunk operations)
  #+sbcl
  (progn
    (sb-ext:gc :full t)
    (let ((before (sb-ext:get-bytes-consed))
          (checksum 0))
      (dotimes (iteration operations)
        (declare (ignore iteration))
        (incf checksum (%result-checksum (funcall thunk))))
      (values (/ (- (sb-ext:get-bytes-consed) before)
                 (coerce operations 'double-float))
              checksum)))
  #-sbcl
  (progn
    (declare (ignore thunk operations))
    (values nil 0)))

(defun %print-result (name statistics bytes-per-operation latency-checksum allocation-checksum)
  (format t "~&~A (warm)~%" name)
  (format
    t
    "  latency ms/op: min=~,6F p50=~,6F p95=~,6F p99=~,6F max=~,6F mean=~,6F mad=~,6F~%"
    (getf statistics :minimum)
    (getf statistics :p50)
    (getf statistics :p95)
    (getf statistics :p99)
    (getf statistics :maximum)
    (getf statistics :mean)
    (getf statistics :mad))
  (if bytes-per-operation
      (format t "  allocation: ~,2F bytes/op~%" bytes-per-operation)
      (format t "  allocation: unsupported on this Lisp implementation~%"))
  (format
    t
    "  checksums: latency=~D allocation=~D~%"
    latency-checksum
    allocation-checksum))

(defun %run-workload
    (name fixture-cardinality thunk expected warmup samples batch jsonl-stream)
  (%assert-result name thunk expected)
  (%warm-up thunk warmup batch)
  (multiple-value-bind (latencies latency-checksum)
      (%measure-latency thunk samples batch)
    (multiple-value-bind (bytes-per-operation allocation-checksum)
        (%measure-allocation thunk (* samples batch))
      (%assert-result name thunk expected)
      (let ((statistics (%latency-statistics latencies)))
        (%print-result
          name statistics bytes-per-operation latency-checksum allocation-checksum)
        (when jsonl-stream
          (%write-json-result
            jsonl-stream name fixture-cardinality (length expected) statistics latencies
            bytes-per-operation latency-checksum allocation-checksum warmup samples batch))))))

(defun %run-cold-path-comparison (samples)
  (multiple-value-bind (sequential-thunk expected)
      (%make-cold-path-workload #'mapcar)
    (multiple-value-bind (cck-thunk cck-expected)
        (%make-cold-path-workload *path-command-directory-map-fn*)
      (declare (ignore cck-expected))
      (%assert-result "cold-path-sequential" sequential-thunk expected)
      (%assert-result "cold-path-cck" cck-thunk expected)
      (multiple-value-bind (sequential-latencies sequential-checksum)
          (%measure-latency sequential-thunk samples 1)
        (multiple-value-bind (cck-latencies cck-checksum)
            (%measure-latency cck-thunk samples 1)
          (let ((sequential-statistics (%latency-statistics sequential-latencies))
                (cck-statistics (%latency-statistics cck-latencies)))
            (format t "~&cold-path-sequential (cold)~%")
            (format
              t
              "  latency ms/op: p50=~,6F p95=~,6F~%"
              (getf sequential-statistics :p50)
              (getf sequential-statistics :p95))
            (format t "  checksum: ~D~%" sequential-checksum)
            (format t "cold-path-cck (cold)~%")
            (format
              t
              "  latency ms/op: p50=~,6F p95=~,6F~%"
              (getf cck-statistics :p50)
              (getf cck-statistics :p95))
            (format t "  checksum: ~D~%" cck-checksum)
            (format
              t
              "  speedup: p50=~,2Fx p95=~,2Fx~%"
              (/ (getf sequential-statistics :p50) (getf cck-statistics :p50))
              (/ (getf sequential-statistics :p95) (getf cck-statistics :p95)))))))))

(defun run-completion-benchmark (&key jsonl-stream)
  (let ((warmup (%positive-environment-integer "NSHELL_BENCH_WARMUP" +default-warmup+))
        (samples
          (%positive-environment-integer "NSHELL_BENCH_SAMPLES" +default-samples+))
        (batch (%positive-environment-integer "NSHELL_BENCH_BATCH" +default-batch+))
        (cold-samples
          (%positive-environment-integer
            "NSHELL_BENCH_COLD_SAMPLES"
            +default-cold-samples+)))
    (format t "~&nshell public completion benchmark~%")
    (format
      t
      "Reproduce: NSHELL_BENCH_MODE=warm NSHELL_BENCH_WARMUP=~D NSHELL_BENCH_SAMPLES=~D NSHELL_BENCH_BATCH=~D NSHELL_BENCH_COLD_SAMPLES=~D sbcl --script scripts/benchmark-completion.lisp~%"
      warmup
      samples
      batch
      cold-samples)
    (format
      t
      "~A ~A; ~A ~A; arch=~A; warmup=~D samples=~D batch=~D cold-samples=~D~%"
      (lisp-implementation-type)
      (lisp-implementation-version)
      (software-type)
      (software-version)
      (machine-type)
      warmup
      samples
      batch
      cold-samples)
    (format
      t
      "Scope: synthetic in-process completion API fixtures; not an end-to-end shell benchmark.~%")
    (format
      t
      "Cold PATH comparison uses eight synthetic directories; JSONL reports remain warm-only.~%")
    (format
      t
      "Each raw sample is the average ms/op for one batch; timer resolution is ~,9F ms.~%"
      (/ 1000.0d0 internal-time-units-per-second))
    (%run-cold-path-comparison cold-samples)
    (multiple-value-bind (thunk expected) (%make-fixed-kb-workload)
      (%run-workload "fixed-kb" 1100 thunk expected warmup samples batch jsonl-stream))
    (multiple-value-bind (thunk expected fixture-cardinality) (%make-fixed-rule-kb-workload)
      (%run-workload "fixed-rule-kb-production" fixture-cardinality thunk expected
                     warmup samples batch jsonl-stream))
    (multiple-value-bind (thunk expected) (%make-fixed-path-workload)
      (%run-workload "fixed-path-adapter" 2 thunk expected warmup samples batch jsonl-stream))
    (values)))
