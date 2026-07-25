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
;;;; the Nix sandbox the systems are already on CL_SOURCE_REGISTRY, and for a
;;;; plain ghq checkout the parent directory tree is registered so sibling
;;;; checkouts (../cl-weave, ../cl-prolog, ...) are found automatically. An
;;;; explicit CL_SOURCE_REGISTRY still wins, because the existing configuration
;;;; is inherited rather than replaced.

(require :asdf)

(let* ((root (truename #P"./"))
       (parent (uiop:pathname-parent-directory-pathname root)))
  (asdf:initialize-source-registry
   `(:source-registry
     (:directory ,root)
     (:tree ,parent)
     :inherit-configuration))
  ;; Warn rather than abort on compile-file warnings: the suite's own failures
  ;; are the signal this script reports, and a style warning in a dependency
  ;; should not masquerade as a test failure.
  (setf asdf:*compile-file-warnings-behaviour* :warn
        asdf:*compile-file-failure-behaviour* :warn)
  (let ((passed-p
          (handler-case
              (progn
                (asdf:load-system "nshell/test")
                (uiop:symbol-call :nshell/test '#:run-tests))
            (error (condition)
              (format *error-output* "~&nshell/test failed: ~A~%" condition)
              nil))))
    (sb-ext:exit :code (if passed-p 0 1))))
