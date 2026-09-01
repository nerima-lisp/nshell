;;;; Generate an sb-cover HTML report and a machine-readable src/ coverage gate.
;;;;
;;;; Usage:  sbcl --script scripts/coverage.lisp
;;;;
;;;; nshell/test depends on sibling nerima-lisp toolkit checkouts (cl-prolog-kit,
;;;; cl-parser-kit, ...). Inside `nix develop` those systems are already on the
;;;; ASDF source registry. For a plain local checkout we also register the
;;;; parent directory tree, so sibling ghq checkouts are discovered
;;;; automatically. When CL_SOURCE_REGISTRY is present (as it is in the Nix
;;;; development shell), register only this checkout and inherit that explicit
;;;; list. Without it, register the parent tree for a plain local checkout.
;;;;
;;;; :force :all is required, not :force t: :force t only forces recompiling
;;;; nshell/test itself, leaving the nshell (src/) dependency loaded from
;;;; cached, uninstrumented fasls -- sb-cover's coverage proclamation never
;;;; reaches src/, and the report silently covers only test files.
(require :asdf)

(load
 (merge-pathnames
  #P"asdf-runtime.lisp"
  (uiop:pathname-directory-pathname
   (or *load-truename* *load-pathname*))))
(nshell-configure-writable-asdf-output)

(require :sb-cover)

(declaim (optimize sb-cover:store-coverage-data))

