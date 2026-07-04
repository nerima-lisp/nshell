(in-package #:nshell.application)
(defstruct (event-dispatcher (:constructor %make-event-dispatcher ()))
  (subscribers (make-hash-table :test #'eq) :type hash-table)
  (queue nil :type list))

(defun make-event-dispatcher ()
  (%make-event-dispatcher))

(defun publish-event (dispatcher event)
  (push event (event-dispatcher-queue dispatcher))
  event)

(defun subscribe (dispatcher event-type handler)
  (setf (gethash event-type (event-dispatcher-subscribers dispatcher))
        (append (gethash event-type (event-dispatcher-subscribers dispatcher))
                (list handler)))
  handler)

(defun unsubscribe (dispatcher event-type handler)
  (setf (gethash event-type (event-dispatcher-subscribers dispatcher))
        (remove handler
                (gethash event-type (event-dispatcher-subscribers dispatcher))
                :test #'eq))
  handler)

(defun drain-events (dispatcher)
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
