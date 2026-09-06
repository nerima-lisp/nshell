(in-package #:nshell.feature.assistant)

(defstruct (assistant-fixture-state
            (:constructor %make-assistant-fixture-state (events)))
  events
  (index 0)
  pending
  started-p
  stopped-p)

(defun %assistant-event-kind (object)
  (let ((type (%assistant-object-field object "type"))
        (subtype (%assistant-object-field object "subtype")))
    (cond
      ((and (equal type "system") (equal subtype "init")) :system-init)
      ((equal type "assistant") :assistant)
      ((equal type "rate_limit_event") :rate-limit-event)
      ((equal type "result") :result)
      (t :unknown))))

(defun %assistant-read-json-value (stream)
  (let ((first-char
          (loop for char = (read-char stream nil :eof)
                do (cond
                     ((eq char :eof) (return :eof))
                     ((find char '(#\Space #\Tab #\Newline #\Return)
                            :test #'char=))
                     (t (unread-char char stream)
                        (return char))))))
    (if (eq first-char :eof)
        (values nil :eof nil)
        (handler-case
            (values (json-kit:read-json stream
                                        :object-type :alist
                                        :array-type :list)
                    :value
                    nil)
          (error (condition)
            (values nil :error (princ-to-string condition)))))))

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
  (make-assistant-model-event generation
                               (%assistant-event-kind object)
                               object))

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
