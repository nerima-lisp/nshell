(in-package #:nshell.feature.assistant)

(defvar *assistant-boundaries* nil)

(defstruct (assistant-model-event
            (:constructor make-assistant-model-event (generation kind payload)))
  generation
  kind
  payload)

(defstruct (assistant-model-boundary
            (:constructor %make-assistant-model-boundary
                (start-fn request-fn poll-fn stop-fn)))
  start-fn
  request-fn
  poll-fn
  stop-fn)

(defun %assistant-object-field (object key)
  (cdr (assoc key object :test #'string=)))

(defun %assistant-object-member (object key)
  (assoc key object :test #'string=))

(defun assistant-system-init-safe-p (payload)
  (and (listp payload)
       (let ((tools (%assistant-object-member payload "tools"))
             (mcp-servers (%assistant-object-member payload "mcp_servers")))
         (and (equal "system" (%assistant-object-field payload "type"))
              (equal "init" (%assistant-object-field payload "subtype"))
              tools
              mcp-servers
              (null (cdr tools))
              (null (cdr mcp-servers))))))

(defun make-assistant-boundary-context (&optional model-boundary)
  (cl-boundary-kit:make-boundary-context :model model-boundary))

(defun make-assistant-model-boundary (&rest options)
  (when (evenp (length options))
    (%make-assistant-model-boundary
     (getf options :start-fn)
     (getf options :request-fn)
     (getf options :poll-fn)
     (getf options :stop-fn))))

(defun assistant-model-boundary ()
  (and *assistant-boundaries*
       (cl-boundary-kit:boundary-context-get *assistant-boundaries*
                                             :model
                                             nil)))

(defun %assistant-boundary-result (status &key value message)
  (list :status status :value value :message message))

(defun assistant-boundary-status (result)
  (getf result :status))

(defun assistant-boundary-value (result)
  (getf result :value))

(defun assistant-boundary-message (result)
  (getf result :message))

(defun %call-assistant-boundary (function arguments)
  (if (functionp function)
      (handler-case
          (%assistant-boundary-result :ok
                                     :value (apply function arguments))
        (error (condition)
          (%assistant-boundary-result :error
                                     :message (princ-to-string condition))))
      (%assistant-boundary-result :unavailable
                                 :message "assistant model boundary is unavailable")))

(defun assistant-boundary-start (boundary &rest arguments)
  (%call-assistant-boundary
   (and (assistant-model-boundary-p boundary)
        (assistant-model-boundary-start-fn boundary))
   arguments))

(defun assistant-boundary-request (boundary &rest arguments)
  (%call-assistant-boundary
   (and (assistant-model-boundary-p boundary)
        (assistant-model-boundary-request-fn boundary))
   arguments))

(defun assistant-boundary-poll (boundary &rest arguments)
  (let ((function (and (assistant-model-boundary-p boundary)
                       (assistant-model-boundary-poll-fn boundary))))
    (if (functionp function)
        (handler-case
            (multiple-value-bind (event present-p)
                (apply function arguments)
              (if present-p
                  (%assistant-boundary-result :event :value event)
                  (%assistant-boundary-result :empty)))
          (error (condition)
            (%assistant-boundary-result :error
                                       :message (princ-to-string condition))))
        (%assistant-boundary-result :unavailable
                                   :message "assistant model boundary is unavailable"))))

(defun assistant-boundary-stop (boundary &rest arguments)
  (%call-assistant-boundary
   (and (assistant-model-boundary-p boundary)
        (assistant-model-boundary-stop-fn boundary))
   arguments))

(defun assistant-model-start (&rest arguments)
  (apply #'assistant-boundary-start
         (assistant-model-boundary)
         arguments))

(defun assistant-model-request (&rest arguments)
  (apply #'assistant-boundary-request
         (assistant-model-boundary)
         arguments))

(defun assistant-model-poll (&rest arguments)
  (apply #'assistant-boundary-poll
         (assistant-model-boundary)
         arguments))

(defun assistant-model-stop (&rest arguments)
  (apply #'assistant-boundary-stop
         (assistant-model-boundary)
         arguments))
