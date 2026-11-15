;;;; Run the unit, command-line, and static repository tests.
;;;; Usage: sbcl --script scripts/test-fast.lisp

(require :asdf)

(let* ((started-at (get-internal-real-time))
       (script-directory
         (uiop:pathname-directory-pathname
          (or *load-truename* *load-pathname*)))
       (root (uiop:pathname-parent-directory-pathname script-directory))
       (parent (uiop:pathname-parent-directory-pathname root)))
  (load (merge-pathnames #P"asdf-runtime.lisp" script-directory))
  (nshell-configure-writable-asdf-output)
  (asdf:initialize-source-registry
   (if (uiop:getenv "CL_SOURCE_REGISTRY")
       `(:source-registry
         (:directory ,root)
         :inherit-configuration)
       `(:source-registry
         (:directory ,root)
         (:tree ,parent)
         :inherit-configuration)))
  (setf asdf:*compile-file-warnings-behaviour* :warn
        asdf:*compile-file-failure-behaviour* :warn)
  (let ((passed-p
          (handler-case
              (progn
                (asdf:load-asd (merge-pathnames #P"nshell.asd" root))
                (asdf:load-system "nshell/test-unit")
                (let ((selected-count
                        (length
                         (uiop:symbol-call :cl-weave '#:list-tests
                                           :reporter :sexp
                                           :stream (make-string-output-stream)
                                           :exclude-tags '(:slow)))))
                  (unless (plusp selected-count)
                    (error "nshell unit test discovery selected no tests"))
                  (let* ((events
                           (uiop:symbol-call :cl-weave '#:run
                                             (uiop:symbol-call :cl-weave '#:root-suite)
                                             :reporter :spec
                                             :exclude-tags '(:slow)
                                             :max-workers 1
                                             :timeout-ms 120000))
                         (result (uiop:symbol-call :cl-weave '#:results-status events)))
                    (format t "~&NSHELL_TESTS selected=~D passed=~A~%"
                            selected-count result)
                    result)))
            (error (condition)
              (format *error-output* "~&nshell/test-unit failed: ~A~%" condition)
              nil))))
    (format t "~&NSHELL_TEST_FAST elapsed=~,3F seconds~%"
            (/ (- (get-internal-real-time) started-at)
               internal-time-units-per-second))
    (finish-output)
    (finish-output *error-output*)
    (sb-ext:exit :code (if passed-p 0 1))))
