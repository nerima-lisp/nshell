(in-package #:nshell/spec)
(eval-when (:compile-toplevel :load-toplevel :execute)
    (defmacro register-language-probes ()
  (let* ((ids (%probe-ids-at-expansion))
         (rows *l7-rows*)
         (descriptors
           (loop for row in rows
                 append (cons row
                              (append (getf row :additional-probes)
                                      (getf row :additional-crash-probes)))))
         (p2-rows
           (remove-if-not
            (lambda (row) (getf (getf row :owner) :v08))
            descriptors))
         (current-behavior-rows
           (remove-if-not (lambda (row) (getf row :v08-current)) descriptors))
         (next-version-rows
           (remove-if-not (lambda (row) (getf row :v09)) rows))
         (warning-rows
           (remove-if-not (lambda (row) (getf row :warning)) descriptors))
         (crash-rows
           (remove-if-not (lambda (row) (getf row :crash)) descriptors))
         (crash-expectation-rows
           (remove-if-not (lambda (row) (getf row :crash-expectation))
                          descriptors)))
    (unless (= (length ids)
               (length (remove-duplicates ids :test #'string=)))
      (error "Language-probe fixture IDs must be unique"))
    (unless (= 30 (length rows))
      (error "L7.1 must have 30 mapped rows, found ~d" (length rows)))
    (dolist (row descriptors)
      (let* ((id (getf row :probe-id))
             (owners (getf (getf row :owner) :v08))
             (crash-owner (getf (getf row :owner) :crash)))
        (unless (member id ids :test #'string=)
          (error "L7 row references unknown probe ~a" id))
        (dolist (owner (if (listp owners) owners (and owners (list owners))))
          (unless (member owner '("S2" "S3" "S4" "S5") :test #'string=)
            (error "Unknown P2 owner ~a for probe ~a" owner id)))
        (when (and crash-owner (not (getf row :crash)))
          (error "Non-crash probe ~a has a crash owner" id))))
    (unless (= (length crash-rows)
               (length (remove-duplicates
                        (mapcar (lambda (row) (getf row :probe-id)) crash-rows)
                        :test #'string=)))
      (error "Crash probe IDs must be unique"))
    (dolist (row crash-rows)
      (when (and (getf (getf row :owner) :crash)
                 (not (member (getf (getf row :owner) :crash)
                              '("C")
                              :test #'string=)))
        (error "Unknown crash owner for probe ~a" (getf row :probe-id))))
    (labels ((owner-label (owner)
               (if (listp owner)
                   (format nil "~{~a~^/~}" owner)
                   owner)))
      (append
       (list 'progn
             (list 'it
                   "the fixed t/spec false executable exits 1"
                   (list '%check-spec-false-exits-nonzero)))
       (mapcar
        (lambda (id)
          (list 'it
                (format nil "language-probe ~a v0.7.0 baseline" id)
                (list '%check-fixture-baseline (list 'quote id))))
        (remove-if (lambda (id)
                     (getf (find id descriptors
                                 :key (lambda (row) (getf row :probe-id))
                                 :test #'string=)
                           :v07-baseline-skip))
                   ids))
       (mapcar
        (lambda (row)
          (let ((id (getf row :probe-id)))
            (list 'it
                  (format nil "L7.1 row ~a probe ~a current v0.8 behavior"
                          (getf row :row) id)
                  (list '%check-l7-v08 (list 'quote id)))))
        current-behavior-rows)
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
          (let* ((id (getf row :probe-id))
                 (owner (getf (getf row :owner) :warning)))
            (list 'it-fails
                  (format nil "L7.1 row ~a probe ~a [~a warning]"
                          (getf row :row) id (owner-label owner))
                  (list '%check-l7-next-version
                        (list 'quote id)
                        :warning))))
        warning-rows)
       (mapcar
        (lambda (row)
          (let* ((id (getf row :probe-id))
                 (owner (getf (getf row :owner) :error)))
            (list 'it-fails
                  (format nil "L7.1 row ~a probe ~a [~a E_ARG_TYPE]"
                          (getf row :row) id (owner-label owner))
                  (list '%check-l7-next-version
                        (list 'quote id)
                        :crash-expectation))))
        crash-expectation-rows)
       (mapcar
        (lambda (row)
          (let* ((id (getf row :probe-id))
                 (owner (getf (getf row :owner) :crash))
                 (check (list '%check-l7-next-version
                              (list 'quote id)
                              :crash)))
            (if owner
                (list 'it-fails
                      (format nil "stderr crash log is absent for ~a [~a]" id
                              (owner-label owner))
                      check)
                (list 'it
                      (format nil "stderr crash log is absent for ~a" id)
                      check))))
        crash-rows)))))
)
  (register-language-probes)