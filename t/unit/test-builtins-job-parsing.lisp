(in-package #:nshell/test)

(describe "builtin-job-parsing-tests"
  (it "parses integer and named signal designators"
    (expect 15 :to-equal (nshell.application::%parse-signal-designator "15"))
    (expect (nshell.application::%parse-signal-designator "TERM")
            :to-be-truthy)
    (expect (nshell.application::%parse-signal-designator "SIGTERM")
            :to-be-truthy)
    (expect (nshell.application::%parse-signal-designator "not-a-signal")
            :to-be-null)
    (expect (nshell.application::%parse-integer-designator "12")
            :to-equal 12)
    (expect (nshell.application::%parse-integer-designator "12x")
            :to-be-null)
    (expect (nshell.application::%parse-integer-designator nil)
            :to-be-null)
    (expect 12 :to-equal
            (nshell.application::%parse-positive-integer "12"))
    (expect nil :to-equal
            (nshell.application::%parse-positive-integer "0")))

  (it "parses kill options and preserves target order"
    (multiple-value-bind (signal targets list-signals-p error)
        (nshell.application::%parse-kill-arguments
         '("--signal=HUP" "-9" "123" "456"))
      (expect signal :to-be-truthy)
      (expect '("-9" "123" "456") :to-equal targets)
      (expect list-signals-p :to-be-falsy)
      (expect error :to-be-null))
    (multiple-value-bind (signal targets list-signals-p error)
        (nshell.application::%parse-kill-arguments '("-s" "TERM" "--" "-1"))
      (expect signal :to-be-truthy)
      (expect '("-1") :to-equal targets)
      (expect list-signals-p :to-be-falsy)
      (expect error :to-be-null)))

  (it "accepts short signal options and option-like targets"
    (multiple-value-bind (signal targets list-signals-p error)
        (nshell.application::%parse-kill-arguments '("-TERM" "-" "123"))
      (expect :sigterm :to-equal signal)
      (expect '("-" "123") :to-equal targets)
      (expect list-signals-p :to-be-falsy)
      (expect error :to-be-null)))

  (it "reports malformed kill options without partial targets"
    (dolist (args '( ("-s")
                     ("-s" "unknown")
                     ("--signal=unknown")
                     ("--unknown")))
      (multiple-value-bind (signal targets list-signals-p error)
          (nshell.application::%parse-kill-arguments args)
        (expect signal :to-be-null)
        (expect targets :to-be-null)
        (expect list-signals-p :to-be-null)
        (expect error :to-be-truthy))))

  (it "recognizes list-signals and explicit option termination"
    (multiple-value-bind (signal targets list-signals-p error)
        (nshell.application::%parse-kill-arguments '("-l"))
      (expect signal :to-be-truthy)
      (expect targets :to-be-null)
      (expect list-signals-p :to-be-truthy)
      (expect error :to-be-null))
    (multiple-value-bind (signal targets list-signals-p error)
        (nshell.application::%parse-kill-arguments '("--" "-TERM"))
      (expect signal :to-be-truthy)
      (expect '("-TERM") :to-equal targets)
      (expect list-signals-p :to-be-falsy)
      (expect error :to-be-null)))

  (it "formats missing job output and default job labels"
    (expect (format nil "jobs: no such job: current~%")
            :to-equal
            (nshell.application::%missing-job-output
             "jobs" (nshell.application::%job-spec-label nil)))
    (expect (format nil "fg: no such job: %9~%")
            :to-equal
            (nshell.application::%missing-job-output
             "fg" (nshell.application::%job-spec-label '("%9"))))))

  (it "selects requested job listings while preserving missing specs"
    "The listing selector keeps user order and reports unresolved selectors separately."
    (let* ((context (make-test-builtins-context))
           (monitor (nshell.application:shell-context-job-monitor context))
           (first-id (nshell.domain.job-control:monitor-add-job
                      monitor (make-test-job 0 "first")))
           (second-id (nshell.domain.job-control:monitor-add-job
                       monitor (make-test-job 0 "second"))))
      (multiple-value-bind (listings missing)
          (nshell.application::%select-job-listings
           monitor (list (format nil "%~d" second-id) "%99"
                         (format nil "%~d" first-id)))
        (expect (list second-id first-id)
                :to-equal
                (mapcar #'nshell.application:job-listing-id listings))
        (expect '("%99") :to-equal missing))))

  (it "resolves only active jobs when requested"
    "Active-only resolution rejects completed jobs without changing ordinary resolution."
    (let* ((monitor (nshell.domain.job-control:make-job-monitor))
           (job-id (nshell.domain.job-control:monitor-add-job
                    monitor (make-test-job 0 "done"))))
      (expect job-id :to-equal
              (nshell.application::%resolve-job-id
               monitor (list (format nil "%~d" job-id))))
      (nshell.domain.job-control:complete-job monitor job-id)
      (expect nil :to-equal
              (nshell.application::%resolve-job-id
               monitor (list (format nil "%~d" job-id))
               :active-only-p t))))

  (it "waits only for active jobs when no selectors are supplied"
    "Completed jobs are excluded from the implicit wait set."
    (let* ((context (make-test-builtins-context))
           (monitor (nshell.domain.job-control:make-job-monitor))
           (completed-id
             (nshell.domain.job-control:monitor-add-job
              monitor (make-test-job 0 "done"))))
      (setf (nshell.application:shell-context-job-monitor context) monitor)
      (nshell.domain.job-control:complete-job monitor completed-id)
      (expect '(nil 0)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-wait context nil)))))

  (it "resolves wait selectors by process id before job specifications"
    (let* ((context (make-test-builtins-context))
           (monitor (nshell.application:shell-context-job-monitor context))
           (job-id (nshell.domain.job-control:monitor-add-job
                    monitor (make-test-job 0 "sleep" :pids '(4242))))
           (calls nil))
      (with-temporary-function
          ('nshell.application:wait-for-job
           (lambda (selected-id process-registry selected-monitor)
             (declare (ignore process-registry selected-monitor))
             (push selected-id calls)
             (values t 0)))
        (expect '(nil 0)
                :to-equal
                (multiple-value-list
                 (nshell.application::%builtin-wait context '("4242")))))
      (expect (list job-id) :to-equal calls)))

(describe "builtin-job-contract-tests"

  (it "keeps job builtins consistent when the monitor is empty"
    "Empty-monitor behavior is a user-visible contract shared by job builtins."
    (with-builtins-context (context)
      (expect (list (format nil "fg: no such job: current~%") 1)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-fg context nil)))
      (expect (list (format nil "bg: no such job: current~%") 1)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-bg context nil)))
      (expect '("" 0)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-jobs context nil)))
      (expect (list (format nil "disown: no current job~%") 1)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-disown context nil)))
      (expect '(nil 0)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-wait context nil)))))

  (it "formats active job listings"
    "The jobs builtin renders each resolved listing and succeeds when all selectors resolve."
    (with-builtins-context (context)
      (let* ((monitor (nshell.application:shell-context-job-monitor context))
             (job-id (nshell.domain.job-control:monitor-add-job
                      monitor (make-test-job 0 "echo ready"))))
        (multiple-value-bind (output status)
            (nshell.application::%builtin-jobs context
                                                (list (format nil "%~d" job-id)))
          (expect 0 :to-equal status)
          (expect output :to-be-truthy)
          (expect (search "echo ready" output) :to-be-truthy)))))

  (it "reports unresolved job selectors consistently"
    (with-builtins-context (context)
      (expect (list (format nil "jobs: no such job: %99~%") 1)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-jobs context '("%99"))))
      (expect (list (format nil "disown: job [%99] not found~%") 1)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-disown context '("%99"))))
      (expect (list (format nil "wait: no such job: %99~%") 1)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-wait context '("%99")))))

  (it "keeps kill argument errors and usage user-visible"
    (with-builtins-context (context)
      (expect (list (format nil "kill: invalid signal~%") 1)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-kill context '("-s" "unknown"))))
      (expect (list (nshell.application::%kill-list-output) 0)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-kill context '("-l"))))
      (expect (list (format nil "usage: kill [-signal] pid|%job~%") 2)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-kill context nil)))
      (expect (list (format nil "kill: no such process or job: 123~%") 1)
              :to-equal
              (multiple-value-list
               (nshell.application::%builtin-kill context '("123")))))

  (it "covers successful job removal and explicit wait delegation"
    (with-builtins-context (context)
      (let* ((monitor (nshell.application:shell-context-job-monitor context))
             (job-id (nshell.domain.job-control:monitor-add-job
                      monitor (make-test-job 0 "sleep"))))
        (expect '(nil 0)
                :to-equal
                (multiple-value-list
                 (nshell.application::%builtin-disown
                  context (list (format nil "%~d" job-id)))))
        (expect nil :to-be-null
                (nshell.domain.job-control:monitor-find-job monitor job-id)))
      (expect nil :to-be-null
              (nshell.application::%parse-integer-designator 42))))

  (it "covers explicit wait and kill error continuation"
    (with-builtins-context (context)
      (let* ((monitor (nshell.application:shell-context-job-monitor context))
             (job-id (nshell.domain.job-control:monitor-add-job
                      monitor (make-test-job 0 "sleep")))
             (calls nil))
        (with-temporary-function
            ('nshell.application:wait-for-job
             (lambda (selected-id process-registry selected-monitor)
               (declare (ignore process-registry selected-monitor))
               (expect job-id :to-equal selected-id)
               (values (list :job) 7)))
          (expect '(7 7)
                  :to-equal
                  (multiple-value-list
                   (nshell.application::%builtin-wait
                    context (list (format nil "%~d" job-id))))))
        (with-temporary-function
            ('nshell.infrastructure.acl:kill-process
             (lambda (pid signal)
               (push (list pid signal) calls)
               (if (= pid 22) (error "permission denied") 0)))
          (multiple-value-bind (output status)
              (nshell.application::%builtin-kill context '("21" "22"))
            (expect 1 :to-equal status)
            (expect (format nil "kill: 22: permission denied~%")
                    :to-equal output)))
        (expect '((22 :sigterm) (21 :sigterm)) :to-equal calls))))

  (it "signals a resolved job and reports non-numeric targets"
    (with-builtins-context (context)
      (let* ((monitor (nshell.application:shell-context-job-monitor context))
             (job-id (nshell.domain.job-control:monitor-add-job
                      monitor (make-test-job 0 "sleep")))
             (signals nil))
        (with-temporary-function
            ('nshell.application::signal-job
             (lambda (selected-id signal selected-monitor)
               (declare (ignore selected-monitor))
               (push (list selected-id signal) signals)
               t))
          (multiple-value-bind (output status)
              (nshell.application::%builtin-kill
               context (list (format nil "%~d" job-id)))
            (expect nil :to-be-null output)
            (expect 0 :to-equal status)))
        (expect (list (list job-id :sigterm)) :to-equal signals)
        (expect (list (format nil "kill: no such process or job: nope~%") 1)
                :to-equal
                (multiple-value-list
                 (nshell.application::%builtin-kill context '("nope")))))))
  )))
