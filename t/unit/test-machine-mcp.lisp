(in-package #:nshell/test)

;;; `nshell --mcp` (task P1-6): RUN-MCP-SERVER in process on string streams.
;;; Every envelope a tool returns is checked against
;;; docs/design/conformance/envelope.schema.json with the helpers of
;;; test-machine-envelope.lisp; the cache home helper comes from
;;; test-machine-json-command.lisp.

(defparameter +mcp-test-tool-names+
  '("initialize" "run" "explain" "complete" "state" "history" "help" "query"
    "read_output" "policy" "list_sessions" "read_state"))

(defun %mcp-json (value)
  (json-kit:stringify value))

(defun %mcp-request (id method &optional params)
  (format nil "{\"jsonrpc\":\"2.0\",\"id\":~A,\"method\":~A~@[,\"params\":~A~]}"
          (%mcp-json id) (%mcp-json method) params))

(defun %mcp-initialize (&key elicitation (version "2025-06-18"))
  (%mcp-request 1 "initialize"
                (format nil "{\"protocolVersion\":~A,\"capabilities\":{~:[~;\"elicitation\":{}~]},\"clientInfo\":{\"name\":\"test\",\"version\":\"1\"}}"
                        (%mcp-json version) elicitation)))

(defun %mcp-call (id name &optional (arguments "{}"))
  (%mcp-request id "tools/call"
                (format nil "{\"name\":~A,\"arguments\":~A}" (%mcp-json name) arguments)))

(defun %mcp-run-call (id input &optional timeout)
  (%mcp-call id "run" (format nil "{\"input\":~A~@[,\"timeout\":~A~]}" (%mcp-json input) timeout)))

(defun %mcp-elicitation-answer (id action &optional (approve t))
  (format nil "{\"jsonrpc\":\"2.0\",\"id\":~A,\"result\":{\"action\":~A~:[~;,\"content\":{\"approve\":~:[false~;true~]}~]}}"
          (%mcp-json id) (%mcp-json action) (equal action "accept") approve))

(defun %mcp-accepted-run (id input elicitation)
  "The lines of a run call of INPUT, which classifies confirm, and the
client's acceptance of the ELICITATION-th approval request."
  (list (%mcp-run-call id input)
        (%mcp-elicitation-answer (format nil "nshell-elicitation-~D" elicitation) "accept")))

(defun %mcp-exchange (&rest lines)
  "Run the server on LINES and return every message it wrote, decoded, in
order."
  (let ((output (make-string-output-stream)))
    (with-input-from-string (input (format nil "~{~A~%~}" lines))
      (expect (nshell.feature.machine:run-mcp-server :input input :output output)
              :to-equal 0))
    (with-input-from-string (stream (get-output-stream-string output))
      (loop for line = (read-line stream nil nil)
            while line
            collect (json-kit:parse line)))))

(defun %mcp-reply (messages id)
  (find-if (lambda (message)
             (and (equal (gethash "id" message) id)
                  (null (gethash "method" message))))
           messages))

(defun %mcp-elicitations (messages)
  (remove-if-not (lambda (message) (equal (gethash "method" message) "elicitation/create"))
                 messages))

(defun %mcp-envelope (messages id)
  "Return the envelope of the tools/call reply ID after checking the tool
result's shape: the envelope validates, the text content holds the same
envelope, and isError is set exactly when the envelope is not ok."
  (let* ((result (gethash "result" (%mcp-reply messages id)))
         (envelope (gethash "structuredContent" result))
         (content (gethash "content" result)))
    (expect (machine-envelope-failures envelope) :to-be-null)
    (expect (length content) :to-equal 1)
    (expect (json-at content 0 "type") :to-equal "text")
    (expect (%mcp-json (json-kit:parse (json-at content 0 "text")))
            :to-equal (%mcp-json envelope))
    (expect (gethash "isError" result)
            :to-equal (if (eq t (gethash "ok" envelope)) json-kit:+json-false+ t))
    envelope))

