;;;; Run the cl-weave regression suite (nshell/weave).
;;;;
;;;; Usage:  sbcl --script scripts/weave.lisp
;;;;
;;;; Beyond cl-weave and cl-prolog, this suite also depends on cl-prolog/weave.
;;;; Inside `nix develop` those systems are already on the
;;;; ASDF source registry.  For a plain local checkout we also register the
;;;; parent directory tree, so sibling ghq checkouts (../cl-weave, ../cl-prolog)
;;;; are discovered automatically.  An explicit CL_SOURCE_REGISTRY still wins
;;;; because we inherit the existing configuration.

(require :asdf)
(asdf:load-system :cl-host-kit)

(let* ((root (truename #P"./"))
       (parent (host-kit:parent-directory-pathname root)))
  (asdf:initialize-source-registry
   (if (host-kit:getenv "CL_SOURCE_REGISTRY")
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
                (asdf:load-system :nshell/weave :force t)
                (funcall (find-symbol "RUN" "NSHELL/WEAVE") :reporter :spec))
            (error (condition)
              (format *error-output* "~&nshell/weave failed: ~A~%" condition)
              nil))))
    (sb-ext:exit :code (if passed-p 0 1))))
