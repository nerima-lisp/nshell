(in-package #:nshell.feature.assistant)

(defparameter +assistant-mcp-protocol-version+ "2024-11-05")
(defparameter +assistant-mcp-default-transcript-tail-lines+ 50)
(defparameter +assistant-mcp-max-transcript-tail-lines+ 200)

(defun %assistant-mcp-field-entry (object name)
  (and (listp object)
       (assoc name object :test #'string=)))

(defun %assistant-mcp-field (object name)
  (cdr (%assistant-mcp-field-entry object name)))

(defun %assistant-mcp-object (&rest entries)
  entries)

(defun %assistant-mcp-response (id result)
  (%assistant-mcp-object
   (cons "jsonrpc" "2.0")
   (cons "id" id)
   (cons "result" result)))

(defun %assistant-mcp-error-response (id code message)
  (%assistant-mcp-object
   (cons "jsonrpc" "2.0")
   (cons "id" id)
   (cons "error"
         (%assistant-mcp-object
          (cons "code" code)
          (cons "message" message)))))

(defun %assistant-mcp-text-content (text)
  (vector (%assistant-mcp-object
           (cons "type" "text")
           (cons "text" text))))

(defun %assistant-mcp-tail-lines (lines count)
  (let ((tail (last lines count)))
    (coerce tail 'vector)))

(defun %assistant-mcp-state-content (snapshot-present-p snapshot-content
                                     transcript-session-id transcript-present-p
                                     transcript-lines tail-lines)
  (let ((snapshot
          (if snapshot-present-p
              (%assistant-mcp-object
               (cons "available" t)
               (cons "content" snapshot-content))
              (%assistant-mcp-object
               (cons "available" nil))))
        (lines (%assistant-mcp-tail-lines transcript-lines tail-lines)))
    (%assistant-mcp-object
     (cons "snapshot" snapshot)
     (cons "transcript"
           (%assistant-mcp-object
            (cons "session_id" transcript-session-id)
            (cons "available" transcript-present-p)
            (cons "tail_lines" (length lines))
            (cons "lines" lines))))))

(defun %assistant-mcp-state-text (snapshot-present-p snapshot-content
                                  transcript-session-id transcript-present-p
                                  transcript-lines tail-lines)
  (with-output-to-string (stream)
    (format stream "snapshot.json:~%")
    (if snapshot-present-p
        (format stream "~a~%" snapshot-content)
        (format stream "[not available]~%"))
    (format stream "transcript-~a.jsonl (last ~d lines):~%"
            (or transcript-session-id "<none>")
            tail-lines)
    (if transcript-present-p
        (loop for line across (%assistant-mcp-tail-lines transcript-lines tail-lines)
              do (format stream "~a~%" line))
        (format stream "[not available]~%"))))

(defun %assistant-mcp-list-sessions-content (session-ids snapshot-present-p)
  (%assistant-mcp-object
   (cons "sessions" (coerce session-ids 'vector))
   (cons "snapshot" (%assistant-mcp-object
                      (cons "available" snapshot-present-p)))))

(defun %assistant-mcp-tool-result (payload text &optional error-p)
  (%assistant-mcp-object
   (cons "content" (%assistant-mcp-text-content text))
   (cons "structuredContent" payload)
   (cons "isError" (not (null error-p)))))

(defun %assistant-mcp-tool-list ()
  (vector
   (%assistant-mcp-object
    (cons "name" "list_sessions")
    (cons "description"
          "List transcript session IDs and whether snapshot.json exists.")
    (cons "inputSchema"
          (%assistant-mcp-object
           (cons "type" "object"))))
   (%assistant-mcp-object
    (cons "name" "read_state")
    (cons "description"
          "Read snapshot.json and the bounded tail of one transcript session.")
    (cons "inputSchema"
          (%assistant-mcp-object
           (cons "type" "object")
           (cons "properties"
                 (%assistant-mcp-object
                  (cons "session_id"
                        (%assistant-mcp-object
                         (cons "type" "string")
                         (cons "description"
                               "Transcript session ID returned by list_sessions.")))
                  (cons "tail_lines"
                        (%assistant-mcp-object
                         (cons "type" "integer")
                         (cons "minimum" 1)
                         (cons "maximum"
                               +assistant-mcp-max-transcript-tail-lines+)
                         (cons "default"
                               +assistant-mcp-default-transcript-tail-lines+)))))
           (cons "required" (vector "session_id")))))))

(defun assistant-mcp-request-state-options (request)
  (let* ((params (%assistant-mcp-field request "params"))
         (arguments (%assistant-mcp-field params "arguments"))
         (session-entry (%assistant-mcp-field-entry arguments "session_id"))
         (tail-entry (%assistant-mcp-field-entry arguments "tail_lines"))
         (session-id (cdr session-entry))
         (tail-lines (if tail-entry
                         (cdr tail-entry)
                         +assistant-mcp-default-transcript-tail-lines+)))
    (cond
      ((not session-entry)
       (values nil nil "session_id is required"))
      ((not (and (stringp session-id) (plusp (length session-id))))
       (values nil nil "session_id must be a non-empty string"))
      ((not (integerp tail-lines))
       (values nil nil "tail_lines must be an integer"))
      ((not (plusp tail-lines))
       (values nil nil "tail_lines must be greater than zero"))
      (t
       (values session-id
               (min tail-lines +assistant-mcp-max-transcript-tail-lines+)
               nil)))))

(defun %assistant-mcp-initialize-result ()
   (%assistant-mcp-object
   (cons "protocolVersion" +assistant-mcp-protocol-version+)
   (cons "capabilities" (%assistant-mcp-object
                          (cons "tools" (%assistant-mcp-object
                                         (cons "listChanged" nil)))))
   (cons "serverInfo"
         (%assistant-mcp-object
          (cons "name" "nshell-state")
          (cons "version" "0.4.0")))))

(defun %assistant-mcp-tool-call
    (request session-ids snapshot-present-p snapshot-content
             transcript-session-id transcript-present-p transcript-lines)
  (let* ((params (%assistant-mcp-field request "params"))
         (name (%assistant-mcp-field params "name")))
    (cond
      ((and (stringp name) (string= name "list_sessions"))
       (let ((payload (%assistant-mcp-list-sessions-content
                       session-ids snapshot-present-p)))
         (%assistant-mcp-tool-result
          payload
          (format nil "Available transcript sessions: ~{~a~^, ~}~%snapshot.json: ~:[not available~;available~]"
                  session-ids snapshot-present-p))))
      ((and (stringp name) (string= name "read_state"))
       (multiple-value-bind (session-id tail-lines error-message)
           (assistant-mcp-request-state-options request)
         (if error-message
             (let ((payload (%assistant-mcp-object
                             (cons "error" error-message))))
               (%assistant-mcp-tool-result payload error-message t))
             (let ((payload
                     (%assistant-mcp-state-content
                      snapshot-present-p snapshot-content session-id
                      (and transcript-present-p
                           (string= session-id transcript-session-id))
                      (if (and transcript-present-p
                               (string= session-id transcript-session-id))
                          transcript-lines
                          nil)
                      tail-lines)))
               (%assistant-mcp-tool-result
                payload
                (%assistant-mcp-state-text
                 snapshot-present-p snapshot-content session-id
                 (and transcript-present-p
                      (string= session-id transcript-session-id))
                 (if (and transcript-present-p
                          (string= session-id transcript-session-id))
                     transcript-lines
                     nil)
                 tail-lines))))))
      (t
       (%assistant-mcp-error-response
        (%assistant-mcp-field request "id")
        -32602
        "Unknown tool")))))

(defun assistant-mcp-handle-request
    (request &key session-ids snapshot-present-p snapshot-content
                    transcript-session-id transcript-present-p transcript-lines)
  (let* ((id-entry (%assistant-mcp-field-entry request "id"))
         (id (cdr id-entry))
         (method (%assistant-mcp-field request "method")))
    (cond
      ((not (and (listp request)
                 (equal (%assistant-mcp-field request "jsonrpc") "2.0")
                 (stringp method)))
       (if id-entry
           (%assistant-mcp-error-response id -32600 "Invalid Request")
           nil))
      ((string= method "notifications/initialized") nil)
      ((not id-entry) nil)
      ((string= method "initialize")
       (%assistant-mcp-response id (%assistant-mcp-initialize-result)))
      ((string= method "ping")
       (%assistant-mcp-response id (%assistant-mcp-object (cons "ok" t))))
      ((string= method "tools/list")
       (%assistant-mcp-response id
                               (%assistant-mcp-object
                                (cons "tools" (%assistant-mcp-tool-list)))))
      ((string= method "tools/call")
       (let ((tool-response
               (%assistant-mcp-tool-call
                request session-ids snapshot-present-p snapshot-content
                transcript-session-id transcript-present-p transcript-lines)))
         (if (%assistant-mcp-field-entry tool-response "error")
             tool-response
             (%assistant-mcp-response id tool-response))))
      (t
       (%assistant-mcp-error-response id -32601 "Method not found")))))
