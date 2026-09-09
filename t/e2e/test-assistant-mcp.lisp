(in-package #:nshell/test)

(defun %assistant-mcp-e2e-json-lines (text)
  (with-input-from-string (stream text)
    (loop for line = (read-line stream nil nil)
          while line
          collect (json-kit:parse line :object-type :alist :array-type :list))))

(defun %assistant-mcp-e2e-run (state-home input)
  (let* ((root (asdf:system-source-directory :nshell))
         (program (append (list (current-sbcl-executable) "--noinform")
                          (%asdf-bootstrap-forms (namestring root))
                          (list "--eval" (%nshell-main-form '("--mcp"))))))
    (host-kit:with-environment-variables
        (("XDG_STATE_HOME" (namestring state-home)))
      (host-kit:run-program (first program) (rest program)
                            :directory root
                            :input input
                            :timeout 120))))

(describe "assistant-mcp-stdio-process-contracts"
  (it "serves-state-over-stdio-after-the-mcp-handshake"
    (host-kit:with-temporary-directory (directory)
      (let* ((state-home (merge-pathnames "xdg/" directory))
             (state-directory (merge-pathnames "nshell/" state-home))
             (snapshot-path (merge-pathnames "snapshot.json" state-directory))
             (transcript-path
               (merge-pathnames "transcript-session.jsonl" state-directory)))
        (ensure-directories-exist snapshot-path)
        (host-kit:write-file-string
         "{\"cwd\":\"/tmp/mcp\",\"session-id\":\"session\"}"
         snapshot-path)
        (host-kit:write-file-string
         (format nil "~{~a~^~%~}~%"
                 '("{\"text\":\"one\"}"
                   "{\"text\":\"two\"}"
                   "{\"text\":\"three\"}"))
         transcript-path)
        (let* ((input
                 (format nil "~{~a~%~}"
                         '("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"
                           "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
                           "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"
                           "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"list_sessions\",\"arguments\":{}}}"
                           "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"read_state\",\"arguments\":{\"session_id\":\"session\",\"tail_lines\":1}}}")))
               (result (%assistant-mcp-e2e-run state-home input))
               (stdout (host-kit:process-result-stdout result))
               (responses (%assistant-mcp-e2e-json-lines stdout)))
          (expect 0 :to-equal (host-kit:process-result-exit-code result))
          (expect "" :to-equal (host-kit:process-result-stderr result))
          (expect 4 :to-equal (length responses))
          (expect "2024-11-05" :to-equal
                  (%assistant-mcp-test-field
                   (%assistant-mcp-test-field (first responses) "result")
                   "protocolVersion"))
          (expect (search "session" stdout) :to-be-truthy)
          (expect (search "three" stdout) :to-be-truthy)
          (expect nil :to-be (search "\"text\":\"one\"" stdout)))))))
