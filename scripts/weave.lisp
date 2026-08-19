;;;; Run the cl-weave regression suite (nshell/weave).
;;;;
;;;; Usage:  sbcl --script scripts/weave.lisp
;;;;
;;;; Beyond cl-weave and cl-prolog, this suite also depends on cl-prolog/weave.
;;;; The ASDF source and output configuration is shared with run-tests.lisp and
;;;; the coverage and benchmark entry points.

(require :asdf)

(let* ((script-path (truename (or *load-truename*
                                 *load-pathname*
                                 #P"./scripts/weave.lisp")))
       (script-directory (uiop:pathname-directory-pathname script-path))
       (root (uiop:pathname-parent-directory-pathname script-directory)))
  (load (merge-pathnames #P"asdf-runtime.lisp" script-directory))
  (nshell-configure-runtime root)
  (let ((passed-p
          (handler-case
              (progn
                (asdf:load-system :nshell/weave :force t)
                (funcall (find-symbol "RUN" "NSHELL/WEAVE") :reporter :spec))
            (error (condition)
              (format *error-output* "~&nshell/weave failed: ~A~%" condition)
              nil))))
    (sb-ext:exit :code (if passed-p 0 1))))
