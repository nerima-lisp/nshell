(require :asdf)
(let ((sb-ext:*posix-argv* '("sbcl" "--list"))
      (*standard-output* (make-broadcast-stream)))
  (load (merge-pathnames "../../scripts/test-dependencies.lisp" *load-truename*)))
(nshell-configure-writable-asdf-output)
(dependency-configure-registry)
(asdf:load-system "cl-weave")

(defvar *checks* 0)
(defun check (value description)
  (incf *checks*)
  (unless value (error "Check failed: ~A" description)))

(defparameter *paths*
  '(("navigation invariants" "one step back then one step forward restores the typed input")
    ("navigation invariants" "with WRAP true, walking backward past the oldest match keeps cycling instead of ever returning NIL")
    ("navigation invariants" "with WRAP true, alternating HISTORY-PREVIOUS and HISTORY-NEXT keeps cycling in both directions instead of ever returning NIL")))

(defun fixture (body)
  (let* ((tests (mapcar (lambda (path)
                        (dependency-weave "MAKE-TEST-CASE" :name (second path) :function body))
                      *paths*))
         (suite (dependency-weave "MAKE-SUITE" :name "navigation invariants" :children tests))
         (root (dependency-weave "MAKE-SUITE" :name "root" :children (list suite))))
    (funcall (fdefinition (list 'setf (find-symbol "SUITE-PARENT" "CL-WEAVE"))) root suite)
    (values root tests)))

(defun run-fixture (root)
  (dependency-weave "NORMALIZE-RUN-RESULTS"
                    (dependency-weave "RUN" root :reporter :spec :retry 0 :max-workers 1)))

(defun rejects (thunk message)
  (handler-case (progn (funcall thunk) nil)
    (error (condition) (not (null (search message (princ-to-string condition)))))))

(multiple-value-bind (root tests) (fixture (lambda () nil))
  (let ((originals (mapcar (lambda (test) (dependency-weave "TEST-CASE-FUNCTION" test)) tests)))
    (check (= 3 (count :pass (run-fixture root)
                       :key (lambda (event) (dependency-weave "TEST-EVENT-STATUS" event))))
           "baseline accepts three assertion-free cases")
    (check (rejects (lambda ()
                      (dependency-call-with-history-assertions
                       "cl-history-kit/test" root (lambda () (run-fixture root))))
                    "History property body")
           "limited gate rejects assertion-free properties")
    (check (every #'eq originals
                  (mapcar (lambda (test) (dependency-weave "TEST-CASE-FUNCTION" test)) tests))
           "body functions are restored after rejection")))

(multiple-value-bind (root tests)
    (fixture (lambda ()
               ;; Nonmatching trials may legitimately do nothing; aggregate counts must be positive.
               (dotimes (trial 100)
                 (when (zerop trial) (eval '(cl-weave:expect t :to-be-truthy))))))
  (declare (ignore tests))
  (check (= 3 (length (dependency-call-with-history-assertions
                      "cl-history-kit/test" root (lambda () (run-fixture root)))))
         "one assertion and 99 empty trials per property are accepted"))

(multiple-value-bind (root tests) (fixture (lambda () nil))
  (declare (ignore tests))
  (check (= 3 (length (dependency-call-with-history-assertions
                      "cl-process-kit/test" root (lambda () (run-fixture root)))))
         "other systems remain outside the limited gate")
  (check (rejects (lambda ()
                    (dependency-call-with-history-assertions
                     "cl-history-kit/test" (dependency-weave "MAKE-SUITE" :name "root")
                     (lambda () nil)))
                  "Expected exactly one history property")
         "missing intended property paths are rejected"))

(multiple-value-bind (root tests) (fixture (lambda () nil))
  (declare (ignore tests))
  (let ((suite (first (dependency-weave "SUITE-CHILDREN" root))))
    (dolist (accessor '("SUITE-BEFORE-EACH" "SUITE-AFTER-EACH"))
      (funcall (fdefinition (list 'setf (find-symbol accessor "CL-WEAVE")))
               (list (lambda () (eval '(cl-weave:expect t :to-be-truthy)))) suite)))
  (check (= 3 (count :pass (run-fixture root)
                     :key (lambda (event) (dependency-weave "TEST-EVENT-STATUS" event))))
         "hooks execute assertions successfully in the baseline")
  (check (rejects (lambda ()
                    (dependency-call-with-history-assertions
                     "cl-history-kit/test" root (lambda () (run-fixture root))))
                  "History property body")
         "hook assertions cannot conceal an assertion-free property body"))

(multiple-value-bind (root tests)
    (fixture (lambda () (eval '(cl-weave:expect t :to-be-truthy))))
  (declare (ignore tests))
  (check (rejects (lambda ()
                    (dependency-call-with-history-assertions
                     "cl-history-kit/test" root (lambda () nil)))
                  "History property body")
         "selected but unexecuted properties are rejected")
  (check (rejects (lambda ()
                    (dependency-call-with-history-assertions
                     "cl-history-kit/test" root
                     (lambda () (run-fixture root) (run-fixture root))))
                  "History property body")
         "repeated execution does not satisfy the exactly-once gate"))

(multiple-value-bind (root tests)
    (fixture (lambda () (eval '(cl-weave:expect nil :to-be-truthy))))
  (declare (ignore tests))
  (check (= 3 (count :fail (dependency-call-with-history-assertions
                          "cl-history-kit/test" root (lambda () (run-fixture root)))
                     :key (lambda (event) (dependency-weave "TEST-EVENT-STATUS" event))))
         "counting failing assertions preserves their failed events"))
(format t "~&dependency-assertion-checks=~D status=PASS~%" *checks*)
