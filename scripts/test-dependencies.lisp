;;;; Run one pinned dependency suite per fresh SBCL process.

(require :asdf)
(load (merge-pathnames "asdf-runtime.lisp" *load-truename*))

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

(defun dependency-store-path-p (path)
  (and path (uiop:string-prefix-p "/nix/store/" (namestring (truename path)))))

(defun dependency-configure-registry ()
  (let* ((value (uiop:getenv "CL_SOURCE_REGISTRY"))
         (registry (and value (asdf/source-registry:parse-source-registry-string value)))
         (entries (and registry (rest registry))))
    (unless (and value (plusp (length value)) (eq (first registry) :source-registry))
      (error "CL_SOURCE_REGISTRY must explicitly name pinned Nix store sources"))
    (setf entries (remove-if (lambda (entry)
                              (member entry '(:inherit-configuration
                                              :ignore-inherited-configuration
                                              (:inherit-configuration)
                                              (:ignore-inherited-configuration))
                                      :test #'equal))
                            entries))
    (unless (and entries
                 (every (lambda (entry)
                          (and (consp entry)
                               (member (first entry) '(:directory :tree))
                               (= (length entry) 2)
                               (dependency-store-path-p (second entry))))
                        entries))
      (error "Only explicit Nix store :directory/:tree registry entries are allowed"))
    (let ((configuration `(:source-registry ,@entries :ignore-inherited-configuration)))
      (setf asdf:*central-registry* nil)
      (asdf:clear-source-registry)
      (asdf:initialize-source-registry configuration)
      ;; Dependency tests that launch child Lisp images inherit the same pins.
      (sb-posix:setenv "CL_SOURCE_REGISTRY" (prin1-to-string configuration) 1))))

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
                   (setf success t))))
           (error (condition)
             (format *error-output* "~&dependency-error system=~S: ~A~%" system condition)))
      (format t "~&dependency-result system=~S discovered=~A selected=~A executed=~D pass=~D nonpass=~D status=~A~%"
              system discovered selected executed passed nonpass (if success "PASS" "FAIL"))
      (finish-output))
    (if success 0 1)))

(let ((arguments (uiop:command-line-arguments)))
  (cond ((equal arguments '("--list"))
         (dolist (entry *dependency-test-systems*) (write-line (first entry))))
        ((= (length arguments) 1)
         (uiop:quit (dependency-test-main (first arguments))))
        (t
         (format *error-output* "Usage: sbcl --script scripts/test-dependencies.lisp SYSTEM | --list~%")
         (uiop:quit 2))))
