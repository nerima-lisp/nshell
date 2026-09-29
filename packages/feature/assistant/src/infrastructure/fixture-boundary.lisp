(in-package #:nshell.feature.assistant)

(defstruct (assistant-fixture-state
            (:constructor %make-assistant-fixture-state (events)))
  events
  (index 0)
  pending
  started-p
  stopped-p)

(defun %assistant-load-fixture (path)
  (handler-case
      (with-open-file (stream path :direction :input)
        (loop with events = nil
              do (multiple-value-bind (object status message)
                     (%assistant-read-json-value stream)
                   (case status
                     (:value
                      (push object events))
                     (:eof
                      (return (values (nreverse events) nil)))
                     (otherwise
                      (return (values nil message)))))))
    (error (condition)
      (values nil (princ-to-string condition)))))

(defun %assistant-fixture-pending-event (state generation object)
  (declare (ignore state))
  (let ((kind (%assistant-event-kind object)))
    (if (eq kind :unknown)
        (make-assistant-model-event
         generation
         :stream-error
         (list (cons "message" "assistant fixture returned an unknown event")))
        (make-assistant-model-event generation kind object))))

(defun %assistant-fixture-start (state)
  (setf (assistant-fixture-state-index state) 1
        (assistant-fixture-state-started-p state) t
        (assistant-fixture-state-stopped-p state) nil
        (assistant-fixture-state-pending state)
          (when (first (assistant-fixture-state-events state))
            (list (%assistant-fixture-pending-event
                   state 0 (first (assistant-fixture-state-events state))))))
  t)

(defun %assistant-fixture-request (state generation payload)
  (declare (ignore payload))
  (if (or (not (assistant-fixture-state-started-p state))
          (assistant-fixture-state-stopped-p state))
      nil
      (let ((events nil)
            (result-seen-p nil)
            (events-list (assistant-fixture-state-events state))
            (index (assistant-fixture-state-index state)))
        (loop while (< index (length events-list))
              for object = (nth index events-list)
              do (incf index)
                 (push (%assistant-fixture-pending-event state generation object)
                       events)
                 (when (eq :result (%assistant-event-kind object))
                   (setf result-seen-p t)
                   (return)))
        (setf (assistant-fixture-state-index state) index)
        (unless result-seen-p
          (push (make-assistant-model-event generation :stream-ended nil)
                events))
        (setf (assistant-fixture-state-pending state)
              (nconc (assistant-fixture-state-pending state)
                     (nreverse events)))
        t)))

(defun %assistant-fixture-poll (state generation)
  (declare (ignore generation))
  (if (assistant-fixture-state-pending state)
      (values (pop (assistant-fixture-state-pending state)) t)
      (values nil nil)))

(defun %assistant-fixture-stop (state)
  (setf (assistant-fixture-state-stopped-p state) t
        (assistant-fixture-state-pending state) nil)
  t)

(defun make-assistant-fixture-boundary (path)
  (multiple-value-bind (events error-message)
      (%assistant-load-fixture path)
    (if error-message
        (values nil error-message)
        (let ((state (%make-assistant-fixture-state
                      (mapcar (lambda (object)
                                object)
                              events))))
          (values
           (make-assistant-model-boundary
            :start-fn (lambda () (%assistant-fixture-start state))
            :request-fn (lambda (generation payload)
                          (%assistant-fixture-request state generation payload))
            :poll-fn (lambda (generation)
                       (%assistant-fixture-poll state generation))
            :stop-fn (lambda () (%assistant-fixture-stop state)))
           nil)))))
