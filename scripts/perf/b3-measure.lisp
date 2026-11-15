;;;; Driver for scripts/perf/b3-measure.sh. Run it only through that script:
;;;; it expects the environment the script prepares.

(require :asdf)
(require :sb-posix)

(defun b3-env (name &optional default)
  (let ((value (sb-posix:getenv name)))
    (if (and value (plusp (length value))) value default)))

(defun b3-fail (control &rest arguments)
  (format *error-output* "~&b3-measure: ~?~%" control arguments)
  (finish-output *error-output*)
  (sb-ext:exit :code 2 :abort t))

(defun b3-inside-p (path root)
  (let ((path (namestring (truename path)))
        (root (namestring (truename root))))
    (and (<= (length root) (length path))
         (string= root path :end2 (length root)))))

(let* ((tree (uiop:ensure-directory-pathname (b3-env "B3_SOURCE_TREE")))
       (key-cost-source (pathname (b3-env "B3_KEY_COST_SOURCE")))
       (fasl-root (uiop:ensure-directory-pathname (b3-env "B3_FASL_DIR")))
       (output (b3-env "B3_OUTPUT")))
  (asdf:initialize-output-translations
   `(:output-translations
     (t ,(merge-pathnames "**/*.*" fasl-root))
     :ignore-inherited-configuration))
  ;; The tree under test comes first so a store copy of nshell in the
  ;; dependency registry cannot shadow it; the check below proves it did not.
  (asdf:initialize-source-registry
   `(:source-registry
     (:directory ,tree)
     :inherit-configuration))
  (setf asdf:*compile-file-warnings-behaviour* :warn
        asdf:*compile-file-failure-behaviour* :warn)
  (handler-case (asdf:load-system "nshell")
    (error (condition) (b3-fail "loading nshell from ~a failed: ~a" tree condition)))
  (let ((asd (asdf:system-source-file "nshell")))
    (unless (b3-inside-p asd tree)
      (b3-fail "nshell resolved to ~a, outside the tree under test ~a" asd tree))
    (format *error-output* "~&b3-measure: nshell loaded from ~a~%" asd))
  (let ((fasl (merge-pathnames "b3-key-cost/key-cost.fasl" fasl-root)))
    (ensure-directories-exist fasl)
    (multiple-value-bind (compiled warnings-p failure-p)
        (compile-file key-cost-source :output-file fasl)
      (declare (ignore warnings-p))
      (when (or (null compiled) failure-p)
        (b3-fail "compiling ~a failed" key-cost-source))
      (load compiled)))
  (unless (funcall (find-symbol "LIBC-COUNTER-AVAILABLE-P" "NSHELL.PERF.KEY-COST"))
    (b3-fail "the libc counter is not loaded; DYLD_INSERT_LIBRARIES did not reach SBCL"))
  (let ((names (let ((value (b3-env "B3_SCENARIOS")))
                 (and value (uiop:split-string value :separator ",")))))
    (handler-case
        (funcall (find-symbol "MAIN" "NSHELL.PERF.KEY-COST")
                 output
                 :samples (parse-integer (b3-env "B3_SAMPLES" "30"))
                 :warmup (parse-integer (b3-env "B3_WARMUP" "3"))
                 :history-count (parse-integer (b3-env "B3_HISTORY_COUNT" "10000"))
                 :big-entry-count (parse-integer (b3-env "B3_BIG_ENTRIES" "20000"))
                 :uptime (b3-env "B3_UPTIME" "")
                 :names names)
      (error (condition) (b3-fail "measurement failed: ~a" condition))))
  (finish-output *error-output*)
  (sb-ext:exit :code 0))
