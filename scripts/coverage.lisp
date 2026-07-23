;;;; Generate an sb-cover HTML report for the nshell/test suite.
;;;;
;;;; Usage:  sbcl --script scripts/coverage.lisp
;;;;
;;;; Beyond cl-weave, this suite depends on sibling nerima-lisp toolkit
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
(require :sb-cover)

(declaim (optimize sb-cover:store-coverage-data))

(let* ((root (truename #P"./"))
       (parent (uiop:pathname-parent-directory-pathname root))
       (coverage-dir
         (uiop:ensure-directory-pathname
          (or (uiop:getenv "NSHELL_COVERAGE_DIR")
              (merge-pathnames #P"coverage/" root))))
       (passed-p nil))
  (asdf:initialize-source-registry
   `(:source-registry
     (:directory ,root)
     (:tree ,parent)
     :inherit-configuration))
  (sb-cover:enable-coverage-logging)
  (unwind-protect
       (setf passed-p
             (handler-case
                 (progn
                    (asdf:load-system :nshell/test :force :all)
                    ;; Drive the cl-weave suite for its coverage side effects;
                    ;; the report is produced regardless of pass/fail.
                    (uiop:symbol-call :nshell/test '#:run-tests)
                    t)
                (error (condition)
                  (format *error-output* "~&nshell/test failed: ~A~%" condition)
                  nil)))
    (sb-cover:report coverage-dir))
  (sb-ext:exit :code (if passed-p 0 1)))
