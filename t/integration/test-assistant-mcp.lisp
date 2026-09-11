(in-package #:nshell/test)

(defun %assistant-mcp-test-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun %assistant-mcp-test-request (json)
  (json-kit:parse json :object-type :alist :array-type :list))

(defun %assistant-mcp-test-response (json &rest state)
  (apply #'nshell.feature.assistant:assistant-mcp-handle-request
         (%assistant-mcp-test-request json)
         state))

(describe "assistant-mcp-protocol-contracts"
  (it "handles-initialize-notification-and-tools-list"
    (let ((response
            (%assistant-mcp-test-response
             "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}")))
      (expect "2.0" :to-equal (%assistant-mcp-test-field response "jsonrpc"))
      (expect "2024-11-05" :to-equal
              (%assistant-mcp-test-field
               (%assistant-mcp-test-field response "result")
               "protocolVersion"))
      (expect nil :to-be
              (%assistant-mcp-test-response
               "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}")))
    (let* ((response
             (%assistant-mcp-test-response
              "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"))
           (tools (%assistant-mcp-test-field
                   (%assistant-mcp-test-field response "result")
                   "tools")))
      (expect 2 :to-equal (length tools))
      (expect "list_sessions" :to-equal
              (%assistant-mcp-test-field (aref tools 0) "name"))
      (expect "read_state" :to-equal
              (%assistant-mcp-test-field (aref tools 1) "name"))))

  (it "returns-bounded-state-content-through-the-read-tool"
    (let* ((response
             (%assistant-mcp-test-response
              "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"read_state\",\"arguments\":{\"session_id\":\"s1\",\"tail_lines\":2}}}"
              :session-ids '("s1")
              :snapshot-present-p t
              :snapshot-content "{\"cwd\":\"/tmp/project\"}"
              :transcript-session-id "s1"
              :transcript-present-p t
              :transcript-lines '("line-1" "line-2" "line-3")))
           (result (%assistant-mcp-test-field response "result"))
           (structured (%assistant-mcp-test-field result "structuredContent"))
           (transcript (%assistant-mcp-test-field structured "transcript"))
           (lines (%assistant-mcp-test-field transcript "lines"))
           (content (%assistant-mcp-test-field
                     (aref (%assistant-mcp-test-field result "content") 0)
                     "text")))
      (expect nil :to-be (%assistant-mcp-test-field result "isError"))
      (expect "{\"cwd\":\"/tmp/project\"}"
              :to-equal
              (%assistant-mcp-test-field
               (%assistant-mcp-test-field structured "snapshot")
               "content"))
      (expect 2 :to-equal (length lines))
      (expect "line-2" :to-equal (aref lines 0))
      (expect "line-3" :to-equal (aref lines 1))
      (expect (search "line-2" content) :to-be-truthy)
      (expect nil :to-be (search "line-1" content))))

  (it "reports-missing-files-as-normal-tool-data"
    (host-kit:with-temporary-directory (directory)
      (let ((state-directory (merge-pathnames "state/" directory)))
        (let ((nshell.feature.assistant:*assistant-state-directory-path-override*
                state-directory))
          (let* ((response
                   (nshell.feature.assistant::%assistant-mcp-response-for-request
                    (%assistant-mcp-test-request
                     "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"read_state\",\"arguments\":{\"session_id\":\"never\",\"tail_lines\":1}}}")))
                 (result (%assistant-mcp-test-field response "result"))
                 (structured
                   (%assistant-mcp-test-field result "structuredContent")))
            (expect nil :to-be (%assistant-mcp-test-field result "isError"))
            (expect nil :to-be
                    (%assistant-mcp-test-field
                     (%assistant-mcp-test-field structured "snapshot")
                     "available"))
            (expect nil :to-be
                    (%assistant-mcp-test-field
                     (%assistant-mcp-test-field structured "transcript")
                     "available"))))))))

  (it "validates-and-bounds-tail-line-options"
    (multiple-value-bind (session-id tail-lines error-message)
        (nshell.feature.assistant:assistant-mcp-request-state-options
         (%assistant-mcp-test-request
          "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"read_state\",\"arguments\":{\"session_id\":\"s1\",\"tail_lines\":999}}}"))
      (expect "s1" :to-equal session-id)
      (expect nshell.feature.assistant:+assistant-mcp-max-transcript-tail-lines+
              :to-equal tail-lines)
      (expect nil :to-be error-message))
    (multiple-value-bind (session-id tail-lines error-message)
        (nshell.feature.assistant:assistant-mcp-request-state-options
         (%assistant-mcp-test-request
          "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"read_state\",\"arguments\":{\"session_id\":\"s1\",\"tail_lines\":0}}}"))
      (expect nil :to-be session-id)
      (expect nil :to-be tail-lines)
      (expect error-message :to-be-truthy)))

  (it "returns-json-rpc-errors-for-unknown-methods-and-tools"
    (let ((method-response
            (%assistant-mcp-test-response
             "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"unknown\"}"))
          (tool-response
            (%assistant-mcp-test-response
             "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"unknown\"}}")))
      (expect -32601 :to-equal
              (%assistant-mcp-test-field
               (%assistant-mcp-test-field method-response "error") "code"))
      (expect -32602 :to-equal
              (%assistant-mcp-test-field
               (%assistant-mcp-test-field tool-response "error") "code"))))
