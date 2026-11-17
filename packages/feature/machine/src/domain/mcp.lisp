(in-package #:nshell.feature.machine)

;;; The MCP side of the machine interface (proposal/02 "同じメソッドを MCP
;;; ツールとして公開"): the protocol versions, the tool descriptors, and the
;;; JSON-RPC messages the --mcp server writes.  Requests arrive parsed as
;;; alists (objects) and lists (arrays); every message built here is a
;;; json-kit value ready for JSON-KIT:STRINGIFY.

(defparameter +mcp-protocol-version+ "2025-06-18"
  "The MCP revision the server speaks by default; it has elicitation.")

(defparameter +mcp-supported-protocol-versions+ '("2025-06-18" "2024-11-05")
  "The revisions a client may ask for at initialize.")

(defparameter +mcp-server-name+ "nshell")

(defparameter +mcp-deprecated-tool-names+ '("list_sessions" "read_state")
  "The tools of the earlier --mcp server, kept for one release.")

(defun mcp-field-entry (object name)
  "Return the (NAME . VALUE) member of the parsed JSON OBJECT, or NIL."
  (and (mcp-object-p object)
       (assoc name object :test #'string=)))

(defun mcp-field (object name)
  (cdr (mcp-field-entry object name)))

(defun mcp-object-p (value)
  "True when VALUE is a parsed JSON object; the empty object parses as NIL."
  (and (listp value)
       (every (lambda (entry) (and (consp entry) (stringp (car entry)))) value)))

(defun %mcp-object (&rest pairs)
  "Build an ordered JSON object from alternating keys and values."
  (json-kit:make-json-object
   (loop for (key value) on pairs by #'cddr collect (cons key value))))

(defun mcp-negotiate-protocol-version (requested)
  (if (and (stringp requested)
           (member requested +mcp-supported-protocol-versions+ :test #'string=))
      requested
      +mcp-protocol-version+))

(defun mcp-initialize-result (requested-version server-version)
  (%mcp-object
   "protocolVersion" (mcp-negotiate-protocol-version requested-version)
   "capabilities" (%mcp-object "tools" (%mcp-object "listChanged" json-kit:+json-false+))
   "serverInfo" (%mcp-object "name" +mcp-server-name+ "version" server-version)))

(defun mcp-response (id result)
  (%mcp-object "jsonrpc" "2.0" "id" id "result" result))

(defun mcp-error-response (id code message)
  (%mcp-object "jsonrpc" "2.0" "id" id
               "error" (%mcp-object "code" code "message" message)))

(defun mcp-envelope-tool-result (envelope)
  "Return the tools/call result of ENVELOPE: the envelope as structured
content and as the text of the one content item, an error when it is not ok."
  (%mcp-object "content" (vector (%mcp-object "type" "text"
                                              "text" (envelope-to-json envelope)))
               "structuredContent" (envelope-json-object envelope)
               "isError" (if (envelope-ok-p envelope) json-kit:+json-false+ t)))

(defun mcp-elicitation-request (id message)
  "Return the elicitation/create request asking the client's user to approve
a run, described by MESSAGE, with one boolean field."
  (%mcp-object
   "jsonrpc" "2.0" "id" id "method" "elicitation/create"
   "params" (%mcp-object
             "message" message
             "requestedSchema"
             (%mcp-object "type" "object"
                          "properties" (%mcp-object
                                        "approve" (%mcp-object
                                                   "type" "boolean"
                                                   "description" "Run the input"))
                          "required" (vector "approve")))))

(defun mcp-elicitation-approved-p (response)
  "True only when the parsed elicitation RESPONSE accepted with approve true;
a decline, a cancel, an error response or any other shape is no approval."
  (let ((result (mcp-field response "result")))
    (and (equal (mcp-field result "action") "accept")
         (eq t (mcp-field (mcp-field result "content") "approve")))))

(defun mcp-visible-text (text)
  "Return TEXT with every character a terminal or a bidi-aware display could
act on written as a visible escape: \\n \\r \\t \\e for those controls, and
\\uXXXX (\\u{XXXXX} above U+FFFF) for other C0 and C1 controls, DEL, format
characters (bidi overrides among them), line and paragraph separators, and
private-use and unassigned code points.  The backslash and the quote become
\\\\ and \\\" so every escape reads one way."
  (with-output-to-string (out)
    (loop for char across text
          for code = (char-code char)
          do (case char
               (#\Newline (write-string "\\n" out))
               (#\Return (write-string "\\r" out))
               (#\Tab (write-string "\\t" out))
               (#\\ (write-string "\\\\" out))
               (#\" (write-string "\\\"" out))
               (t (cond ((= code 27) (write-string "\\e" out))
                        ((member (symbol-name (sb-unicode:general-category char))
                                 '("Cc" "Cf" "Zl" "Zp" "Cs" "Co" "Cn")
                                 :test #'string-equal)
                         ;; Braced above U+FFFF, so no digit can be read as part of it.
                         (format out (if (> code #xFFFF) "\\u{~X}" "\\u~4,'0X") code))
                        (t (write-char char out))))))))

(defun mcp-approval-message (input verdict)
  "The text an elicitation shows: INPUT quoted on one line and the reasons of
VERDICT, (LEVEL . REASONS) with REASONS a list of (RULE . TEXT), all through
MCP-VISIBLE-TEXT, so what the user approves is exactly what is shown."
  (format nil "nshell asks to run this ~(~A~) input:~%\"~A\"~%~{~A~%~}"
          (first verdict)
          (mcp-visible-text input)
          (loop for (rule . text) in (rest verdict)
                collect (format nil "- ~A (~A)" (mcp-visible-text text)
                                (mcp-visible-text rule)))))

;;; Tool descriptors

(defun %mcp-schema (&rest properties-and-required)
  "Return an object input schema.  PROPERTIES-AND-REQUIRED is a plist of
property names to (TYPE DESCRIPTION) and :REQUIRED to a list of names."
  (let ((required (getf properties-and-required :required))
        (properties (loop for (name spec) on properties-and-required by #'cddr
                          unless (eq name :required)
                            collect (cons name (%mcp-object "type" (first spec)
                                                            "description" (second spec))))))
    (apply #'%mcp-object
           "type" "object"
           "properties" (json-kit:make-json-object properties)
           (and required (list "required" (coerce required 'vector))))))

(defun %mcp-tool (name description schema)
  (%mcp-object "name" name "description" description "inputSchema" schema))

(defun %mcp-deprecated-tools ()
  "The tools of the earlier --mcp server with their schemas unchanged."
  (list
   (%mcp-tool "list_sessions"
              "Deprecated: list transcript session IDs and whether snapshot.json exists."
              (%mcp-object "type" "object"))
   (%mcp-tool "read_state"
              "Deprecated: read snapshot.json and the bounded tail of one transcript session."
              (%mcp-object
               "type" "object"
               "properties"
               (%mcp-object
                "session_id" (%mcp-object
                              "type" "string"
                              "description" "Transcript session ID returned by list_sessions.")
                "tail_lines" (%mcp-object
                              "type" "integer"
                              "minimum" 1
                              "maximum" nshell.feature.assistant:+assistant-mcp-max-transcript-tail-lines+
                              "default" nshell.feature.assistant:+assistant-mcp-default-transcript-tail-lines+))
               "required" (vector "session_id")))))

(defun mcp-tool-descriptors ()
  "Return the tools tools/list announces: the machine methods in the order of
*MACHINE-METHODS* (ux/U5), then the deprecated tools of the earlier server."
  (coerce
   (append
    (list
     (%mcp-tool "initialize"
                "Return nshell's version, methods, limits, policy summary and session."
                (%mcp-schema))
     (%mcp-tool "run"
                "Run nshell input in this server's session and return the result envelope. Input that needs approval asks the client's user first."
                (%mcp-schema "input" '("string" "The nshell input to run")
                             "timeout" '("number" "Whole-run deadline in seconds")
                             :required '("input")))
     (%mcp-tool "explain"
                "Classify nshell input without running it: forms, effects and safety."
                (%mcp-schema "input" '("string" "The nshell input to explain")
                             :required '("input")))
     (%mcp-tool "complete"
                "Return completion candidates for a command line at a cursor position."
                (%mcp-schema "input" '("string" "The command line")
                             "cursor" '("integer" "Cursor position; defaults to the end")
                             :required '("input")))
     (%mcp-tool "state"
                "Return the session's working directory, session id and last status."
                (%mcp-schema))
     (%mcp-tool "history"
                "Return the inputs run in this session, newest first."
                (%mcp-schema "query" '("string" "Keep entries whose input contains this text")
                             "limit" '("integer" "Return at most this many entries")))
     (%mcp-tool "help"
                "Return the help text of a builtin, or the overview without a topic."
                (%mcp-schema "topic" '("string" "A builtin name")))
     (%mcp-tool "query"
                "Query the knowledge base (not implemented yet)."
                (%mcp-schema "query" '("string" "The question")))
     (%mcp-tool "read_output"
                "Read more of a cut output that a run saved."
                (%mcp-schema "id" '("string" "The session of the envelope")
                             "seq" '("integer" "The run's seq; defaults to 1")
                             "stream" '("string" "stdout or stderr")
                             "offset" '("integer" "Byte offset to read from")
                             "limit" '("integer" "Maximum bytes to read")
                             :required '("id")))
     (%mcp-tool "policy"
                "List the safety rules with their level and description."
                (%mcp-schema)))
    (%mcp-deprecated-tools))
   'vector))
