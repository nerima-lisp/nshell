;;;; Run one pinned dependency suite per fresh SBCL process.

(require :asdf)
(load (merge-pathnames "asdf-runtime.lisp" *load-truename*))
(load (merge-pathnames "dependency-registry.lisp" *load-truename*))

(defparameter *dependency-test-systems*
  '(("cl-prolog-kit/test" nil)
    ("cl-parser-kit/test" nil)
    ("cl-dataflow-kit/test" nil)
    ("cl-boundary-kit/test" nil)
    ("cl-cli/test" nil)
    ("cl-cli/test/shell-verification" nil)
    ("cl-tty-kit/test" nil)
    ("cl-log-kit/test" nil)
    ("cl-process-kit/test" nil)
    ("cl-process-kit/pty-test" nil)
    ("cl-regex-kit/test" 30000)
    ("cl-vcs-kit/test" nil)
    ("cl-tui-kit/test" nil)
    ("cl-history-kit/test" 10000)
    ("cl-host-kit/test" 10000)
    ("cl-codec-kit/test" 20000)
    ("cl-concurrent-kit/test" 20000)
    ("cl-date-kit/test" 20000)
    ("cl-json-kit/test" 10000)))

(defun dependency-weave (name &rest arguments)
  ;; Event accessors and registry nodes are internal in pinned cl-weave 1.3.0.
  ;; A changed API must fail, not fall back to run-all's permissive boolean.
  (let ((symbol (find-symbol name "CL-WEAVE")))
    (unless (and symbol (fboundp symbol))
      (error "Required cl-weave API is unavailable: ~A" name))
    (apply (symbol-function symbol) arguments)))

(defun dependency-check-source (system)
  (let ((source (asdf:system-source-file (asdf:find-system system))))
    (unless (dependency-store-path-p source)
      (error "System ~A is not from a Nix store source" system))
    (format t "~&dependency-source system=~S source=~S~%" system (namestring source))))

