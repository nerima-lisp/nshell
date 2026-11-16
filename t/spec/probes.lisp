(in-package #:nshell/spec)
(eval-when (:compile-toplevel :load-toplevel :execute)
    (defmacro register-language-probes ()
      (let* ((ids (%probe-ids-at-expansion))
             (rows *l7-rows*)
             (next-version-rows
               (remove-if-not (lambda (row) (getf row :v09)) rows)))
        (unless (= (length ids)
                   (length (remove-duplicates ids :test #'string=)))
          (error "Language-probe fixture IDs must be unique"))
        (unless (= 30 (length rows))
          (error "L7.1 must have 30 mapped rows, found ~d" (length rows)))
        (unless (= 8 (length next-version-rows))
          (error "Expected 8 next-version L7 expectations, found ~d"
                 (length next-version-rows)))
        (dolist (row rows)
          (unless (member (getf row :probe-id) ids :test #'string=)
            (error "L7 row ~d references unknown probe ~a"
                   (getf row :row) (getf row :probe-id))))
        (append
         (list 'progn)
         (mapcar (lambda (id)
                   (list 'it
                         (format nil "language-probe ~a" id)
                         (list '%check-fixture-case (list 'quote id))))
                 ids)
         (mapcar (lambda (row)
                   (list 'it-fails
                         (format nil "L7.1 row ~d probe ~a next-version"
                                 (getf row :row) (getf row :probe-id))
                         (list '%check-l7-next-version
                               (list 'quote (getf row :probe-id)))))
                 next-version-rows)))))
  (register-language-probes)