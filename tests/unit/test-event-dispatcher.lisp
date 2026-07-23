(in-package #:nshell/test)

(defun test-event (type)
  (nshell.domain.events:make-generic-domain-event type))

(describe "event-dispatcher-tests"
  (it "dispatcher-raw-constructor-is-internal-boundary"
    "The dispatcher struct constructor is internal; callers use the application factory."
    (expect (fboundp 'nshell.application:make-event-dispatcher) :to-be-truthy)
    (expect (fboundp 'nshell.application::%make-event-dispatcher) :to-be-truthy))

  (it "dispatcher-drains-events-in-fifo-order-per-type"
    "Events published for a type are delivered in FIFO order."
    (let ((dispatcher (nshell.application:make-event-dispatcher)))
      (with-event-capture (seen dispatcher :type-a) (nshell.domain.events:domain-event-timestamp event)
        (nshell.application:publish-event dispatcher (nshell.domain.events:make-generic-domain-event :type-a :timestamp 1))
        (nshell.application:publish-event dispatcher (nshell.domain.events:make-generic-domain-event :type-a :timestamp 2))
        (nshell.application:publish-event dispatcher (nshell.domain.events:make-generic-domain-event :type-a :timestamp 3))
        (expect (nshell.application:drain-events dispatcher) :to-be-null)
        (expect '(1 2 3) :to-equal (nreverse seen)))))

  (it "dispatcher-filters-events-by-type"
    "Handlers only receive events for their subscribed type."
    (let ((dispatcher (nshell.application:make-event-dispatcher)))
      (with-event-capture (seen dispatcher :type-x) (nshell.domain.events:domain-event-type event)
        (nshell.application:publish-event dispatcher (test-event :type-x))
        (nshell.application:publish-event dispatcher (test-event :type-y))
        (nshell.application:publish-event dispatcher (test-event :type-x))
        (expect (nshell.application:drain-events dispatcher) :to-be-null)
        (expect '(:type-x :type-x) :to-equal (nreverse seen)))))

  (it "dispatcher-delivers-to-multiple-handlers"
    "Multiple handlers subscribed to the same type see all matching events."
    (let ((dispatcher (nshell.application:make-event-dispatcher)))
      (with-event-capture (first-handler dispatcher :type-a) (nshell.domain.events:domain-event-type event)
        (with-event-capture (second-handler dispatcher :type-a) (nshell.domain.events:domain-event-type event)
          (nshell.application:publish-event dispatcher (test-event :type-a))
          (nshell.application:publish-event dispatcher (test-event :type-a))
          (expect (nshell.application:drain-events dispatcher) :to-be-null)
          (expect '(:type-a :type-a) :to-equal (nreverse first-handler))
          (expect '(:type-a :type-a) :to-equal (nreverse second-handler))))))

  (it "dispatcher-empty-drain-is-no-op"
    "Draining an empty dispatcher returns no errors and invokes no handlers."
    (let ((dispatcher (nshell.application:make-event-dispatcher))
          (calls 0))
      (nshell.application:subscribe dispatcher :type-a
                                    (lambda (event)
                                      (declare (ignore event))
                                      (incf calls)))
      (expect (nshell.application:drain-events dispatcher) :to-be-null)
      (expect 0 :to-equal calls)))

  (it "dispatcher-isolates-handler-errors"
    "A failing handler is collected as an error and does not block siblings."
    (let ((dispatcher (nshell.application:make-event-dispatcher)))
      (nshell.application:subscribe dispatcher :type-a
                                    (lambda (event)
                                      (declare (ignore event))
                                      (error "boom")))
      (with-event-capture (seen dispatcher :type-a) (nshell.domain.events:domain-event-type event)
        (nshell.application:publish-event dispatcher (test-event :type-a))
        (let ((errors (nshell.application:drain-events dispatcher)))
          (expect 1 :to-equal (length errors))
          (expect (getf (first errors) :condition) :to-be-type-of 'error)
          (expect '(:type-a) :to-equal (nreverse seen))))))

  (it "dispatcher-unsubscribe-removes-handler"
    "After unsubscribe, the handler no longer receives matching events."
    (let* ((dispatcher (nshell.application:make-event-dispatcher))
           (seen nil)
           (handler (lambda (event)
                      (push (nshell.domain.events:domain-event-type event) seen))))
      (nshell.application:subscribe dispatcher :type-a handler)
      (nshell.application:publish-event dispatcher (test-event :type-a))
      (expect (nshell.application:drain-events dispatcher) :to-be-null)
      (nshell.application:unsubscribe dispatcher :type-a handler)
      (nshell.application:publish-event dispatcher (test-event :type-a))
      (expect (nshell.application:drain-events dispatcher) :to-be-null)
      (expect '(:type-a) :to-equal (nreverse seen)))))
