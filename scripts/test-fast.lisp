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
                (asdf:load-system "nshell/test-unit")
                (uiop:symbol-call :nshell/test '#:run-tests
                                  :exclude-tags '(:slow)))
            (error (condition)
              (format *error-output* "~&nshell/test-unit failed: ~A~%" condition)
              nil))))
    (format t "~&NSHELL_TEST_FAST elapsed=~,3F seconds~%"
            (/ (- (get-internal-real-time) started-at)
               internal-time-units-per-second))
    (finish-output)
    (finish-output *error-output*)
    (sb-ext:exit :code (if passed-p 0 1))))
