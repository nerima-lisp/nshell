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
            :to-be-null))

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
  ))
