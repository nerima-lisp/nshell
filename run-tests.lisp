;;;; Lisp-level entry point for the nshell test suite.
;;;;
;;;; Usage:  sbcl --script run-tests.lisp
;;;;
;;;; This is the single entry point the org standard requires at the repository
;;;; root. It is what `checks.default` and `apps.test` in flake.nix invoke, so
;;;; the hermetic Nix check and a plain local run execute exactly the same code
;;;; path rather than two hand-rolled `--eval` chains that drift apart.
;;;;
;;;; Dependency resolution mirrors scripts/weave.lisp: inside `nix develop` or
;;;; the Nix sandbox ASDF receives CL_SOURCE_REGISTRY from the environment. For
;;;; a plain ghq checkout the parent directory tree is registered so sibling
;;;; checkouts (../cl-weave, ../cl-prolog-kit, ...) are found automatically.

(require :asdf)

(load
 (merge-pathnames
  #P"scripts/asdf-runtime.lisp"
  (uiop:pathname-directory-pathname
   (or *load-truename* *load-pathname*))))
(nshell-configure-writable-asdf-output)

(let* ((root (uiop:pathname-directory-pathname
              (or *load-truename* *load-pathname*)))
       (parent (uiop:pathname-parent-directory-pathname root)))
  (unless (uiop:getenv "CL_SOURCE_REGISTRY")
    (asdf:initialize-source-registry
     `(:source-registry
       (:directory ,root)
       (:tree ,parent)
       :inherit-configuration)))
  ;; Warn rather than abort on compile-file warnings: the suite's own failures
  ;; are the signal this script reports, and a style warning in a dependency
  ;; should not masquerade as a test failure.
  (setf asdf:*compile-file-warnings-behaviour* :warn
        asdf:*compile-file-failure-behaviour* :warn)
  (let ((passed-p
          (handler-case
              (progn
                  (asdf:load-system "cl-prolog-kit")
                  (asdf:load-system "cl-weave")
                  (asdf:load-system "nshell/test" :force t)
                (multiple-value-bind (result selected-count)
                    (funcall (find-symbol "RUN-TESTS" "NSHELL/TEST"))
                  (unless (and (integerp selected-count)
                               (plusp selected-count))
                    (error "nshell test discovery selected no tests"))
                  result))
            (error (condition)
              (format *error-output* "~&nshell/test failed: ~A~%" condition)
              nil))))
    (finish-output)
    (finish-output *error-output*)
    (sb-ext:exit :code (if passed-p 0 1))))
