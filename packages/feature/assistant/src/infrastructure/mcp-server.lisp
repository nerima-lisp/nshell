(in-package #:nshell.feature.assistant)

(defun %assistant-mcp-json-alist-p (value)
  (and (listp value)
       (every (lambda (entry)
                (and (consp entry)
                     (stringp (car entry))))
              value)))

(defun %assistant-mcp-json-value (value)
  (cond
    ((eq value json-kit:+json-null+) value)
    ((null value) json-kit:+json-false+)
    ((stringp value) value)
    ((numberp value) value)
    ((eq value t) t)
    ((vectorp value)
     (map 'vector #'%assistant-mcp-json-value value))
    ((%assistant-mcp-json-alist-p value)
     (json-kit:alist->json-object
      (mapcar (lambda (entry)
                (cons (car entry)
                      (%assistant-mcp-json-value (cdr entry))))
              value)))
    ((consp value)
     (map 'vector #'%assistant-mcp-json-value (coerce value 'vector)))
    (t value)))

(defun %assistant-mcp-read-file-string (path)
  (if (probe-file path)
      (handler-case
          (values
           (with-open-file (stream path :direction :input)
             (with-output-to-string (output)
               (loop for line = (read-line stream nil nil)
                     while line
                     do (write-string line output)
                        (terpri output))))
           t)
        (error () (values nil nil)))
      (values nil nil)))

(defun %assistant-mcp-read-transcript-tail (session-id max-lines)
  (let ((path (assistant-transcript-file-path session-id)))
    (if (probe-file path)
        (handler-case
            (with-open-file (stream path :direction :input)
              (let ((tail nil))
                (loop for line = (read-line stream nil nil)
                      while line
                      do (push line tail)
                         (when (> (length tail) max-lines)
                           (setf tail (butlast tail))))
                (values (nreverse tail) t)))
          (error () (values nil nil)))
        (values nil nil))))

(defun %assistant-mcp-session-id-from-path (path)
  (let* ((name (pathname-name path))
         (prefix "transcript-"))
    (when (and (stringp name)
               (>= (length name) (length prefix))
               (string= prefix name :end2 (length prefix))
               (> (length name) (length prefix)))
      (subseq name (length prefix)))))

(defun %assistant-mcp-session-ids ()
  (handler-case
      (sort
       (remove-duplicates
        (remove nil
                (mapcar #'%assistant-mcp-session-id-from-path
                        (directory
                         (merge-pathnames
                          "transcript-*.jsonl"
                          (assistant-state-directory-path)))))
        :test #'string=)
       #'string<)
    (error () nil)))

(defun %assistant-mcp-read-state-request-p (request)
  (and (equal (%assistant-mcp-field request "method") "tools/call")
       (let ((params (%assistant-mcp-field request "params")))
         (equal (%assistant-mcp-field params "name") "read_state"))))

(defun %assistant-mcp-response-line (response)
  (json-kit:stringify (%assistant-mcp-json-value response)))

(defun %assistant-mcp-write-response (response)
  (when response
    (write-line (%assistant-mcp-response-line response) *standard-output*)
    (finish-output *standard-output*)))

(defun %assistant-mcp-parse-error-response (message)
  (list (cons "jsonrpc" "2.0")
        (cons "id" json-kit:+json-null+)
        (cons "error"
              (list (cons "code" -32700)
                    (cons "message" message)))))

(defun %assistant-mcp-response-for-request (request)
  (let* ((session-ids (%assistant-mcp-session-ids))
         (snapshot-path (assistant-snapshot-file-path))
         (snapshot-content nil)
         (snapshot-present-p nil)
         (transcript-session-id nil)
         (transcript-lines nil)
         (transcript-present-p nil))
    (multiple-value-setq (snapshot-content snapshot-present-p)
      (%assistant-mcp-read-file-string snapshot-path))
    (when (%assistant-mcp-read-state-request-p request)
      (multiple-value-bind (session-id tail-lines error-message)
          (assistant-mcp-request-state-options request)
        (declare (ignore tail-lines error-message))
        (when session-id
          (setf transcript-session-id session-id)
          (multiple-value-setq (transcript-lines transcript-present-p)
            (%assistant-mcp-read-transcript-tail
             session-id +assistant-mcp-max-transcript-tail-lines+)))))
    (assistant-mcp-handle-request
     request
     :session-ids session-ids
     :snapshot-present-p snapshot-present-p
     :snapshot-content snapshot-content
     :transcript-session-id transcript-session-id
     :transcript-present-p transcript-present-p
     :transcript-lines transcript-lines)))

(defun run-assistant-mcp-server ()
  (loop for line = (read-line *standard-input* nil nil)
        while line
        do (unless (zerop (length (string-trim '(#\Space #\Tab #\Return) line)))
             (handler-case
                 (%assistant-mcp-write-response
                  (%assistant-mcp-response-for-request
                   (json-kit:parse line
                                   :object-type :alist
                                   :array-type :list)))
               (error (condition)
                 (%assistant-mcp-write-response
                  (%assistant-mcp-parse-error-response
                   (princ-to-string condition)))))))
  0)
