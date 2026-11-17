(in-package #:nshell/test)

;;; `nshell --mcp` as a real process (task P1-6): one session of JSON-RPC
;;; lines on standard input, including the client's answer to the server's
;;; elicitation request, whose id the server numbers predictably.  The same
;;; session runs from the current source and from the built executable
;;; (NSHELL_BIN, skipped outside CI as the golden tests are).

(defun %mcp-e2e-environment (directory)
  (let ((names '("HOME" "XDG_CONFIG_HOME" "XDG_DATA_HOME" "XDG_STATE_HOME"
                 "XDG_CACHE_HOME" "NSHELL_AI_COMMAND")))
    (append
     (loop for (name sub) in '(("HOME" "home/") ("XDG_CONFIG_HOME" "config/")
                               ("XDG_DATA_HOME" "data/") ("XDG_STATE_HOME" "state/")
                               ("XDG_CACHE_HOME" "cache/"))
           for path = (merge-pathnames sub directory)
           do (ensure-directories-exist path)
           collect (format nil "~A=~A" name
                           (string-right-trim "/" (sb-ext:native-namestring path))))
     (list "NSHELL_AI_COMMAND=/nonexistent")
     (remove-if (lambda (entry)
                  (member (subseq entry 0 (or (position #\= entry) (length entry)))
                          names :test #'string=))
                (%e2e-child-environment)))))

(defun %mcp-e2e-serve (program directory lines)
  "Run PROGRAM, a list of the executable and its arguments, as an MCP server
in DIRECTORY on the JSON-RPC LINES.  Return its standard output lines, its
exit code and its stderr."
  (let ((result (host-kit:run-program (first program) (rest program)
                                      :directory directory
                                      :environment (%mcp-e2e-environment directory)
                                      :input (format nil "~{~A~%~}" lines)
                                      :timeout 120)))
    (values (with-input-from-string (stream (host-kit:process-result-stdout result))
              (loop for line = (read-line stream nil nil)
                    while line
                    collect line))
            (host-kit:process-result-exit-code result)
            (host-kit:process-result-stderr result))))

(defun %mcp-e2e-session (program directory work)
  "Drive one session of PROGRAM in DIRECTORY whose confirm run changes to
WORK.  Return the decoded messages it wrote, its exit code and its stderr."
  (let* ((lines
           (list "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{\"elicitation\":{}},\"clientInfo\":{\"name\":\"e2e\",\"version\":\"1\"}}}"
                 "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
                 "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"
                 "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"run\",\"arguments\":{\"input\":\"echo hi\"}}}"
                 (format nil "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"run\",\"arguments\":{\"input\":~A}}}"
                         (json-kit:stringify (format nil "cd ~A" work)))
                 "{\"jsonrpc\":\"2.0\",\"id\":\"nshell-elicitation-1\",\"result\":{\"action\":\"accept\",\"content\":{\"approve\":true}}}"
                 "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"run\",\"arguments\":{\"input\":\"pwd\"}}}"
                 "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"query\",\"arguments\":{\"query\":\"x\"}}}"
                 (format nil "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"run\",\"arguments\":{\"input\":~A}}}"
                         (json-kit:stringify (format nil "touch ~A/declined" work)))
                 "{\"jsonrpc\":\"2.0\",\"id\":\"nshell-elicitation-2\",\"result\":{\"action\":\"decline\"}}"
                 (format nil "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"run\",\"arguments\":{\"input\":~A}}}"
                         (json-kit:stringify
                          (format nil "echo ,(CLOSE (OPEN ~S :DIRECTION :OUTPUT))"
                                  (format nil "~A/value-form" work))))
                 "{\"jsonrpc\":\"2.0\",\"id\":\"nshell-elicitation-3\",\"result\":{\"action\":\"decline\"}}"))
         )
    (multiple-value-bind (output exit-code stderr) (%mcp-e2e-serve program directory lines)
      (values (mapcar #'json-kit:parse output) exit-code stderr))))

(defun %mcp-e2e-check-terminal-io (program)
  "Approved runs that write to and read from *terminal-io* must not reach the
protocol streams: every output line stays JSON and the request after them is
answered."
  (host-kit:with-temporary-directory (directory)
    (multiple-value-bind (output exit-code)
        (%mcp-e2e-serve
         program directory
         (list "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{\"elicitation\":{}}}}"
               "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"run\",\"arguments\":{\"input\":\"(format *terminal-io* \\\"TERMIO~%\\\")\"}}}"
               "{\"jsonrpc\":\"2.0\",\"id\":\"nshell-elicitation-1\",\"result\":{\"action\":\"accept\",\"content\":{\"approve\":true}}}"
               "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"run\",\"arguments\":{\"input\":\"(read-line *query-io* nil)\",\"timeout\":10}}}"
               "{\"jsonrpc\":\"2.0\",\"id\":\"nshell-elicitation-2\",\"result\":{\"action\":\"accept\",\"content\":{\"approve\":true}}}"
               "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"ping\"}"))
      (expect exit-code :to-equal 0)
      (let ((messages (mapcar (lambda (line)
                                (handler-case (json-kit:parse line)
                                  (error () (list :not-json line))))
                              output)))
        (expect (remove-if-not #'listp messages) :to-be-null)
        (expect (mapcar (lambda (message)
                          (or (gethash "method" message) (gethash "id" message)))
                        messages)
                :to-equal '(1 "elicitation/create" 2 "elicitation/create" 3 4))
        (flet ((envelope (id)
                 (json-at (find id messages :key (lambda (message) (gethash "id" message))
                                            :test #'equal)
                          "result" "structuredContent")))
          (expect (json-at (envelope 2) "ok") :to-equal t)
          ;; The read finds an empty stream at once instead of the next
          ;; protocol line; nshell reads nil case-preserving, so it signals.
          (expect (search "end of file" (json-at (envelope 3) "error" "message"))
                  :to-be-truthy))))))

(defun %mcp-e2e-check-session (program)
  (host-kit:with-temporary-directory (directory)
    (let* ((work-directory (merge-pathnames "work/" directory))
           (work (progn (ensure-directories-exist work-directory)
                        (string-right-trim "/" (sb-ext:native-namestring
                                                (truename work-directory))))))
      (multiple-value-bind (messages exit-code stderr)
          (%mcp-e2e-session program directory work)
        (expect exit-code :to-equal 0)
        (expect stderr :to-equal "")
        (labels ((reply (id)
                   (find-if (lambda (message)
                              (and (equal (gethash "id" message) id)
                                   (null (gethash "method" message))))
                            messages))
                 (envelope (id)
                   (let ((envelope (json-at (reply id) "result" "structuredContent")))
                     (expect (machine-envelope-failures envelope) :to-be-null)
                     envelope)))
          (expect (mapcar (lambda (message)
                            (or (gethash "method" message) (gethash "id" message)))
                          messages)
                  :to-equal '(1 2 3 "elicitation/create" 4 5 6 "elicitation/create" 7
                              "elicitation/create" 8))
          (expect (json-at (reply 1) "result" "protocolVersion") :to-equal "2025-06-18")
          (expect (json-at (reply 1) "result" "serverInfo" "name") :to-equal "nshell")
          (expect (length (json-at (reply 2) "result" "tools")) :to-equal 12)
          (expect (json-at (envelope 3) "stdout" "text") :to-equal (format nil "hi~%"))
          (let ((request (find "elicitation/create" messages
                               :key (lambda (message) (gethash "method" message))
                               :test #'equal)))
            (expect (gethash "id" request) :to-equal "nshell-elicitation-1")
            (expect (search (format nil "cd ~A" work) (json-at request "params" "message"))
                    :to-be-truthy))
          (expect (json-at (envelope 4) "ok") :to-equal t)
          ;; The cd of the approved run is still in effect for the next call.
          (expect (json-at (envelope 5) "stdout" "text") :to-equal (format nil "~A~%" work))
          (expect (mapcar (lambda (id) (json-at (envelope id) "seq")) '(3 4 5))
                  :to-equal '(1 2 3))
          (expect (remove-duplicates (mapcar (lambda (id) (json-at (envelope id) "session"))
                                             '(3 4 5))
                                     :test #'equal)
                  :to-equal (list (json-at (envelope 3) "session")))
          (expect (json-at (envelope 6) "error" "code") :to-equal "E_NOT_IMPLEMENTED")
          (expect (json-at (reply 6) "result" "isError") :to-equal t)
          ;; After an accepted confirm run, a declined one does not run.
          (expect (json-at (envelope 7) "error" "code") :to-equal "E_NEEDS_APPROVAL")
          (expect (probe-file (format nil "~A/declined" work)) :to-be-null)
          ;; A value form that writes is confirm, so declining it keeps it from running.
          (expect (json-at (envelope 8) "safety" "level") :to-equal "confirm")
          (expect (json-at (envelope 8) "error" "code") :to-equal "E_NEEDS_APPROVAL")
          (expect (probe-file (format nil "~A/value-form" work)) :to-be-null))))))

(describe "machine mcp stdio process"
  (it "serves one session from the current source"
    (let ((root (namestring (asdf:system-source-directory :nshell))))
      (%mcp-e2e-check-session
       (append (list (current-sbcl-executable) "--noinform")
               (%asdf-bootstrap-forms root)
               (list "--eval" (%nshell-main-form '("--mcp")))))))

  (it "serves one session from the built executable"
    (%mcp-e2e-check-session (list (%json-golden-binary) "--mcp")))

  (it "keeps *terminal-io* off the protocol streams"
    (let ((root (namestring (asdf:system-source-directory :nshell))))
      (%mcp-e2e-check-terminal-io
       (append (list (current-sbcl-executable) "--noinform")
               (%asdf-bootstrap-forms root)
               (list "--eval" (%nshell-main-form '("--mcp")))))))

  (it "keeps *terminal-io* off the protocol streams in the built executable"
    (%mcp-e2e-check-terminal-io (list (%json-golden-binary) "--mcp"))))
