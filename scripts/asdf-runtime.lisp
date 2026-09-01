;;;; Shared ASDF runtime configuration for read-only source trees.

(require :asdf)

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
    output-root))
