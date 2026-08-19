;;;; Lisp-level entry point for the nshell test suite.
;;;;
;;;; Usage:  sbcl --script run-tests.lisp
;;;;
;;;; This is the single entry point the org standard requires at the repository
;;;; root. It is what `checks.default` and `apps.test` in flake.nix invoke, so
;;;; the hermetic Nix check and a plain local run execute exactly the same code
;;;; path rather than two hand-rolled `--eval` chains that drift apart.
;;;;
;;;; Dependency resolution is shared with the auxiliary scripts through
;;;; scripts/asdf-runtime.lisp. An explicit CL_SOURCE_REGISTRY still wins;
;;;; otherwise NSHELL_SOURCE_TREE opts into one explicit sibling-system tree.

(require :asdf)

(let* ((script-path (truename (or *load-truename*
                                 *load-pathname*
                                 #P"./run-tests.lisp")))
       (root (uiop:pathname-directory-pathname script-path)))
  (load (merge-pathnames #P"scripts/asdf-runtime.lisp" root))
  (format *error-output* "~&[nshell] configure runtime~%")
  (finish-output *error-output*)
  (nshell-configure-runtime root)
  (format *error-output* "~&[nshell] load nshell/test~%")
  (finish-output *error-output*)
  (asdf:load-system "nshell/test")
  (format *error-output* "~&[nshell] run tests~%")
  (finish-output *error-output*)
  (let ((runner (find-symbol "RUN-TESTS" "NSHELL/TEST")))
    (unless (and runner (fboundp runner))
      (error "NSHELL/TEST:RUN-TESTS is not available."))
    (unless (funcall runner)
      (error "nshell/test reported failure.")))
  (format *error-output* "~&[nshell] tests passed~%")
  (finish-output *error-output*)
  (sb-ext:exit :code 0))
