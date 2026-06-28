(in-package #:nshell/test)

(def-suite event-dispatcher-tests
  :description "Application event dispatcher unit tests"
  :in nshell-tests)

(in-suite event-dispatcher-tests)

(defun test-event (type)
  (nshell.domain.events:make-domain-event type))

(test dispatcher-drains-events-in-fifo-order-per-type
  "Events published for a type are delivered in FIFO order."
  (let ((dispatcher (nshell.application:make-event-dispatcher)))
    (with-event-capture (seen dispatcher :type-a) (nshell.domain.events:domain-event-timestamp event)
      (nshell.application:publish-event dispatcher (nshell.domain.events:make-domain-event :type-a 1))
      (nshell.application:publish-event dispatcher (nshell.domain.events:make-domain-event :type-a 2))
      (nshell.application:publish-event dispatcher (nshell.domain.events:make-domain-event :type-a 3))
      (is (null (nshell.application:drain-events dispatcher)))
      (is (equal '(1 2 3) (nreverse seen))))))

(test dispatcher-filters-events-by-type
  "Handlers only receive events for their subscribed type."
  (let ((dispatcher (nshell.application:make-event-dispatcher)))
    (with-event-capture (seen dispatcher :type-x) (nshell.domain.events:domain-event-type event)
      (nshell.application:publish-event dispatcher (test-event :type-x))
      (nshell.application:publish-event dispatcher (test-event :type-y))
      (nshell.application:publish-event dispatcher (test-event :type-x))
      (is (null (nshell.application:drain-events dispatcher)))
      (is (equal '(:type-x :type-x) (nreverse seen))))))

(test dispatcher-delivers-to-multiple-handlers
  "Multiple handlers subscribed to the same type see all matching events."
  (let ((dispatcher (nshell.application:make-event-dispatcher)))
    (with-event-capture (first-handler dispatcher :type-a) (nshell.domain.events:domain-event-type event)
      (with-event-capture (second-handler dispatcher :type-a) (nshell.domain.events:domain-event-type event)
        (nshell.application:publish-event dispatcher (test-event :type-a))
        (nshell.application:publish-event dispatcher (test-event :type-a))
        (is (null (nshell.application:drain-events dispatcher)))
        (is (equal '(:type-a :type-a) (nreverse first-handler)))
        (is (equal '(:type-a :type-a) (nreverse second-handler)))))))

(test dispatcher-empty-drain-is-no-op
  "Draining an empty dispatcher returns no errors and invokes no handlers."
  (let ((dispatcher (nshell.application:make-event-dispatcher))
        (calls 0))
    (nshell.application:subscribe dispatcher :type-a
                                  (lambda (event)
                                    (declare (ignore event))
                                    (incf calls)))
    (is (null (nshell.application:drain-events dispatcher)))
    (is (= 0 calls))))

(test dispatcher-isolates-handler-errors
  "A failing handler is collected as an error and does not block siblings."
  (let ((dispatcher (nshell.application:make-event-dispatcher)))
    (nshell.application:subscribe dispatcher :type-a
                                  (lambda (event)
                                    (declare (ignore event))
                                    (error "boom")))
    (with-event-capture (seen dispatcher :type-a) (nshell.domain.events:domain-event-type event)
      (nshell.application:publish-event dispatcher (test-event :type-a))
      (let ((errors (nshell.application:drain-events dispatcher)))
        (is (= 1 (length errors)))
        (is (typep (getf (first errors) :condition) 'error))
        (is (equal '(:type-a) (nreverse seen)))))))

(test dispatcher-unsubscribe-removes-handler
  "After unsubscribe, the handler no longer receives matching events."
  (let* ((dispatcher (nshell.application:make-event-dispatcher))
         (seen nil)
         (handler (lambda (event)
                    (push (nshell.domain.events:domain-event-type event) seen))))
    (nshell.application:subscribe dispatcher :type-a handler)
    (nshell.application:publish-event dispatcher (test-event :type-a))
    (is (null (nshell.application:drain-events dispatcher)))
    (nshell.application:unsubscribe dispatcher :type-a handler)
    (nshell.application:publish-event dispatcher (test-event :type-a))
    (is (null (nshell.application:drain-events dispatcher)))
    (is (equal '(:type-a) (nreverse seen)))))
