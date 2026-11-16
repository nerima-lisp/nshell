(in-package #:nshell/spec)
(eval-when (:compile-toplevel :load-toplevel :execute)
    (defmacro register-language-probes ()
  (let* ((ids (%probe-ids-at-expansion))
         (rows *l7-rows*)
         (descriptors
           (loop for row in rows
                 append (cons row (getf row :additional-probes))))
         (p2-rows
           (remove-if-not
            (lambda (row) (getf (getf row :owner) :v08))
            descriptors))
         (next-version-rows
           (remove-if-not (lambda (row) (getf row :v09)) rows))
         (warning-rows
           (remove-if-not (lambda (row) (getf row :warning)) descriptors))
         (crash-rows
           (remove-if-not (lambda (row) (getf row :crash)) descriptors))
         (crash-baseline-rows
           (remove-if-not (lambda (row) (getf row :crash-baseline)) rows)))
    (unless (= (length ids)
               (length (remove-duplicates ids :test #'string=)))
      (error "Language-probe fixture IDs must be unique"))
    (unless (= 30 (length rows))
      (error "L7.1 must have 30 mapped rows, found ~d" (length rows)))
    (dolist (row descriptors)
      (let ((id (getf row :probe-id))
            (owners (getf (getf row :owner) :v08)))
        (unless (member id ids :test #'string=)
          (error "L7 row references unknown probe ~a" id))
        (dolist (owner (if (listp owners) owners (and owners (list owners))))
          (unless (member owner '("S2" "S3" "S4" "S5") :test #'string=)
            (error "Unknown P2 owner ~a for probe ~a" owner id)))))
    (let ((crash-probe-ids
            (remove-duplicates
             (append (mapcar (lambda (row) (getf row :probe-id)) crash-rows)
                     '("loop-upper" "time-head"))
             :test #'string=)))
      (dolist (id crash-probe-ids)
        (unless (member id ids :test #'string=)
          (error "Crash probe references unknown fixture ~a" id)))
      (labels ((owner-label (owner)
                 (if (listp owner)
                     (format nil "~{~a~^/~}" owner)
                     owner)))
        (append
         (list 'progn)
         (mapcar
          (lambda (id)
            (list 'it
                  (format nil "language-probe ~a v0.7.0 baseline" id)
                  (list '%check-fixture-baseline (list 'quote id))))
          ids)
         (mapcar
          (lambda (row)
            (let* ((id (getf row :probe-id))
                   (owner (getf (getf row :owner) :v08))
                   (note (getf row :note)))
              (list 'it-fails
                    (format nil "language-probe ~a [P2 ~a]~@[ - ~a~]"
                            id (owner-label owner) note)
                    (list '%check-l7-v08 (list 'quote id)))))
          p2-rows)
         (mapcar
          (lambda (row)
            (let ((id (getf row :probe-id)))
              (list 'it-fails
                    (format nil "L7.1 row ~a probe ~a next-version"
                            (getf row :row) id)
                    (list '%check-l7-next-version
                          (list 'quote id)
                          :next-version))))
          next-version-rows)
         (mapcar
          (lambda (row)
            (let ((id (getf row :probe-id)))
              (list 'it-fails
                    (format nil "L7.1 row ~a probe ~a [S6 warning]"
                            (getf row :row) id)
                    (list '%check-l7-next-version
                          (list 'quote id)
                          :warning))))
          warning-rows)
         (mapcar
          (lambda (row)
            (let ((id (getf row :probe-id)))
              (list 'it
                    (format nil "crash-probe baseline ~a" id)
                    (list '%check-l7-next-version
                          (list 'quote id)
                          :crash-baseline))))
          crash-baseline-rows)
         (mapcar
          (lambda (id)
            (list 'it-fails
                  (format nil "stderr crash log is absent for ~a [P0-4 C]" id)
                  (list '%check-l7-next-version
                        (list 'quote id)
                        :crash)))
          crash-probe-ids)))))))
  (register-language-probes)