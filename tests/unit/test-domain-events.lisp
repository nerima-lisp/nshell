(in-package #:nshell/test)

(def-suite domain-events-tests
  :description "Domain event unit tests"
  :in nshell-tests)

(in-suite domain-events-tests)

(defmacro assert-event-types (&rest cases)
  `(progn
     ,@(loop for (event-form expected-type) in cases
             collect `(is (eq (nshell.domain.events:domain-event-type ,event-form)
                              ,expected-type)))))

(test generic-event-factory
  "Generic domain events can be created through an explicit factory."
  (let ((event (nshell.domain.events:make-generic-domain-event :test-event :timestamp 0)))
    (is (eq (nshell.domain.events:domain-event-type event) :test-event))
    (is (= 0 (nshell.domain.events:domain-event-timestamp event)))))

(test domain-event-factory-enforces-event-invariants
  "Domain events are created through invariant-checking factories."
  (signals type-error
    (nshell.domain.events:make-generic-domain-event "not-a-keyword"))
  (signals type-error
    (nshell.domain.events:make-generic-domain-event :test :timestamp nil))
  (let ((event (nshell.domain.events:make-command-entered-event "ls")))
    (is (eq (nshell.domain.events:domain-event-type event) :command-entered))
    (is (integerp (nshell.domain.events:domain-event-timestamp event)))))

(test domain-event-values-do-not-export-raw-struct-api
  "Domain events expose factories and projections, not raw struct helpers."
  (is (not (nth-value 1 (find-symbol "DOMAIN-EVENT" :nshell.domain.events))))
  (is (not (fboundp 'nshell.domain.events::domain-event-p)))
  (is (not (fboundp 'nshell.domain.events::copy-domain-event)))
  (is (fboundp 'nshell.domain.events::%domain-event-p))
  (is (fboundp 'nshell.domain.events:domain-event-type))
  (is (fboundp 'nshell.domain.events:domain-event-timestamp)))

(test command-events-have-correct-types
  "All command event constructors produce correct types"
  (assert-event-types
   ((nshell.domain.events:make-command-entered-event "ls") :command-entered)
   ((nshell.domain.events:make-command-parsed-event '()) :command-parsed)
   ((nshell.domain.events:make-parse-failed-event "bad" "error") :parse-failed)))

(test job-events-have-correct-types
  "All job event constructors produce correct types"
  (assert-event-types
   ((nshell.domain.events:make-job-created-event 1 "ls" 100) :job-created)
   ((nshell.domain.events:make-job-stopped-event 1 :sigterm) :job-stopped)
   ((nshell.domain.events:make-job-completed-event 1 0) :job-completed)))

(test history-events-have-correct-types
  "History event constructors produce correct types"
  (assert-event-types
   ((nshell.domain.events:make-history-searched-event) :history-searched)))

(test event-timestamp-is-monotonic
  "Event timestamps are set at creation time"
  (let* ((t1 (get-universal-time))
         (event (nshell.domain.events:make-generic-domain-event :test)))
    (is (<= t1 (nshell.domain.events:domain-event-timestamp event)))))
