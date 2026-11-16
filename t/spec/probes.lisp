(in-package #:nshell/spec)
(eval-when (:compile-toplevel :load-toplevel :execute)
    (defmacro register-language-probes ()
      (let* ((ids (%probe-ids-at-expansion))
             (rows *l7-rows*)
             (next-version-rows
               (remove-if-not (lambda (row) (getf row :v09)) rows))
             (p2-owners
               '(("print-top" . "S3")
                 ("kw-arg" . "S4")
                 ("escaped-sym" . "S2")
                 ("dollar-braced" . "S2")
                 ("unquote-atoms" . "S4")
                 ("pipe-mixed-2" . "S3")
                 ("bare-fish-if" . "S3")
                 ("bare-paren-mid" . "S2")
                 ("loop-cmd" . "S2")
                 ("loop-upper" . "S2")
                 ("and-cmd" . "S4")
                 ("defun-sym-args" . "S4")
                 ("var-dollar-in-value" . "S4")
                 ("redir-2to1" . "S2")
                 ("redir-value-target" . "S2")
                 ("bg-sexp" . "S2")
                 ("bare-var-list" . "S2")
                 ("nested-cmd-arg" . "S4")
                 ("time-head" . "S4")
                 ("sharp-eq" . "S2")
                 ("mid-dollar" . "S2")))
             (current-defects
               '(("pipe-mixed-1" . "exit status"))))
        (unless (= (length ids)
                   (length (remove-duplicates ids :test #'string=)))
          (error "Language-probe fixture IDs must be unique"))
        (unless (= 30 (length rows))
          (error "L7.1 must have 30 mapped rows, found ~d" (length rows)))
        (unless (= 8 (length next-version-rows))
          (error "Expected 8 next-version L7 expectations, found ~d"
                 (length next-version-rows)))
        (unless (= 21 (length p2-owners))
          (error "Expected 21 pending P2 expectations, found ~d"
                 (length p2-owners)))
        (unless (= 1 (length current-defects))
          (error "Expected 1 current implementation defect, found ~d"
                 (length current-defects)))
        (dolist (row rows)
          (unless (member (getf row :probe-id) ids :test #'string=)
            (error "L7 row ~d references unknown probe ~a"
                   (getf row :row) (getf row :probe-id))))
        (dolist (entry (append p2-owners current-defects))
          (unless (member (car entry) ids :test #'string=)
            (error "Language-probe classification references unknown probe ~a"
                   (car entry))))
        (append
         (list 'progn)
         (mapcar
          (lambda (id)
            (let ((owner (cdr (assoc id p2-owners :test #'string=)))
                  (defect (cdr (assoc id current-defects :test #'string=))))
              (list (if (or owner defect) 'it-fails 'it)
                    (cond
                      (owner
                       (format nil "language-probe ~a [P2 ~a]" id owner))
                      (defect
                       (format nil "language-probe ~a [current defect: ~a]"
                               id defect))
                      (t
                       (format nil "language-probe ~a" id)))
                    (list '%check-fixture-case (list 'quote id)))))
          ids)
         (mapcar (lambda (row)
                   (list 'it-fails
                         (format nil "L7.1 row ~d probe ~a next-version"
                                 (getf row :row) (getf row :probe-id))
                         (list '%check-l7-next-version
                               (list 'quote (getf row :probe-id)))))
                 next-version-rows)))))
  (register-language-probes)