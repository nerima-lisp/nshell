;;;; Regenerate docs/src/reference/error-codes.md from the error-code table.
;;;;
;;;; Usage:  sbcl --script scripts/generate-error-codes-doc.lisp
;;;;
;;;; Needs only SBCL: it reads data/domain/error-codes-data.lisp with READ and
;;;; renders it with src/domain/error-code-table.lisp, which uses only CL. The
;;;; unit test error-codes-tests reads the table the same way and fails when
;;;; the committed page differs from what this script writes.

(defpackage #:nshell.domain.error-codes (:use #:cl))

(let* ((root (merge-pathnames
              "../" (make-pathname :name nil :type nil
                                   :defaults (or *load-truename* *load-pathname*))))
       (table (merge-pathnames "data/domain/error-codes-data.lisp" root))
       (output (merge-pathnames "docs/src/reference/error-codes.md" root)))
  (load (merge-pathnames "src/domain/error-code-table.lisp" root))
  (let ((markdown (funcall (find-symbol "RENDER-ERROR-CODES-MARKDOWN"
                                        '#:nshell.domain.error-codes)
                           (funcall (find-symbol "READ-ERROR-CODE-TABLE"
                                                 '#:nshell.domain.error-codes)
                                    table))))
    (with-open-file (stream output :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create
                                   :external-format :utf-8)
      (write-string markdown stream))
    (format t "~&Wrote docs/src/reference/error-codes.md~%")))
