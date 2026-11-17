(in-package #:nshell.feature.machine)

;;; `nshell --mcp` (proposal/02, D-83): the machine methods as MCP tools over
;;; newline-delimited JSON-RPC on standard input and output.
;;;
;;; One server process is one session: the shell state (cwd, variables,
;;; functions, aliases) is set up once and every run call continues it, every
;;; run envelope carries the same session id, and seq counts the run calls.
;;; Messages are handled one at a time in arrival order.  A run whose input
;;; classifies :confirm asks the client's user through elicitation/create when
;;; the client declared the elicitation capability on a protocol revision that
;;; has it; requests that arrive while the server waits for that answer are
;;; kept and handled after the run, and a notifications/cancelled for the run
;;; or for a kept request drops it without a reply (MCP cancellation).  A run
;;; whose worker could not be stopped at its deadline may still change the
;;; shell state, so the session refuses every later call that uses that state.

(defstruct (mcp-server (:constructor %make-mcp-server (input output)))
  input
  output
  ;; Messages read while waiting for an elicitation answer, oldest first, as
  ;; (PARSED . PARSE-ERROR-MESSAGE).
  (pending '())
  (elicitation-p nil)
  (protocol-version nil)
  (elicitation-count 0)
  ;; The id of the tools/call being handled.
  (request-id nil)
  ;; True once a run's worker outlived its deadline.
  (poisoned-p nil)
  (session-id nil)
  ;; The output store session cut output is saved in, or NIL when the store
  ;; could not be created safely.
  (output-session nil)
  (seq 0)
  ;; (SEQ INPUT STATUS) of every run call, newest first.
  (history '())
  (last-status nil))

(define-condition %mcp-invalid-arguments (error)
  ((message :initarg :message :reader %mcp-invalid-arguments-message))
  (:report (lambda (condition stream)
             (write-string (%mcp-invalid-arguments-message condition) stream))))

;;; Messages

(defun %mcp-read-message (server)
  "Read the next non-blank line of the protocol stream.  Return the parsed
message and NIL, NIL and the parse error's text, or, at end of input, three
NILs; the third value is true when a line was read."
  (loop for line = (read-line (mcp-server-input server) nil nil)
        while line
        unless (zerop (length (string-trim '(#\Space #\Tab #\Return) line)))
          do (return
               (handler-case
                   (values (json-kit:parse line :object-type :alist :array-type :vector)
                           nil t)
                 (error (condition)
                   (values nil (princ-to-string condition) t))))
        finally (return (values nil nil nil))))

(defun %mcp-next-message (server)
  "Return the next message to handle as %MCP-READ-MESSAGE does, the kept ones
first."
  (let ((kept (pop (mcp-server-pending server))))
    (if kept
        (values (car kept) (cdr kept) t)
        (%mcp-read-message server))))

(defun %mcp-write (server message)
  "Write MESSAGE, a json-kit value or a JSON line, as one protocol line."
  (when message
    (let ((output (mcp-server-output server)))
      (write-line (if (stringp message) message (json-kit:stringify message)) output)
      (finish-output output))))

(defun %mcp-parse-error-response (message)
  (mcp-error-response json-kit:+json-null+ -32700 message))

;;; Approval

(defun %mcp-answer-to-p (message id)
  "True when MESSAGE is the client's response to the server's request ID."
  (and (mcp-object-p message)
       (equal (mcp-field message "id") id)
       (not (mcp-field-entry message "method"))
       (or (mcp-field-entry message "result") (mcp-field-entry message "error"))))

(defun %mcp-cancelled-id (message)
  "Return the requestId MESSAGE cancels when it is notifications/cancelled."
  (and (mcp-object-p message)
       (equal (mcp-field message "method") "notifications/cancelled")
       (mcp-field-entry (mcp-field message "params") "requestId")
       (mcp-field (mcp-field message "params") "requestId")))

(defun %mcp-request-id-p (message id)
  (and (mcp-object-p message)
       (mcp-field-entry message "method")
       (equal (mcp-field message "id") id)))

(defun %mcp-elicitation-available-p (server)
  (and (mcp-server-elicitation-p server)
       (equal (mcp-server-protocol-version server) "2025-06-18")))

(defun %mcp-request-approval (server input verdict)
  "Ask the client's user whether INPUT, which classified as VERDICT, may run.
Return :APPROVED only when they accepted with approve true, :CANCELLED when
the client cancelled the tools/call being handled, and NIL otherwise.  Without
elicitation nobody can be asked.  Other messages read meanwhile are kept for
later, except a request the client cancels meanwhile; end of input is no
approval."
  (when (%mcp-elicitation-available-p server)
    (let ((id (format nil "nshell-elicitation-~D"
                      (incf (mcp-server-elicitation-count server)))))
      (%mcp-write server (mcp-elicitation-request id (mcp-approval-message input verdict)))
      (loop
        (multiple-value-bind (message error present-p) (%mcp-read-message server)
          (let ((cancelled (and (not error) (%mcp-cancelled-id message))))
            (cond ((not present-p) (return nil))
                  ((and (not error) (%mcp-answer-to-p message id))
                   (return (and (mcp-elicitation-approved-p message) :approved)))
                  ((and cancelled (equal cancelled (mcp-server-request-id server)))
                   (return :cancelled))
                  (cancelled
                   (setf (mcp-server-pending server)
                         (remove-if (lambda (kept)
                                      (and (null (cdr kept))
                                           (%mcp-request-id-p (car kept) cancelled)))
                                    (mcp-server-pending server))))
                  (t (setf (mcp-server-pending server)
                           (append (mcp-server-pending server)
                                   (list (cons message error))))))))))))

;;; Tools

(defun %mcp-argument (arguments name type &optional required-p)
  "Return argument NAME of ARGUMENTS, checked to be of TYPE (:string,
:integer or :number), or NIL when it is absent and not REQUIRED-P."
  (let ((entry (mcp-field-entry arguments name)))
    (cond ((null entry)
           (when required-p
             (error '%mcp-invalid-arguments
                    :message (format nil "~A is required" name)))
           nil)
          ((ecase type
             (:string (stringp (cdr entry)))
             (:integer (integerp (cdr entry)))
             (:number (realp (cdr entry))))
           (cdr entry))
          (t (error '%mcp-invalid-arguments
                    :message (format nil "~A must be ~A" name
                                     (ecase type
                                       (:string "a string")
                                       (:integer "an integer")
                                       (:number "a number"))))))))

(define-condition %mcp-request-cancelled (error) ())

(defun %mcp-report-unsaved-output (seq envelope)
  "Say on stderr when run SEQ cut an output the session could not save, which
the envelope shows only by the missing path."
  (dolist (output (list (envelope-stdout envelope) (envelope-stderr envelope)))
    (when (and (envelope-output-truncated output) (null (envelope-output-path output)))
      (format *error-output* "nshell --mcp: the full output of run ~D could not be saved~%"
              seq)
      (finish-output *error-output*)
      (return))))

(defun %mcp-run (server arguments)
  (let ((input (%mcp-argument arguments "input" :string t))
        (timeout (or (%mcp-argument arguments "timeout" :number)
                     +json-default-timeout-seconds+)))
    (unless (%valid-json-timeout-p timeout)
      (error '%mcp-invalid-arguments :message "timeout must be a positive number of seconds"))
    ;; exit in an earlier run ends that run only.
    (setf nshell.presentation::*running* t)
    (multiple-value-bind (verdict readable-p) (%classify-input input)
      (let ((answer (and readable-p
                         (eq (first verdict) :confirm)
                         (%mcp-request-approval server input verdict))))
        (when (eq answer :cancelled)
          (error '%mcp-request-cancelled))
        (let ((seq (incf (mcp-server-seq server))))
          (multiple-value-bind (json status envelope worker-alive-p)
              (run-json-command input :timeout timeout
                                      :environment-agent-p t
                                      ;; run-json-command classifies again and
                                      ;; refuses a verdict other than this one.
                                      :approved-verdict (and (eq answer :approved) verdict)
                                      :reset-state-p nil
                                      :session (mcp-server-session-id server)
                                      :output-session (mcp-server-output-session server)
                                      :seq seq)
            (declare (ignore json))
            (when worker-alive-p
              (setf (mcp-server-poisoned-p server) t))
            (when (mcp-server-output-session server)
              (%mcp-report-unsaved-output seq envelope))
            (push (list seq input status) (mcp-server-history server))
            (setf (mcp-server-last-status server) status)
            envelope))))))

(defun %mcp-tool-envelope (server name arguments)
  "Return the envelope tool NAME answers with for ARGUMENTS, a parsed object."
  (let ((cwd (%current-directory)))
    (handler-case
        (progn
          (unless (mcp-object-p arguments)
            (error '%mcp-invalid-arguments :message "arguments must be an object"))
          (when (and (mcp-server-poisoned-p server)
                     (member name '("run" "explain" "complete" "state") :test #'string=))
            (return-from %mcp-tool-envelope
              (method-error-envelope
               "E_INTERNAL"
               "a previous run could not be stopped at its deadline and may still change the shell state; start a new server"
               cwd)))
          (cond
            ((string= name "initialize")
             (initialize-envelope :cwd cwd :session-id (mcp-server-session-id server)))
            ((string= name "run") (%mcp-run server arguments))
            ((string= name "explain")
             (explain-input (nshell.presentation::%make-repl-shell-context)
                            (%mcp-argument arguments "input" :string t)
                            :cwd cwd))
            ((string= name "complete")
             (complete-envelope (nshell.presentation::%make-repl-shell-context)
                                (%mcp-argument arguments "input" :string t)
                                :cursor (%mcp-argument arguments "cursor" :integer)
                                :cwd cwd))
            ((string= name "state")
             (state-envelope :cwd cwd
                             :session-id (mcp-server-session-id server)
                             :seq (mcp-server-seq server)
                             :last-status (mcp-server-last-status server)))
            ((string= name "history")
             (history-envelope (mcp-server-history server)
                               :query (%mcp-argument arguments "query" :string)
                               :limit (%mcp-argument arguments "limit" :integer)
                               :cwd cwd))
            ((string= name "help")
             (help-envelope :topic (%mcp-argument arguments "topic" :string) :cwd cwd))
            ((string= name "query") (query-envelope :cwd cwd))
            ((string= name "read_output")
             (read-output-envelope
              :id (%mcp-argument arguments "id" :string t)
              :seq (or (%mcp-argument arguments "seq" :integer) 1)
              :stream (or (%mcp-argument arguments "stream" :string) "stdout")
              :offset (or (%mcp-argument arguments "offset" :integer) 0)
              :limit (or (%mcp-argument arguments "limit" :integer)
                         +default-max-output-bytes+)
              :cwd cwd))
            ((string= name "policy") (policy-envelope :cwd cwd))))
      (%mcp-invalid-arguments (condition)
        (method-error-envelope "E_PROTOCOL" (%mcp-invalid-arguments-message condition)
                               cwd)))))

(defun %mcp-tool-call (server request id)
  (let* ((params (mcp-field request "params"))
         (name (mcp-field params "name")))
    (cond
      ((and (stringp name) (member name +mcp-deprecated-tool-names+ :test #'string=))
       (nshell.feature.assistant:assistant-mcp-state-response-line request))
      ((and (stringp name) (member name *machine-methods* :test #'string=))
       (setf (mcp-server-request-id server) id)
       (handler-case
           (mcp-response id (mcp-envelope-tool-result
                             (%mcp-tool-envelope server name (mcp-field params "arguments"))))
         ;; MCP cancellation: a cancelled request gets no response.
         (%mcp-request-cancelled () nil)))
      (t (mcp-error-response id -32602 "Unknown tool")))))

(defun %mcp-handle (server request)
  "Return the response to REQUEST, or NIL when it needs none."
  (let* ((id-entry (mcp-field-entry request "id"))
         (id (cdr id-entry))
         (method (mcp-field request "method")))
    (cond
      ((not (mcp-object-p request))
       (mcp-error-response json-kit:+json-null+ -32600 "Invalid Request"))
      ((not (equal (mcp-field request "jsonrpc") "2.0"))
       (and id-entry (mcp-error-response id -32600 "Invalid Request")))
      ;; A response to no request the server is waiting for.
      ((and (null method)
            (or (mcp-field-entry request "result") (mcp-field-entry request "error")))
       nil)
      ((not (stringp method))
       (and id-entry (mcp-error-response id -32600 "Invalid Request")))
      ;; Notifications, notifications/initialized among them.
      ((not id-entry) nil)
      ((string= method "initialize")
       (let ((params (mcp-field request "params")))
         (setf (mcp-server-elicitation-p server)
               (not (null (mcp-field-entry (mcp-field params "capabilities")
                                           "elicitation")))
               (mcp-server-protocol-version server)
               (mcp-negotiate-protocol-version (mcp-field params "protocolVersion")))
         (mcp-response id (mcp-initialize-result
                           (mcp-field params "protocolVersion")
                           (asdf:component-version (asdf:find-system "nshell"))))))
      ((string= method "ping") (mcp-response id (json-kit:make-json-object '())))
      ((string= method "tools/list")
       (mcp-response id (%mcp-object "tools" (mcp-tool-descriptors))))
      ((string= method "tools/call") (%mcp-tool-call server request id))
      (t (mcp-error-response id -32601 "Method not found")))))

;;; Session

(defun %fallback-session-id ()
  "A session id for a server whose output store could not be created: cut
output is then not saved, and read_output finds nothing under it."
  (let ((state (make-random-state t))
        (alphabet "abcdefghijklmnopqrstuvwxyz0123456789"))
    (format nil "s_~{~C~}"
            (loop repeat 6 collect (char alphabet (random (length alphabet) state))))))

(defun run-mcp-server (&key (input *standard-input*) (output *standard-output*))
  "Serve the MCP tools on INPUT and OUTPUT until INPUT ends; return 0."
  (let ((server (%make-mcp-server input output))
        ;; Bound, not assigned, as run-json-command binds them: a caller in the
        ;; same image keeps its own.
        (nshell.presentation:*noninteractive-batch-p* t)
        (nshell.infrastructure.acl:*detach-child-standard-input* nil)
        (nshell.infrastructure.terminal:*terminal-color-depth* nil)
        ;; Neither a run nor anything else reads or writes the protocol
        ;; streams: input reads end at once and output goes to stderr, through
        ;; *terminal-io* (and so *query-io* and *debug-io*) as well.
        (*standard-input* (make-string-input-stream ""))
        (*standard-output* *error-output*)
        (*terminal-io* (make-two-way-stream (make-string-input-stream "") *error-output*)))
    (nshell.presentation::%initialize-batch-state)
    (let ((session (ignore-errors (open-output-session))))
      (setf (mcp-server-output-session server) session
            (mcp-server-session-id server) (if session
                                               (output-session-id session)
                                               (%fallback-session-id)))
      (unwind-protect
           (loop
             (multiple-value-bind (message error present-p) (%mcp-next-message server)
               (unless present-p (return))
               (%mcp-write server
                           (if error
                               (%mcp-parse-error-response error)
                               (handler-case (%mcp-handle server message)
                                 (error (condition)
                                   (let ((id-entry (mcp-field-entry message "id")))
                                     (and id-entry
                                          (mcp-error-response (cdr id-entry) -32603
                                                              (princ-to-string condition))))))))))
        ;; A session that saved nothing leaves no directory behind.
        (when session
          (ignore-errors
           (sb-posix:rmdir (string-right-trim "/" (output-session-directory session)))))))
    0))
