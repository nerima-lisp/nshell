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
