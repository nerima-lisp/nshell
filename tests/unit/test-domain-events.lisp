(in-package #:nshell/test)

(defun domain-events-external-symbol-p (name)
  (eq (nth-value 1 (find-symbol name :nshell.domain.events)) :external))

(defmacro assert-event-types (&rest cases)
  `(progn
     ,@(loop for (event-form expected-type) in cases
             collect `(expect (nshell.domain.events:domain-event-type ,event-form) :to-be ,expected-type))))

(describe "domain-events-tests"
  (it "generic-event-factory"
    "Generic domain events can be created through an explicit factory."
    (let ((event (nshell.domain.events:make-generic-domain-event :test-event :timestamp 0)))
      (expect (nshell.domain.events:domain-event-type event) :to-be :test-event)
      (expect 0 :to-equal (nshell.domain.events:domain-event-timestamp event))))

  (it "domain-event-factory-enforces-event-invariants"
    "Domain events are created through invariant-checking factories."
    (expect (lambda () (nshell.domain.events:make-generic-domain-event "not-a-keyword")) :to-throw 'type-error)
    (expect (lambda () (nshell.domain.events:make-generic-domain-event :test :timestamp nil)) :to-throw 'type-error)
    (let ((event (nshell.domain.events:make-command-entered-event "ls")))
      (expect (nshell.domain.events:domain-event-type event) :to-be :command-entered)
      (expect (integerp (nshell.domain.events:domain-event-timestamp event)) :to-be-truthy)))

  (it "domain-event-values-expose-public-contract"
    "Domain events expose factories and projections, not raw struct details."
    (expect (domain-events-external-symbol-p "MAKE-GENERIC-DOMAIN-EVENT") :to-be-truthy)
    (expect (domain-events-external-symbol-p "DOMAIN-EVENT-TYPE") :to-be-truthy)
    (expect (domain-events-external-symbol-p "DOMAIN-EVENT-TIMESTAMP") :to-be-truthy)
    (expect (domain-events-external-symbol-p "DOMAIN-EVENT") :to-be-falsy)
    (expect (domain-events-external-symbol-p "%DOMAIN-EVENT") :to-be-falsy)
    (expect (domain-events-external-symbol-p "%MAKE-DOMAIN-EVENT") :to-be-falsy))

  (it "command-events-have-correct-types"
    "All command event constructors produce correct types"
    (assert-event-types
     ((nshell.domain.events:make-command-entered-event "ls") :command-entered)
     ((nshell.domain.events:make-command-parsed-event '()) :command-parsed)
     ((nshell.domain.events:make-parse-failed-event "bad" "error") :parse-failed)))

  (it "job-events-have-correct-types"
    "All job event constructors produce correct types"
    (assert-event-types
     ((nshell.domain.events:make-job-created-event 1 "ls" 100) :job-created)
     ((nshell.domain.events:make-job-stopped-event 1 :sigterm) :job-stopped)
     ((nshell.domain.events:make-job-completed-event 1 0) :job-completed)))

  (it "history-events-have-correct-types"
    "History event constructors produce correct types"
    (assert-event-types
     ((nshell.domain.events:make-history-searched-event) :history-searched)))

  (it "event-timestamp-is-monotonic"
    "Event timestamps are set at creation time"
    (let* ((t1 (get-universal-time))
           (event (nshell.domain.events:make-generic-domain-event :test)))
      (expect t1 :to-be-less-than-or-equal (nshell.domain.events:domain-event-timestamp event)))))
