;;;; Run the in-process benchmarks of bench/ against the nshell system of a
;;;; given source tree. Driven by legacy-bench.sh through the environment:
;;;;   LEGACY_TREE      source tree whose nshell system is measured
;;;;   LEGACY_CHECKOUT  checkout whose bench/*.lisp is compiled and run
;;;;   LEGACY_FASL_DIR  output directory for the compiled bench files
;;;;   LEGACY_OUTPUT    JSONL output path
;;;;   LEGACY_MODE      warm, process or all
;;;; The bench code comes from LEGACY_CHECKOUT so that an older tree with a
;;;; stale bench/ can still be measured with the current benchmark code.

(require :asdf)
(require :sb-posix)

(defun %env (name)
  (let ((value (sb-posix:getenv name)))
    (when (or (null value) (zerop (length value)))
      (format *error-output* "legacy-bench: ~A is not set~%" name)
      (sb-ext:exit :code 2 :abort t))
    value))

(let* ((tree (uiop:ensure-directory-pathname (%env "LEGACY_TREE")))
       (checkout (uiop:ensure-directory-pathname (%env "LEGACY_CHECKOUT")))
       (fasl-dir (uiop:ensure-directory-pathname (%env "LEGACY_FASL_DIR")))
       (output (%env "LEGACY_OUTPUT"))
       (mode (string-downcase (%env "LEGACY_MODE"))))
  (unless (member mode '("warm" "process" "all") :test #'string=)
    (format *error-output* "legacy-bench: LEGACY_MODE must be warm, process or all, got ~S~%" mode)
    (sb-ext:exit :code 2 :abort t))
  (asdf:initialize-source-registry
   `(:source-registry (:directory ,tree) :inherit-configuration))
  (handler-case
      (progn
        (asdf:load-system "cl-host-kit")
        (asdf:load-system "nshell")
        ;; Prove the measured nshell is the requested tree, not a copy found
        ;; elsewhere on the registry.
        (let ((loaded (truename (asdf:system-source-directory "nshell"))))
          (unless (equal loaded (truename tree))
            (error "nshell was loaded from ~A, expected ~A" loaded tree))
          (format t "~&nshell source: ~A~%bench source: ~Abench/~%" loaded (truename checkout)))
        (ensure-directories-exist fasl-dir)
        (dolist (name '("package" "completion" "process"))
          (let ((source (merge-pathnames (format nil "bench/~A.lisp" name) checkout)))
            (multiple-value-bind (fasl warnings-p failure-p)
                (compile-file source :output-file (merge-pathnames (format nil "~A.fasl" name) fasl-dir))
              (declare (ignore warnings-p))
              (when failure-p
                (error "compiling ~A failed" source))
              (load fasl))))
        (with-open-file (stream output :direction :output :if-exists :supersede
                                       :if-does-not-exist :create :external-format :utf-8)
          (when (member mode '("warm" "all") :test #'string=)
            (funcall (find-symbol "RUN-COMPLETION-BENCHMARK" "NSHELL/BENCHMARK") :jsonl-stream stream))
          (when (member mode '("process" "all") :test #'string=)
            (funcall (find-symbol "RUN-PROCESS-BENCHMARK" "NSHELL/BENCHMARK") :jsonl-stream stream)))
        (format t "~&JSONL output: ~A~%" output)
        (sb-ext:exit :code 0))
    (error (condition)
      (format *error-output* "~&legacy-bench failed: ~A~%" condition)
      (sb-ext:exit :code 1 :abort t))))
