;;;; Shared ASDF runtime configuration for read-only source trees.

(require :asdf)
(require :sb-posix)

(defun nshell-configure-writable-asdf-output ()
  "Route compiled systems to a writable directory before loading them."
  (let* ((configured-root (uiop:getenv "NSHELL_ASDF_OUTPUT_DIR"))
         (output-root
           (uiop:ensure-directory-pathname
            (or configured-root
                (merge-pathnames
                 (format nil "nshell-asdf-~36R/" (random most-positive-fixnum))
                                 (uiop:temporary-directory))))))
    (ensure-directories-exist output-root)
    ;; PTY-spawned SBCL children must use the same compiled artifacts as the
    ;; runner. Their ASDF image starts fresh, so the output translation itself
    ;; is passed through the environment and re-established by test bootstrap.
    (sb-posix:setenv "NSHELL_ASDF_OUTPUT_DIR" (namestring output-root) 1)
    (asdf:initialize-output-translations
     `(:output-translations
       (t ,(merge-pathnames "**/*.*" output-root))
       :ignore-inherited-configuration))
    output-root))