(describe "machine mcp protocol"
  (it "negotiates 2025-06-18 and keeps 2024-11-05"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (flet ((negotiated (version)
               (json-at (%mcp-reply (%mcp-exchange (%mcp-initialize :version version)) 1)
                        "result" "protocolVersion")))
        (expect (negotiated "2025-06-18") :to-equal "2025-06-18")
        (expect (negotiated "2024-11-05") :to-equal "2024-11-05")
        (expect (negotiated "1999-01-01") :to-equal "2025-06-18"))
      (let ((result (gethash "result" (%mcp-reply (%mcp-exchange (%mcp-initialize)) 1))))
        (expect (json-at result "serverInfo" "name") :to-equal "nshell")
        (expect (json-at result "serverInfo" "version")
                :to-equal (asdf:component-version (asdf:find-system "nshell")))
        (expect (hash-table-p (json-at result "capabilities" "tools")) :to-be-truthy))))

  (it "lists the ten machine tools and the two deprecated ones"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (let ((tools (json-at (%mcp-reply (%mcp-exchange (%mcp-initialize)
                                                       (%mcp-request 2 "tools/list"))
                                        2)
                            "result" "tools")))
        (expect (map 'list (lambda (tool) (gethash "name" tool)) tools)
                :to-equal +mcp-test-tool-names+)
        (expect (subseq +mcp-test-tool-names+ 0 10)
                :to-equal nshell.feature.machine:*machine-methods*)
        (loop for tool across tools
              for deprecated-p = (member (gethash "name" tool) '("list_sessions" "read_state")
                                         :test #'equal)
              do (expect (json-at tool "inputSchema" "type") :to-equal "object")
                 (expect (list (gethash "name" tool)
                               (eql 0 (search "Deprecated:" (gethash "description" tool))))
                         :to-equal (list (gethash "name" tool) (and deprecated-p t))))
        (expect (coerce (json-at (find "run" tools :key (lambda (tool) (gethash "name" tool))
                                                   :test #'equal)
                                 "inputSchema" "required")
                        'list)
                :to-equal '("input")))))

  (it "answers protocol errors as JSON-RPC errors and argument errors as E_PROTOCOL"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (let ((messages (%mcp-exchange
                       (%mcp-initialize)
                       "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
                       (%mcp-request 2 "nope")
                       (%mcp-call 3 "nope")
                       "{not json"
                       (%mcp-request 4 "ping")
                       (%mcp-call 5 "run")
                       (%mcp-call 6 "run" "{\"input\":3}")
                       (%mcp-call 7 "run" "\"text\"")
                       (%mcp-run-call 8 "echo hi" "-1")
                       (%mcp-call 9 "complete" "{\"input\":\"ec\",\"cursor\":99}")
                       (%mcp-call 10 "history" "{\"limit\":0}"))))
        (expect (length messages) :to-equal 11)
        (expect (json-at (%mcp-reply messages 2) "error" "code") :to-equal -32601)
        (expect (json-at (%mcp-reply messages 3) "error" "code") :to-equal -32602)
        (expect (json-at (find-if (lambda (message)
                                    (json-kit:json-null-p (gethash "id" message)))
                                  messages)
                         "error" "code")
                :to-equal -32700)
        (expect (hash-table-p (json-at (%mcp-reply messages 4) "result")) :to-be-truthy)
        (dolist (id '(5 6 7 8 9 10))
          (let ((envelope (%mcp-envelope messages id)))
            (expect (list id (json-at envelope "error" "code"))
                    :to-equal (list id "E_PROTOCOL"))))
        ;; A rejected call is no run: it takes no seq.
        (expect (json-at (%mcp-envelope (%mcp-exchange (%mcp-initialize)
                                                       (%mcp-call 2 "run")
                                                       (%mcp-run-call 3 "echo one"))
                                        3)
                         "seq")
                :to-equal 1)))))

(describe "machine mcp tools"
  (it "answers every machine tool with a schema-valid envelope"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (let* ((messages (%mcp-exchange
                        (%mcp-initialize)
                        (%mcp-call 2 "initialize")
                        (%mcp-run-call 3 "echo hi")
                        (%mcp-call 4 "explain" "{\"input\":\"ls | grep foo\"}")
                        (%mcp-call 5 "complete" "{\"input\":\"ech\"}")
                        (%mcp-call 6 "state")
                        (%mcp-call 7 "history")
                        (%mcp-call 8 "help" "{\"topic\":\"cd\"}")
                        (%mcp-call 9 "query" "{\"query\":\"x\"}")
                        (%mcp-call 10 "read_output" "{\"id\":\"s_zzzzzz\"}")
                        (%mcp-call 11 "policy")
                        (%mcp-call 12 "help")))
             (session (json-at (%mcp-envelope messages 3) "session")))
        (let ((initialize (%mcp-envelope messages 2)))
          (expect (coerce (json-at initialize "value" "methods") 'list)
                  :to-equal nshell.feature.machine:*machine-methods*)
          (expect (json-at initialize "value" "session" "id") :to-equal session))
        (let ((run (%mcp-envelope messages 3)))
          (expect (json-at run "ok") :to-equal t)
          (expect (json-at run "stdout" "text") :to-equal (format nil "hi~%"))
          (expect (json-at run "seq") :to-equal 1))
        (expect (json-at (%mcp-envelope messages 4) "forms" 0 "kind") :to-equal "syntax")
        (expect (find "echo" (json-at (%mcp-envelope messages 5) "value" "candidates")
                      :key (lambda (candidate) (gethash "text" candidate)) :test #'equal)
                :to-be-truthy)
        (let ((state (%mcp-envelope messages 6)))
          (expect (json-at state "value" "session" "id") :to-equal session)
          (expect (json-at state "value" "session" "seq") :to-equal 1)
          (expect (json-at state "value" "last_status") :to-equal 0)
          (expect (json-at state "state" "last_status") :to-equal 0))
        (expect (json-at (%mcp-envelope messages 7) "value" "entries" 0 "input")
                :to-equal "echo hi")
        (expect (search "cd" (json-at (%mcp-envelope messages 8) "value" "text"))
                :to-be-truthy)
        (let ((query (%mcp-envelope messages 9)))
          (expect (json-at query "error" "code") :to-equal "E_NOT_IMPLEMENTED")
          (expect (json-at (%mcp-reply messages 9) "result" "isError") :to-equal t))
        (expect (json-at (%mcp-envelope messages 10) "error" "code") :to-equal "E_PERMISSION")
        (expect (plusp (length (json-at (%mcp-envelope messages 11) "value" "rules")))
                :to-be-truthy)
        (expect (stringp (json-at (%mcp-envelope messages 12) "value" "text"))
                :to-be-truthy))))

  (it "saves cut output under the session and run seq for read_output"
    (host-kit:with-temporary-directory (directory)
      (with-json-cache-home (root)
        (let ((numbers (format nil "~Anumbers" (sb-ext:native-namestring directory))))
          (with-open-file (out numbers :direction :output)
            (loop for n from 1 to 10000 do (format out "~D~%" n)))
          ;; cat is a read-only known command, so it runs unasked.
          (let* ((messages (%mcp-exchange (%mcp-initialize)
                                          (%mcp-run-call 2 "echo short")
                                          (%mcp-run-call 3 (format nil "cat ~A" numbers))))
                 (envelope (%mcp-envelope messages 3))
                 (session (json-at envelope "session")))
            (expect (json-at envelope "seq") :to-equal 2)
            (expect (json-at envelope "stdout" "truncated") :to-equal t)
            (expect (json-at envelope "stdout" "path")
                    :to-equal (format nil "~A~A/2.txt" root session))
            ;; The saved run stays readable after the server ended.
            (let ((read (%mcp-envelope
                         (%mcp-exchange (%mcp-initialize)
                                        (%mcp-call 2 "read_output"
                                                   (format nil "{\"id\":~A,\"seq\":2,\"limit\":6}"
                                                           (%mcp-json session))))
                         2)))
              (expect (json-at read "value" "text") :to-equal (format nil "1~%2~%3~%")))))
        ;; A server whose runs saved nothing leaves no session directory.
        (let* ((messages (%mcp-exchange (%mcp-initialize) (%mcp-run-call 2 "echo short")))
               (session (json-at (%mcp-envelope messages 2) "session")))
          (expect (probe-file (format nil "~A~A/" root session)) :to-be-null)))))

  (it "keeps the deprecated tools' payloads"
    (host-kit:with-temporary-directory (directory)
      (with-json-cache-home (root)
        (declare (ignorable root))
        (let* ((nshell.feature.assistant:*assistant-state-directory-path-override*
                 (merge-pathnames "state/" directory))
               (messages (%mcp-exchange
                          (%mcp-initialize)
                          (%mcp-call 2 "list_sessions")
                          (%mcp-call 3 "read_state" "{\"session_id\":\"never\"}")))
               (sessions (json-at (%mcp-reply messages 2) "result")))
          (expect (length (json-at sessions "structuredContent" "sessions")) :to-equal 0)
          (expect (json-kit:json-false-p (json-at sessions "isError")) :to-be-truthy)
          (expect (json-at (%mcp-reply messages 3) "result" "structuredContent" "error")
                  :to-equal "unknown session_id")
          (expect (json-at (%mcp-reply messages 3) "result" "isError") :to-equal t))))))

(describe "machine mcp session"
  (it "keeps one session id and counts the run calls"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (let* ((messages (%mcp-exchange (%mcp-initialize)
                                      (%mcp-run-call 2 "echo one")
                                      (%mcp-run-call 3 "ls /nshell-mcp-test-missing")
                                      (%mcp-run-call 4 "echo two")
                                      (%mcp-call 5 "state")
                                      (%mcp-call 6 "history" "{\"query\":\"echo\",\"limit\":1}")
                                      (%mcp-call 7 "history")))
             (runs (mapcar (lambda (id) (%mcp-envelope messages id)) '(2 3 4)))
             (session (json-at (first runs) "session")))
        (expect (and (stringp session) (string= "s_" session :end2 2)) :to-be-truthy)
        (expect (mapcar (lambda (run) (json-at run "session")) runs)
                :to-equal (list session session session))
        (expect (mapcar (lambda (run) (json-at run "seq")) runs) :to-equal '(1 2 3))
        (expect (json-at (%mcp-envelope messages 5) "value" "session" "seq") :to-equal 3)
        (expect (map 'list (lambda (entry) (list (gethash "seq" entry) (gethash "input" entry)))
                     (json-at (%mcp-envelope messages 6) "value" "entries"))
                :to-equal '((3 "echo two")))
        (expect (plusp (json-at (second runs) "status")) :to-be-truthy)
        (expect (map 'list (lambda (entry) (list (gethash "seq" entry) (gethash "status" entry)))
                     (json-at (%mcp-envelope messages 7) "value" "entries"))
                :to-equal (list (list 3 0) (list 2 (json-at (second runs) "status")) (list 1 0))))))

  (it "keeps the shell state from one run call to the next"
    (with-json-cache-home (root)
      (declare (ignorable root))
      ;; set and exit classify confirm, so the client accepts them.
      (let ((messages (apply #'%mcp-exchange
                             (append (list (%mcp-initialize :elicitation t))
                                     (%mcp-accepted-run 2 "set MCP_TEST_KEPT kept" 1)
                                     (list (%mcp-run-call 3 "echo $MCP_TEST_KEPT"))
                                     (%mcp-accepted-run 4 "exit 3" 2)
                                     (list (%mcp-run-call 5 "echo after"))))))
        (expect (json-at (%mcp-envelope messages 3) "stdout" "text")
                :to-equal (format nil "kept~%"))
        (expect (json-at (%mcp-envelope messages 4) "status") :to-equal 3)
        (expect (json-at (%mcp-envelope messages 5) "stdout" "text")
                :to-equal (format nil "after~%"))))))

(describe "machine mcp approval"
  (it "runs safe input without asking and refuses block input without asking"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (let ((messages (%mcp-exchange (%mcp-initialize :elicitation t)
                                     (%mcp-run-call 2 "echo hi")
                                     ;; rm refuses to remove ".", so this stays
                                     ;; harmless even if it ran.
                                     (%mcp-run-call 3 "rm -r ."))))
        (expect (%mcp-elicitations messages) :to-be-null)
        (expect (json-at (%mcp-envelope messages 2) "ok") :to-equal t)
        (let ((blocked (%mcp-envelope messages 3)))
          (expect (json-at blocked "error" "code") :to-equal "E_BLOCKED_BY_POLICY")
          (expect (json-at blocked "seq") :to-equal 2)))))

  (it "runs confirm input the client's user accepts"
    (host-kit:with-temporary-directory (directory)
      (with-json-cache-home (root)
        (declare (ignorable root))
        (let* ((victim (format nil "~Avictim" (sb-ext:native-namestring directory)))
               (marker (format nil "~A/keep" victim))
               (input (format nil "rm -r ~A" victim)))
          (ensure-directories-exist marker)
          (with-open-file (out marker :direction :output) (write-string "x" out))
          (let* ((messages (%mcp-exchange (%mcp-initialize :elicitation t)
                                          (%mcp-run-call 2 input)
                                          (%mcp-elicitation-answer "nshell-elicitation-1"
                                                                   "accept")))
                 (request (first (%mcp-elicitations messages))))
            (expect (length (%mcp-elicitations messages)) :to-equal 1)
            (expect (gethash "id" request) :to-equal "nshell-elicitation-1")
            (expect (search input (json-at request "params" "message")) :to-be-truthy)
            (expect (search "classify/delete-dir" (json-at request "params" "message"))
                    :to-be-truthy)
            (expect (coerce (json-at request "params" "requestedSchema" "required") 'list)
                    :to-equal '("approve"))
            (expect (json-at request "params" "requestedSchema" "properties" "approve" "type")
                    :to-equal "boolean")
            (let ((envelope (%mcp-envelope messages 2)))
              (expect (json-at envelope "ok") :to-equal t)
              (expect (json-at envelope "safety" "level") :to-equal "confirm"))
            (expect (probe-file marker) :to-be-null))))))

  (it "answers E_NEEDS_APPROVAL when nobody approves"
    (with-json-cache-home (root)
      (declare (ignorable root))
      ;; No safe command spec covers true: an unknown command is confirm.
      (let ((messages (%mcp-exchange
                       (%mcp-initialize :elicitation t)
                       (%mcp-run-call 2 "true")
                       (%mcp-elicitation-answer "nshell-elicitation-1" "decline")
                       (%mcp-run-call 3 "true")
                       (%mcp-elicitation-answer "nshell-elicitation-2" "accept" nil)
                       (%mcp-run-call 4 "true")
                       (%mcp-elicitation-answer "nshell-elicitation-3" "cancel")
                       (%mcp-run-call 5 "true")
                       "{\"jsonrpc\":\"2.0\",\"id\":\"nshell-elicitation-4\",\"error\":{\"code\":-1,\"message\":\"no\"}}")))
        (expect (length (%mcp-elicitations messages)) :to-equal 4)
        (dolist (id '(2 3 4 5))
          (expect (list id (json-at (%mcp-envelope messages id) "error" "code"))
                  :to-equal (list id "E_NEEDS_APPROVAL"))))
      (let ((messages (%mcp-exchange (%mcp-initialize) (%mcp-run-call 2 "true"))))
        (expect (%mcp-elicitations messages) :to-be-null)
        (expect (json-at (%mcp-envelope messages 2) "error" "code") :to-equal "E_NEEDS_APPROVAL"))))

  (it "handles requests that arrive during an elicitation after the run"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (let* ((messages (%mcp-exchange (%mcp-initialize :elicitation t)
                                      (%mcp-run-call 2 "true")
                                      (%mcp-call 3 "state")
                                      (%mcp-request 4 "ping")
                                      (%mcp-elicitation-answer "nshell-elicitation-1"
                                                               "accept")))
             (order (mapcar (lambda (message)
                              (or (gethash "method" message) (gethash "id" message)))
                            messages)))
        (expect order :to-equal '(1 "elicitation/create" 2 3 4))
        (expect (json-at (%mcp-envelope messages 2) "ok") :to-equal t)
        ;; The state call waited for the run it arrived during.
        (expect (json-at (%mcp-envelope messages 3) "value" "session" "seq") :to-equal 1))))

  (it "treats the end of input during an elicitation as no approval"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (let ((messages (%mcp-exchange (%mcp-initialize :elicitation t)
                                     (%mcp-run-call 2 "true")
                                     (%mcp-call 3 "state"))))
        (expect (length (%mcp-elicitations messages)) :to-equal 1)
        (expect (json-at (%mcp-envelope messages 2) "error" "code") :to-equal "E_NEEDS_APPROVAL")
        (expect (json-at (%mcp-envelope messages 3) "ok") :to-equal t)))))

(describe "machine mcp robustness"
  (it "answers a message that is not a JSON object with Invalid Request"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (let ((messages (%mcp-exchange "[1]" "3" "\"text\"" "[]")))
        (expect (mapcar (lambda (message)
                          (list (json-kit:json-null-p (gethash "id" message))
                                (json-at message "error" "code")))
                        messages)
                :to-equal '((t -32600) (t -32600) (t -32600) (t -32600))))))

  (it "asks for approval only on a protocol revision with elicitation"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (let ((messages (%mcp-exchange (%mcp-initialize :elicitation t :version "2024-11-05")
                                     (%mcp-run-call 2 "true"))))
        (expect (%mcp-elicitations messages) :to-be-null)
        (expect (json-at (%mcp-envelope messages 2) "error" "code")
                :to-equal "E_NEEDS_APPROVAL"))))

  (it "drops a run the client cancels while its approval is pending"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (let ((messages (%mcp-exchange
                       (%mcp-initialize :elicitation t)
                       (%mcp-run-call 2 "true")
                       "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":2,\"reason\":\"user\"}}"
                       (%mcp-run-call 3 "echo after")
                       (%mcp-call 4 "history"))))
        (expect (%mcp-reply messages 2) :to-be-null)
        (expect (json-at (%mcp-envelope messages 3) "seq") :to-equal 1)
        (expect (map 'list (lambda (entry) (gethash "input" entry))
                     (json-at (%mcp-envelope messages 4) "value" "entries"))
                :to-equal '("echo after"))))
    (with-json-cache-home (root)
      (declare (ignorable root))
      ;; A request kept during the wait and cancelled before its turn gets no reply.
      (let ((messages (%mcp-exchange
                       (%mcp-initialize :elicitation t)
                       (%mcp-run-call 2 "true")
                       (%mcp-call 3 "state")
                       "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":3}}"
                       (%mcp-elicitation-answer "nshell-elicitation-1" "accept"))))
        (expect (json-at (%mcp-envelope messages 2) "ok") :to-equal t)
        (expect (%mcp-reply messages 3) :to-be-null))))

  (it "refuses an approved run whose verdict changed before it ran"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (let ((calls 0))
        (with-temporary-function
            ((quote nshell.feature.machine::%classify-input)
             (lambda (input)
               (declare (ignore input))
               (values (list :confirm (if (= 1 (incf calls))
                                          (cons "classify/unknown-command" "unknown command")
                                          (cons "classify/delete-dir" "deletes a directory")))
                       t)))
          (let ((messages (%mcp-exchange (%mcp-initialize :elicitation t)
                                         (%mcp-run-call 2 "echo hi")
                                         (%mcp-elicitation-answer "nshell-elicitation-1"
                                                                  "accept"))))
            (expect (json-at (%mcp-envelope messages 2) "error" "code")
                    :to-equal "E_NEEDS_APPROVAL")
            (expect (json-at (%mcp-envelope messages 2) "stdout" "text") :to-equal ""))))))

  (it "refuses to go on in a session whose run could not be stopped"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (with-temporary-function
          ((quote nshell.feature.machine::%run-batch-with-deadline)
           (lambda (&rest arguments)
             (declare (ignore arguments))
             (let ((run (nshell.feature.machine::%make-json-run)))
               (setf (nshell.feature.machine::json-run-timed-out-p run) t
                     (nshell.feature.machine::json-run-worker-alive-p run) t)
               run)))
        (let ((messages (%mcp-exchange (%mcp-initialize)
                                       (%mcp-run-call 2 "echo stuck")
                                       (%mcp-run-call 3 "echo next")
                                       (%mcp-call 4 "explain" "{\"input\":\"ls\"}")
                                       (%mcp-call 5 "complete" "{\"input\":\"ec\"}")
                                       (%mcp-call 6 "state")
                                       (%mcp-call 7 "policy"))))
          (expect (json-at (%mcp-envelope messages 2) "error" "code") :to-equal "E_TIMEOUT")
          (dolist (id '(3 4 5 6))
            (let ((envelope (%mcp-envelope messages id)))
              (expect (list id (json-at envelope "error" "code"))
                      :to-equal (list id "E_INTERNAL"))
              (expect (search "could not be stopped" (json-at envelope "error" "message"))
                      :to-be-truthy)))
          (expect (json-at (%mcp-envelope messages 7) "ok") :to-equal t)))))

  (it "saves cut output even after the live session directory was pruned"
    (host-kit:with-temporary-directory (directory)
      (with-json-cache-home (root)
        (let ((numbers (format nil "~Anumbers" (sb-ext:native-namestring directory))))
          (with-open-file (out numbers :direction :output)
            (loop for n from 1 to 10000 do (format out "~D~%" n)))
          (let* ((messages
                   (apply #'%mcp-exchange
                          (append (list (%mcp-initialize :elicitation t))
                                  ;; As another process's prune would: the empty
                                  ;; live session is among the oldest.
                                  (%mcp-accepted-run
                                   2 "(NSHELL.FEATURE.MACHINE:PRUNE-OUTPUT-SESSIONS :KEEP 0)" 1)
                                  (list (%mcp-run-call 3 (format nil "cat ~A" numbers))))))
                 (pruned (%mcp-envelope messages 2))
                 (envelope (%mcp-envelope messages 3))
                 (path (json-at envelope "stdout" "path")))
            (expect (json-at pruned "ok") :to-equal t)
            (expect path :to-equal (format nil "~A~A/2.txt" root (json-at envelope "session")))
            (expect (probe-file path) :to-be-truthy)))))))
