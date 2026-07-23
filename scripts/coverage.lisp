(require :asdf)
(require :sb-cover)

(declaim (optimize sb-cover:store-coverage-data))

(let* ((root (truename #P"./"))
       (coverage-dir
         (uiop:ensure-directory-pathname
          (or (uiop:getenv "NSHELL_COVERAGE_DIR")
              (merge-pathnames #P"coverage/" root))))
       (passed-p nil))
  (pushnew root asdf:*central-registry* :test #'equal)
  (sb-cover:enable-coverage-logging)
  (unwind-protect
       (setf passed-p
             (handler-case
                 (progn
                    (asdf:load-system :nshell/test :force t)
                    ;; Drive the cl-weave suite for its coverage side effects;
                    ;; the report is produced regardless of pass/fail.
                    (uiop:symbol-call :nshell/test '#:run-tests)
                    t)
                (error (condition)
                  (format *error-output* "~&nshell/test failed: ~A~%" condition)
                  nil)))
    (sb-cover:report coverage-dir))
  (sb-ext:exit :code (if passed-p 0 1)))
