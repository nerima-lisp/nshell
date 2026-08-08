(require :asdf)
(asdf:load-system :cl-host-kit)

(let* ((root (truename #P"./"))
       (parent (host-kit:parent-directory-pathname root))
       (jsonl-path (host-kit:getenv "NSHELL_BENCH_JSONL"))
       (mode (string-downcase (or (host-kit:getenv "NSHELL_BENCH_MODE") "warm"))))
  (asdf:initialize-source-registry
   (if (host-kit:getenv "CL_SOURCE_REGISTRY")
       (list :source-registry
             (list :directory root)
             :inherit-configuration)
       (list :source-registry
             (list :directory root)
             (list :tree parent)
             :inherit-configuration)))
  (setf asdf:*compile-file-warnings-behaviour* :warn
        asdf:*compile-file-failure-behaviour* :warn)
  (handler-case
      (progn
        (unless (member mode '("warm" "process" "all") :test #'string=)
          (error "NSHELL_BENCH_MODE must be warm, process, or all (got ~S)" mode))
        (asdf:load-system :nshell/benchmark :force t)
        (labels ((run (stream)
                   (when (member mode '("warm" "all") :test #'string=)
                     (funcall (find-symbol "RUN-COMPLETION-BENCHMARK" "NSHELL/BENCHMARK")
                              :jsonl-stream stream))
                   (when (member mode '("process" "all") :test #'string=)
                     (funcall (find-symbol "RUN-PROCESS-BENCHMARK" "NSHELL/BENCHMARK")
                              :jsonl-stream (or stream *standard-output*)))))
          (if (and jsonl-path (plusp (length jsonl-path)))
              (progn
  (format t "~&JSONL output: ~A~%" jsonl-path)
  (let ((failure nil))
    (with-open-file (stream jsonl-path :direction :output :if-exists :supersede
                            :if-does-not-exist :create :external-format :utf-8)
      (handler-case
          (run stream)
        (error (condition)
          (setf failure condition))))
    (when failure
      (error failure))))
              (run nil)))
        (sb-ext:exit :code 0))
    (error (condition)
      (format *error-output* "~&nshell benchmark failed: ~A~%" condition)
      (sb-ext:exit :code 1))))
