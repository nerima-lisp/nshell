;;;; Generate an sb-cover HTML report for all nshell test suites.
;;;;
;;;; Usage:  sbcl --script scripts/coverage.lisp
;;;;
;;;; Beyond cl-weave and cl-prolog, these suites depend on sibling nerima-lisp toolkit
;;;; checkouts (cl-prolog, cl-parser-kit, ...). Inside `nix develop` those
;;;; systems are already on the ASDF source registry. For a plain local
;;;; checkout we also register the parent directory tree, so sibling ghq
;;;; checkouts (../cl-weave, ../cl-prolog, ...) are discovered automatically,
;;;; mirroring scripts/weave.lisp. An explicit CL_SOURCE_REGISTRY still wins
;;;; because we inherit the existing configuration.
;;;;
;;;; :force :all is required, not :force t: :force t only forces recompiling
;;;; nshell/test itself, leaving the nshell (src/) dependency loaded from
;;;; cached, uninstrumented fasls -- sb-cover's coverage proclamation never
;;;; reaches src/, and the report silently covers only test files.
(require :asdf)
(asdf:load-system :cl-host-kit)

(require :sb-cover)

(declaim (optimize sb-cover:store-coverage-data))

(let* ((root (truename #P"./"))
       (parent (host-kit:parent-directory-pathname root))
       (coverage-dir
        (host-kit:ensure-directory-pathname
         (or (host-kit:getenv "NSHELL_COVERAGE_DIR")
             (merge-pathnames #P"coverage/" root))))
       (passed-p nil)
       (report-path nil))
  (asdf:initialize-source-registry
   (if (host-kit:getenv "CL_SOURCE_REGISTRY")
       `(:source-registry
         (:directory ,root)
         :inherit-configuration)
       `(:source-registry
         (:directory ,root)
         (:tree ,parent)
         :inherit-configuration)))
  (sb-cover:enable-coverage-logging)
  (unwind-protect
      (setf passed-p
            (handler-case
                (progn
                  (asdf:load-system :nshell/test :force :all)
                  ;; Keep instrumented nshell sources loaded while refreshing the
                  ;; independent weave test system.
                  (asdf:load-system :nshell/weave :force t)
                  (let ((all-passed-p t))
                    (dolist (suite (list :nshell/test :nshell/weave))
                      (unless (handler-case
                                  (ecase suite
                                    (:nshell/test
                                     (funcall (find-symbol "RUN-TESTS" "NSHELL/TEST")))
                                    (:nshell/weave
                                     (funcall (find-symbol "RUN" "NSHELL/WEAVE")
                                              :reporter :spec)))
                                (error (condition)
                                  (format *error-output*
                                          "~&~(~A~) failed: ~A~%" suite condition)
                                  nil))
                        (setf all-passed-p nil)))
                    all-passed-p))
              (error (condition)
                (format *error-output* "~&Coverage setup failed: ~A~%" condition)
                nil)))
    (handler-case
        (setf report-path (sb-cover:report coverage-dir))
      (error (condition)
        (format *error-output* "~&Coverage report failed: ~A~%" condition)
        (setf passed-p nil))))
  (unless (and report-path (probe-file report-path))
    (format *error-output* "~&Coverage report was not written to ~A~%" coverage-dir)
    (setf passed-p nil))
  (when report-path
    (format t "~&Coverage report: ~A~%" report-path))
  (sb-ext:exit :code (if passed-p 0 1)))
