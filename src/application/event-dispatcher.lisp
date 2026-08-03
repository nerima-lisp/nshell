(in-package #:nshell.application)
(defstruct (event-dispatcher (:constructor %make-event-dispatcher ()))
  (subscribers (make-hash-table :test #'eq) :type hash-table)
  (queue nil :type list))

(defun make-event-dispatcher ()
  "Return a fresh EVENT-DISPATCHER with no subscribers and an empty queue."
  (%make-event-dispatcher))

(defun publish-event (dispatcher event)
  "Queue EVENT on DISPATCHER and return it. Does not call any handler --
handlers only run when DRAIN-EVENTS is later called; publishing is
deferred, not synchronous dispatch."
  (push event (event-dispatcher-queue dispatcher))
  event)

(defun subscribe (dispatcher event-type handler)
  "Register HANDLER to be called with each future EVENT-TYPE event that
DRAIN-EVENTS processes. Appends, so handlers for the same EVENT-TYPE run
in subscription order. Returns HANDLER, so it can be captured for a later
UNSUBSCRIBE call."
  (setf (gethash event-type (event-dispatcher-subscribers dispatcher))
        (append (gethash event-type (event-dispatcher-subscribers dispatcher))
                (list handler)))
  handler)

(defun unsubscribe (dispatcher event-type handler)
  "Remove HANDLER from EVENT-TYPE's subscriber list. Compares with EQ, so
this must be the identical function object SUBSCRIBE was given -- an
equivalent but freshly-allocated closure will not match."
  (setf (gethash event-type (event-dispatcher-subscribers dispatcher))
        (remove handler
                (gethash event-type (event-dispatcher-subscribers dispatcher))
                :test #'eq))
  handler)

(defun drain-events (dispatcher)
  "Dispatch every event DISPATCHER has queued since the last DRAIN-EVENTS,
oldest first, to each of that event type's subscribed handlers in
subscription order, then empty the queue. A handler signalling any
CONDITION does not stop the drain -- the remaining handlers and events
still run -- and every such condition is collected and returned instead,
oldest first, as a list of (:EVENT event :HANDLER handler :CONDITION
condition) plists."
  (let ((events (nreverse (event-dispatcher-queue dispatcher)))
        (errors nil))
    (setf (event-dispatcher-queue dispatcher) nil)
    (dolist (event events)
      (let ((handlers (gethash (nshell.domain.events:domain-event-type event)
                               (event-dispatcher-subscribers dispatcher))))
        (dolist (handler handlers)
          (handler-case
              (funcall handler event)
            (condition (condition)
              (push (list :event event
                          :handler handler
                          :condition condition)
                    errors))))))
    (nreverse errors)))