(progn
  (defun %coverage-string-prefix-p (prefix string)
    (and (<= (length prefix) (length string)) (string= prefix string :end2 (length prefix))))
  (defun %next-coverage-row (text start end)
    (let ((odd (search "<tr class='odd'>" text :start2 start :end2 end))
          (even (search "<tr class='even'>" text :start2 start :end2 end)))
      (cond
        ((and odd even) (min odd even))
        (odd odd)
        (even even))))
  (defun %parse-coverage-row (text start end)
    (let* ((row-end (search "</tr>" text :start2 start :end2 end))
           (next-row
            (if row-end (+ row-end (length "</tr>"))
              end)))
      (if (null row-end) (values nil nil next-row)
        (let* ((row (subseq text start row-end))
               (covered-marker "</a></td><td>")
               (covered-position (search covered-marker row))
               (total-marker "</td><td>")
               (total-position
                (and
                 covered-position
                 (search total-marker row :start2 (+ covered-position (length covered-marker))))))
          (if (or (null covered-position) (null total-position)) (values nil nil next-row)
            (values
             (ignore-errors
              (parse-integer
               row
               :start
               (+ covered-position (length covered-marker))
               :junk-allowed
               t))
             (ignore-errors
              (parse-integer row :start (+ total-position (length total-marker)) :junk-allowed t))
             next-row))))))
  (defun %coverage-row-file-name (text start end)
    (let* ((row-end (search "</tr>" text :start2 start :end2 end))
           (row (and row-end (subseq text start row-end)))
           (link-marker "<a href='")
           (link-start (and row (search link-marker row)))
           (name-start (and link-start
                            (search ">" row :start2 (+ link-start (length link-marker)))))
           (name-end (and name-start (search "</a>" row :start2 (1+ name-start)))))
      (and name-start name-end (subseq row (1+ name-start) name-end))))
  (defparameter +coverage-excluded-source-file-names+
    '("package.lisp"
      "package-domain.lisp"
      "package-application.lisp"
      "package-infrastructure.lisp"
      "package-presentation.lisp"
      "package-domain-completion.lisp"))
  (defun %coverage-declarative-source-p (path)
    (let ((file-name (file-namestring (pathname path))))
      (or (search "/data/" path)
          (search "-data.lisp" file-name))))
  (defun %coverage-source-file-p (path source-root)
    (and (%coverage-string-prefix-p source-root path)
         (search "/src/" path)
         (not (%coverage-declarative-source-p path))
         (not (member (file-namestring (pathname path))
                      +coverage-excluded-source-file-names+
                      :test #'string=))))
  (defun %coverage-file-totals (index-path source-root)
    (let* ((html (uiop:read-file-string index-path))
           (section-marker "<tr class='subheading'><td colspan='7'>")
           (section-marker-length (length section-marker))
           (html-length (length html)))
      (loop with cursor = 0
            with files = nil
            for section-start = (search section-marker html :start2 cursor)
            while section-start
            do (let* ((path-start (+ section-start section-marker-length))
                      (path-end (or (search "</td></tr>" html :start2 path-start) html-length))
                      (path
                       (string-trim
                        '(#\Space #\Tab #\Newline #\Return)
                        (subseq html path-start path-end)))
                      (next-section (search section-marker html :start2 path-end))
                      (section-end (or next-section html-length))
                      (row-cursor path-end))
                 (setf cursor section-end)
                 (when (%coverage-source-file-p path source-root)
                   (loop for row-start = (%next-coverage-row html row-cursor section-end)
                         while row-start
                         do (multiple-value-bind (covered total next-row) (%parse-coverage-row
                                                                           html
                                                                           row-start
                                                                           section-end)
                              (let ((file-name (%coverage-row-file-name html row-start section-end)))
                                (setf row-cursor next-row)
                                (when (and file-name
                                           (%coverage-source-file-p
                                            (concatenate 'string path file-name)
                                            source-root)
                                           (integerp covered)
                                           (integerp total))
                                  (push (list (concatenate 'string path file-name)
                                               covered
                                               total)
                                        files)))))))
            finally (return (nreverse files)))))
  (defun %coverage-totals (files)
    (values (length files)
            (reduce #'+ files :key #'second :initial-value 0)
            (reduce #'+ files :key #'third :initial-value 0)))
  (defun %coverage-percentage (covered total)
    (if (plusp total) (* 100.0 (/ covered total))
      0.0))
  (defun %coverage-threshold (name default)
    (let ((raw (uiop:getenv name)))
      (if (null raw) default
        (let ((*read-eval* nil)
              (value (ignore-errors (read-from-string raw))))
          (if (and (realp value) (<= 0 value) (<= value 100)) (float value 1.0)
            (error "Invalid ~A value ~S; expected a number from 0 to 100." name raw))))))
  (defun %json-boolean (value)
    (if value "true"
      "false"))
  (defun %write-coverage-summary (pathname
                                  files
                                  covered
                                  total
                                  percentage
                                  minimum
                                  target
                                  tests-passed
                                  tests-selected)
    (ensure-directories-exist pathname)
    (with-open-file (stream
                     pathname
                     :direction
                     :output
                     :if-exists
                     :supersede
                     :if-does-not-exist
                     :create)
      (format
       stream
       "{~%  \"scope\": \"src-executable\",~%  \"files\": ~D,~%  \"covered\": ~D,~%  \"total\": ~D,~%  \"expression-percent\": ~,2F,~%  \"minimum-percent\": ~,2F,~%  \"target-percent\": ~,2F,~%  \"tests-selected\": ~D,~%  \"tests-passed\": ~A,~%  \"minimum-passed\": ~A,~%  \"target-reached\": ~A~%}~%"
       files
       covered
       total
       percentage
       minimum
       target
       tests-selected
       (%json-boolean tests-passed)
       (%json-boolean (and (plusp total) (>= percentage minimum)))
       (%json-boolean (and (plusp total) (>= percentage target))))))
  (defun %write-coverage-files (pathname files)
    (ensure-directories-exist pathname)
    (with-open-file (stream pathname :direction :output :if-exists :supersede :if-does-not-exist :create)
      (format stream "[~%")
      (loop for (path covered total) in files
            for first = t then nil
            do (unless first (format stream ",~%"))
               (format stream "  {\"path\": \"~A\", \"covered\": ~D, \"total\": ~D, \"expression-percent\": ~,2F}"
                       path covered total (%coverage-percentage covered total)))
      (format stream "~%]~%")))
  (let* ((root (truename #P"./"))
         (parent (uiop:pathname-parent-directory-pathname root))
         (tmpdir (uiop:getenv "TMPDIR"))
         (coverage-dir
          (uiop:ensure-directory-pathname
           (or
            (uiop:getenv "NSHELL_COVERAGE_DIR")
            (if tmpdir (merge-pathnames
                        #P"nshell-coverage/"
                        (uiop:ensure-directory-pathname tmpdir))
                (merge-pathnames #P"coverage/" root)))))
         (index-path (merge-pathnames #P"cover-index.html" coverage-dir))
         (summary-path (merge-pathnames #P"coverage-summary.json" coverage-dir))
         (files-path (merge-pathnames #P"coverage-files.json" coverage-dir))
         (source-root (uiop:native-namestring (truename (merge-pathnames #P"src/" root))))
         (minimum (%coverage-threshold "NSHELL_COVERAGE_MIN" 85.0))
         (target (%coverage-threshold "NSHELL_COVERAGE_TARGET" 100.0))
         (tests-selected 0)
         (tests-passed nil)
         (report-passed nil)
         (coverage-passed nil))
    (asdf:initialize-source-registry
     (if (uiop:getenv "CL_SOURCE_REGISTRY")
         `(:source-registry
           (:directory ,root)
           :inherit-configuration)
       `(:source-registry
         (:directory ,root)
         (:tree ,parent)
         :inherit-configuration)))
    (ensure-directories-exist coverage-dir)
    (sb-cover:enable-coverage-logging)
    (unwind-protect (setf tests-passed (handler-case
                                           (progn
                                             (asdf:load-system :nshell/test :force :all)
                                             (multiple-value-bind (result selected-count)
                                                 (uiop:symbol-call :nshell/test (quote #:run-tests))
                                               (unless (and (integerp selected-count)
                                                            (plusp selected-count))
                                                 (error "nshell test discovery selected no tests"))
                                               (setf tests-selected selected-count)
                                               (and result t)))
                                         (error (condition)
                                                (format *error-output*
                                                        "~&nshell/test failed: ~A~%"
                                                        condition)
                                                nil)))
                    (setf report-passed (handler-case (progn
                                                        (sb-cover:report coverage-dir)
                                                        t)
                                          (error (condition)
                                                 (format *error-output* "~&sb-cover report failed: ~A~%" condition)
                                                 nil))))
    (let ((file-totals (if report-passed (handler-case (%coverage-file-totals
                                                       index-path
                                                       source-root)
                                                                   (error (condition)
                                                                          (format
                                                                           *error-output*
                                                                           "~&coverage summary failed: ~A~%"
                                                                           condition)
                                                                          nil))
                                                   nil)))
      (multiple-value-bind (files covered total) (%coverage-totals file-totals)
      (let ((percentage (%coverage-percentage covered total)))
        (setf coverage-passed (and
                               report-passed
                               (plusp files)
                               (plusp total)
                               (plusp tests-selected)
                               (>= percentage minimum)))
        (%write-coverage-summary
         summary-path
         files
         covered
         total
         percentage
         minimum
         target
         tests-passed
         tests-selected)
        (%write-coverage-files files-path file-totals)
        (unless (probe-file summary-path)
          (error "coverage summary was not written: ~A" summary-path))
        (format t "NSHELL_COVERAGE_SUMMARY path=~A~%" summary-path)
        (format t "NSHELL_COVERAGE_FILES path=~A~%" files-path)
        (format
         t
         "NSHELL_COVERAGE scope=src-executable files=~D covered=~D total=~D expression-percent=~,2F minimum-percent=~,2F target-percent=~,2F tests-selected=~D tests-passed=~A minimum-passed=~A target-reached=~A~%"
         files
         covered
         total
         percentage
         minimum
         target
         tests-selected
         (%json-boolean tests-passed)
         (%json-boolean coverage-passed)
         (%json-boolean (and (plusp total) (>= percentage target))))
        (unless coverage-passed
          (format
           *error-output*
           "~&src executable expression coverage did not meet the configured minimum (~,2F%%).~%"
           minimum))))
    (finish-output)
    (finish-output *error-output*)
    (sb-ext:exit
     :code
     (if (and tests-passed coverage-passed) 0
         1)))))