(defun dependency-registered-count (node)
  (cond ((dependency-weave "TEST-CASE-P" node) 1)
        ((dependency-weave "SUITE-P" node)
         (reduce #'+ (dependency-weave "SUITE-CHILDREN" node)
                 :key #'dependency-registered-count :initial-value 0))
        (t (error "Unknown cl-weave registry node: ~S" node))))

(defun dependency-paths (items accessor)
  (sort (mapcar (lambda (item)
                 (with-standard-io-syntax
                   (prin1-to-string (dependency-weave accessor item))))
               items)
        #'string<))

(defparameter *dependency-history-assertion-paths*
  '(("navigation invariants" "one step back then one step forward restores the typed input")
    ("navigation invariants" "with WRAP true, walking backward past the oldest match keeps cycling instead of ever returning NIL")
    ("navigation invariants" "with WRAP true, alternating HISTORY-PREVIOUS and HISTORY-NEXT keeps cycling in both directions instead of ever returning NIL")))

(defun dependency-call-with-history-assertions (system root run)
  (unless (string= system "cl-history-kit/test")
    (return-from dependency-call-with-history-assertions (funcall run)))
  (let ((matches (make-hash-table :test #'equal))
        (counter (find-symbol "*ASSERTION-COUNT*" "CL-WEAVE"))
        (setter (find-symbol "TEST-CASE-FUNCTION" "CL-WEAVE"))
        (records nil))
    (unless (and counter setter (fboundp (list 'setf setter)))
      (error "Required cl-weave assertion instrumentation is unavailable"))
    (labels ((visit (node path)
               (cond ((dependency-weave "SUITE-P" node)
                      (dolist (child (dependency-weave "SUITE-CHILDREN" node))
                        (visit child (if (eq node root) path
                                         (append path (list (dependency-weave "SUITE-NAME" node)))))))
                     ((dependency-weave "TEST-CASE-P" node)
                      (let ((full-path (append path (list (dependency-weave "TEST-CASE-NAME" node)))))
                        (when (member full-path *dependency-history-assertion-paths* :test #'equal)
                          (push node (gethash full-path matches)))))
                     (t (error "Unknown cl-weave registry node: ~S" node)))))
      (visit root nil))
    (dolist (path *dependency-history-assertion-paths*)
      (let ((tests (gethash path matches)))
        (unless (= 1 (length tests))
          (error "Expected exactly one history property at ~S; found ~D" path (length tests)))
        (push (list path (first tests)
                    (dependency-weave "TEST-CASE-FUNCTION" (first tests)) 0 0)
              records)))
    (setf records (nreverse records))
    (unwind-protect
         (progn
           (dolist (record records)
             (let ((original (third record)))
               (funcall (fdefinition (list 'setf setter))
                        (lambda ()
                          ;; Count only the property body, not before/after hooks.
                          ;; A nonmatching trial is valid; the whole property must assert.
                          (let ((before (symbol-value counter)))
                            (unless (integerp before)
                              (error "cl-weave did not bind its assertion counter"))
                            (incf (fourth record))
                            (unwind-protect (funcall original)
                              (incf (fifth record) (- (symbol-value counter) before)))))
                        (second record))))
           (multiple-value-prog1 (funcall run)
             (dolist (record records)
               (format t "~&dependency-assertions system=~S path=~{~S~^ > ~} executed=~D assertions=~D~%"
                       system (first record) (fourth record) (fifth record)))
             (unless (every (lambda (record)
                              (and (= 1 (fourth record)) (plusp (fifth record))))
                            records)
               (error "History property body was unexecuted, repeated, or assertion-free"))))
      (dolist (record records)
        (funcall (fdefinition (list 'setf setter)) (third record) (second record))))))

(defun dependency-native-spawn-source ()
  (dependency-configure-registry)
  (let* ((system (asdf:find-system "cl-process-kit"))
         (source (asdf:system-source-file system))
         (script (merge-pathnames "t/native-spawn-test.sh" source)))
    (unless (and (dependency-store-path-p source)
                 (string= "3.4.4" (asdf:component-version system))
                 (probe-file script)
                 (dependency-store-path-p (truename script)))
      (error "Pinned cl-process-kit 3.4.4 native test source is unavailable"))
    (write-line (namestring (truename script)))))

(defun dependency-test-main (system)
  (let ((entry (assoc system *dependency-test-systems* :test #'string=))
        (discovered :unknown) (selected :unknown) (executed 0) (passed 0)
        (nonpass 0) (success nil))
    (unwind-protect
         (handler-case
             (progn
               (unless entry (error "Unknown dependency test system: ~A" system))
               (nshell-configure-writable-asdf-output)
               (dependency-configure-registry)
               (dependency-check-source system)
               (dependency-check-source "cl-weave")
               (unless (string= "1.3.0" (asdf:component-version (asdf:find-system "cl-weave")))
                 (error "This runner requires pinned cl-weave 1.3.0"))
               (asdf:load-system system)
               (let* ((root (dependency-weave "ROOT-SUITE"))
                      (plan (dependency-weave "COLLECT-TEST-PLAN" root
                                              :name-filter nil :retry 0
                                              :timeout-ms (second entry))))
                 (setf discovered (dependency-registered-count root)
                       selected (length plan))
                 (format t "~&dependency-discovery system=~S discovered=~D selected=~D~%"
                         system discovered selected)
                 (unless (and (plusp discovered) (= discovered selected)
                              (notany (lambda (test)
                                        (dependency-weave "TEST-PLAN-ENTRY-FOCUSED" test))
                                      plan))
                   (error "Empty or incomplete/focused dependency test selection"))
                 ;; Unlike ASDF test-op and run-all, RUN returns actual events.
                 (dependency-call-with-history-assertions
                  system root
                  (lambda ()
                    (let ((events (dependency-weave
                                   "NORMALIZE-RUN-RESULTS"
                                   (dependency-weave "RUN" root :reporter :spec
                                                     :name-filter nil :bail nil :retry 0
                                                     :timeout-ms (second entry)
                                                     :max-workers 1))))
                      (setf executed (length events)
                            passed (count :pass events
                                          :key (lambda (event)
                                                 (dependency-weave "TEST-EVENT-STATUS" event)))
                            nonpass (- executed passed))
                      (unless (and (= discovered selected executed passed)
                                   (equal (dependency-paths plan "TEST-PLAN-ENTRY-PATH")
                                          (dependency-paths events "TEST-EVENT-PATH")))
                        (error "Incomplete execution or non-pass events (skip/todo also fail)"))
                      events)))
                 (setf success t)))
           (error (condition)
             (format *error-output* "~&dependency-error system=~S: ~A~%" system condition)))
      (format t "~&dependency-result system=~S discovered=~A selected=~A executed=~D pass=~D nonpass=~D status=~A~%"
              system discovered selected executed passed nonpass (if success "PASS" "FAIL"))
      (finish-output))
    (if success 0 1)))

(let ((arguments (uiop:command-line-arguments)))
  (cond ((equal arguments '("--list"))
         (dolist (entry *dependency-test-systems*) (write-line (first entry))))
        ((equal arguments '("--native-spawn-source"))
         (handler-case (dependency-native-spawn-source)
           (error (condition)
             (format *error-output* "Native test source error: ~A~%" condition)
             (uiop:quit 1))))
        ((= (length arguments) 1)
         (uiop:quit (dependency-test-main (first arguments))))
        (t
         (format *error-output* "Usage: sbcl --script scripts/test-dependencies.lisp SYSTEM | --list | --native-spawn-source~%")
         (uiop:quit 2))))
