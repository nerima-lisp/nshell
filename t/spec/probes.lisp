(in-package #:nshell/spec)

;;; Generation invariant:
;;; - the fixed bin directory's false exits 1;
;;; - a JSON case gets "language-probe ID v0.7.0 baseline" unless it is the
;;;   probe of a row whose :v08 :expect is not :v07, or of a *probe-changes*
;;;   entry (warning mode :optional when that :v07 row has a :warning, :none
;;;   otherwise);
;;; - every row and probe change gets one v0.8 test, `it` without owners and
;;;   `it-fails` with, except a :deferred probe change;
;;; - every row and probe change with :v09 gets an `it-fails` v0.9.0 test;
;;; - every crash probe gets "no crash log for ID", `it-fails` with an owner.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *row-owners* '("S2" "S3" "S4" "S5" "S6" "F3"))
  (defparameter *crash-owners* '("C"))
  (defparameter *unsettled-reasons*
    '(:design-conflict :format-undecided :behaviour-undefined :rule-scope))

  (defun %plist-keys-within (plist keys where)
    (unless (and (listp plist) (evenp (length plist)))
      (error "~a: expected a plist, got ~s" where plist))
    (loop for (key) on plist by #'cddr
          unless (member key keys)
            do (error "~a: unknown key ~s" where key)))

  (defun %design-file (name)
    ;; Bare chapter names (L7-diff-and-migration.md) live under their
    ;; directory; any other path is relative to docs/design/.
    (let ((directory (and (not (find #\/ name))
                          (cdr (assoc (char name 0)
                                      '((#\L . "language/") (#\U . "ux/")
                                        (#\I . "inventory/")))))))
      (merge-pathnames (concatenate 'string "docs/design/" directory name)
                       (asdf:system-source-directory "nshell"))))

  (defun %file-line-count (pathname)
    (with-open-file (stream pathname :external-format :utf-8)
      (loop while (read-line stream nil nil) count t)))

  (defun %basis-entry-error (entry)
    ;; Returns NIL when ENTRY is a valid citation, otherwise the reason.
    (let* ((colon (position #\: entry :from-end t))
           (file (and colon (subseq entry 0 colon)))
           (line (and colon (< (1+ colon) (length entry))
                      (every #'digit-char-p (subseq entry (1+ colon)))
                      (parse-integer entry :start (1+ colon)))))
      (cond
        ((let ((number (and (eql 0 (search "ruling " entry)) (subseq entry 7))))
           (and number (plusp (length number)) (every #'digit-char-p number)))
         nil)
        ((not (and file (plusp (length file)) line (plusp line)))
         "not \"file:line\", \"execution-plan.md:N\" or \"ruling N\"")
        ;; The private execution plan is not in the repository.
        ((string= file "execution-plan.md") nil)
        ((not (uiop:file-exists-p (%design-file file)))
         (format nil "no file ~a" (%design-file file)))
        ((> line (%file-line-count (%design-file file)))
         (format nil "~a has fewer than ~d lines" file line)))))

  (defun %validate-basis (basis where)
    (unless (and basis (%string-list-p basis))
      (error "~a: :basis must be a non-empty list of strings, got ~s" where basis))
    (dolist (entry basis)
      (let ((reason (%basis-entry-error entry)))
        (when reason
          (error "~a: bad citation ~s: ~a" where entry reason)))))

  (defun %validate-owners (owners allowed where)
    (unless (and (%string-list-p owners)
                 (every (lambda (owner) (member owner allowed :test #'string=))
                        owners)
                 (= (length owners)
                    (length (remove-duplicates owners :test #'string=))))
      (error "~a: owners must be distinct members of ~s, got ~s"
             where allowed owners)))

  (defun %validate-input (entry where &key require-basis)
    (let ((input (getf entry :input)))
      (unless (or (null input) (stringp input))
        (error "~a: :input must be nil or a script string" where))
      (when (or (getf entry :input-basis) (and require-basis (stringp input)))
        (%validate-basis (getf entry :input-basis)
                         (format nil "~a :input-basis" where)))))

  (defun %validate-v08 (v08 row where &key allow-deferred)
    (%plist-keys-within v08 '(:expect :conflict :reason :deferred :warning :owners :basis)
                        where)
    (dolist (key '(:expect :warning :owners :basis))
      (unless (%plist-key-p v08 key)
        (error "~a: :v08 needs ~s" where key)))
    (%validate-warning (getf v08 :warning) where)
    (%validate-owners (getf v08 :owners) *row-owners* where)
    (%validate-basis (getf v08 :basis) where)
    (let ((expect (getf v08 :expect)))
      (case expect
        (:v07
         ;; The run is compared with the JSON record of the fixture source.
         (when (getf row :input)
           (error "~a: :expect :v07 runs the fixture src; :input must be nil" where)))
        (:unsettled
         (let ((conflict (getf v08 :conflict)))
           (unless (and (stringp conflict) (plusp (length conflict)))
             (error "~a: :expect :unsettled needs a non-empty :conflict string" where)))
         (unless (member (getf v08 :reason) *unsettled-reasons*)
           (error "~a: :expect :unsettled needs :reason, one of ~s, got ~s"
                  where *unsettled-reasons* (getf v08 :reason)))
         ;; The owners name the unit that settles the conflict.
         (unless (getf v08 :owners)
           (error "~a: :expect :unsettled needs non-empty :owners" where))
         (cond
           ((%plist-key-p v08 :deferred)
            (unless (eq (getf v08 :deferred) t)
              (error "~a: :deferred must be t" where))
            (unless allow-deferred
              (error "~a: :deferred is allowed only in *probe-changes*" where))
            (when (getf v08 :warning)
              (error "~a: :deferred excludes :warning; a warning is testable" where)))
           ((null (getf v08 :warning))
            (error "~a: :expect :unsettled without :warning must declare :deferred t"
                   where))))
        (t (%validate-expectation expect where)))
      (dolist (key '(:conflict :reason :deferred))
        (when (and (%plist-key-p v08 key) (not (eq expect :unsettled)))
          (error "~a: ~s belongs only to :expect :unsettled" where key)))))

  (defun %validate-v09 (entry where)
    (when (%plist-key-p entry :v09)
      (let ((v09 (getf entry :v09))
            (where (format nil "~a :v09" where)))
        (%plist-keys-within v09 '(:expect :input :input-basis :basis) where)
        (%validate-expectation (getf v09 :expect) where)
        (%validate-input v09 where)
        (%validate-basis (getf v09 :basis) where))))

  (defun %validate-row (row ids)
    (let ((where (format nil "L7.1 row ~s" (getf row :row))))
      (%plist-keys-within row '(:row :probe :input :input-basis :v08 :v09) where)
      (unless (integerp (getf row :row))
        (error "~a: :row must be the line number in L7-diff-and-migration.md" where))
      (unless (member (getf row :probe) ids :test #'equal)
        (error "~a: unknown probe id ~s" where (getf row :probe)))
      (%validate-input row where :require-basis t)
      (%validate-v08 (getf row :v08) row where)
      (%validate-v09 row where)))

  (defun %validate-probe-change (entry ids row-probes)
    (let ((where (format nil "probe change ~s" (getf entry :probe))))
      (%plist-keys-within entry '(:probe :input :input-basis :v08 :v09) where)
      (unless (member (getf entry :probe) ids :test #'equal)
        (error "~a: unknown probe id" where))
      (when (member (getf entry :probe) row-probes :test #'equal)
        (error "~a: the probe of an L7.1 row belongs in *l7-rows*" where))
      (%validate-input entry where :require-basis t)
      (let ((v08 (getf entry :v08)))
        (when (eq (getf v08 :expect) :v07)
          (error "~a: :expect :v07 is only for L7.1 rows" where))
        (%validate-v08 v08 entry where :allow-deferred t))
      (%validate-v09 entry where)))

  (defun %validate-crash-probe (entry ids)
    (let ((where (format nil "crash probe ~s" (getf entry :probe))))
      (%plist-keys-within entry '(:probe :input :input-basis :owners :basis) where)
      (unless (member (getf entry :probe) ids :test #'equal)
        (error "~a: unknown probe id" where))
      (%validate-input entry where :require-basis t)
      (%validate-owners (getf entry :owners) *crash-owners* where)
      (%validate-basis (getf entry :basis) where)))

  (defun %require-unique (values what)
    (let ((duplicates (loop for (value . rest) on values
                            when (member value rest :test #'equal)
                              collect value)))
      (when duplicates
        (error "Duplicate ~a: ~s" what duplicates))))

  (defun %maybe-failing (owners name form)
    (list (if owners 'it-fails 'it)
          (format nil "~a~@[ [~{~a~^/~}]~]" name owners)
          form))

  (defun %v08-test-name (row)
    (let* ((v08 (getf row :v08))
           (expect (getf v08 :expect))
           (code (getf (getf v08 :warning) :code)))
      (format nil "L7.1 row ~d probe ~a v0.8~:[~; keeps v0.7.0~]~@[ warns ~a~]~:[~; (unsettled)~]"
              (getf row :row) (getf row :probe) (eq expect :v07) code
              (eq expect :unsettled))))

  (defmacro register-language-probes ()
    (let ((ids (%probe-ids-at-expansion))
          (rows *l7-rows*)
          (probe-changes *probe-changes*)
          (crash-probes *crash-probes*))
      (%require-unique ids "language-probe fixture ids")
      (unless (= 30 (length rows))
        (error "L7.1 must have 30 rows, found ~d" (length rows)))
      (dolist (row rows) (%validate-row row ids))
      (%require-unique (mapcar (lambda (row) (getf row :row)) rows) "L7.1 row numbers")
      (%require-unique (mapcar (lambda (row) (getf row :probe)) rows) "L7.1 row probes")
      (let ((row-probes (mapcar (lambda (row) (getf row :probe)) rows)))
        (dolist (entry probe-changes) (%validate-probe-change entry ids row-probes)))
      (%require-unique (mapcar (lambda (entry) (getf entry :probe)) probe-changes)
                       "probe change ids")
      (dolist (entry crash-probes) (%validate-crash-probe entry ids))
      (%require-unique (mapcar (lambda (entry) (getf entry :probe)) crash-probes)
                       "crash probe ids")
      (let ((changed (append (loop for row in rows
                                   unless (eq :v07 (getf (getf row :v08) :expect))
                                     collect (getf row :probe))
                             (mapcar (lambda (entry) (getf entry :probe)) probe-changes))))
        `(progn
           (it "the fixed t/spec false executable exits 1"
             (%check-spec-false-exits-nonzero))
           ,@(loop for id in ids
                   unless (member id changed :test #'string=)
                     collect `(it ,(format nil "language-probe ~a v0.7.0 baseline" id)
                                (%check-baseline ,id)))
           ,@(loop for row in rows
                   collect (%maybe-failing (getf (getf row :v08) :owners)
                                           (%v08-test-name row)
                                           `(%check-v08 ,(getf row :row))))
           ,@(loop for row in rows
                   when (getf row :v09)
                     collect `(it-fails ,(format nil "L7.1 row ~d probe ~a v0.9.0"
                                                 (getf row :row) (getf row :probe))
                                (%check-v09 ,(getf row :row))))
           ;; A deferred probe change has nothing to assert; its :conflict,
           ;; :reason and :owners are the record.
           ,@(loop for entry in probe-changes
                   for id = (getf entry :probe)
                   for v08 = (getf entry :v08)
                   unless (getf v08 :deferred)
                     collect (%maybe-failing (getf v08 :owners)
                                             (format nil "language-probe ~a v0.8" id)
                                             `(%check-v08 ,id))
                   when (getf entry :v09)
                     collect `(it-fails ,(format nil "language-probe ~a v0.9.0" id)
                                (%check-v09 ,id)))
           ,@(loop for entry in crash-probes
                   collect (%maybe-failing
                            (getf entry :owners)
                            (format nil "no crash log for ~a" (getf entry :probe))
                            `(%check-no-crash-log ,(getf entry :probe)))))))))

(register-language-probes)
