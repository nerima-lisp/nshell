(in-package #:nshell/test)

(describe "assistant-audit-log-contracts"
  (it "appends JSONL after applying the same redaction to payload and response"
    (let ((path (merge-pathnames
                 (format nil "nshell-assistant-audit-~a.jsonl" (gensym))
                 (uiop:temporary-directory))))
      (unwind-protect
           (let ((nshell.feature.assistant:*assistant-audit-file-path-override*
                   path))
             (expect path :to-equal
                     (nshell.feature.assistant:assistant-audit-file-path))
             (expect (nshell.feature.assistant:append-assistant-audit-entry
                      `(("environment" . ("API_TOKEN=secret-value"))
                        ("output" .
                         ,(format nil "ghp_12345678901234567890~%-----BEGIN PRIVATE KEY-----"))
                        ("path" . "/tmp/private.env"))
                      '(("summary" . "Bearer response-secret-value"))
                      :denylist-paths '("*/private.env")
                      :denylist-commands '("cat"))
                     :to-be-truthy)
             (expect (nshell.feature.assistant:append-assistant-audit-entry
                      '(("environment" . ("HOME=/Users/example")))
                      '(("summary" . "ok")))
                     :to-be-truthy)
             (let ((lines
                     (with-open-file (stream path)
                       (loop for line = (read-line stream nil nil)
                             while line collect line))))
               (expect 2 :to-be (length lines))
               (expect (every (lambda (line) (json-kit:parse line)) lines)
                       :to-be-truthy)
               (let ((content (format nil "~{~a~^~%~}" lines)))
                 (expect (search "API_TOKEN" content) :to-be-truthy)
                 (expect nil :to-be (search "secret-value" content))
                 (expect nil :to-be
                         (search "ghp_12345678901234567890" content))
                 (expect nil :to-be (search "PRIVATE KEY" content))
                 (expect nil :to-be (search "/tmp/private.env" content))
                 (expect nil :to-be (search "response-secret-value" content)))))
        (when (probe-file path)
          (delete-file path))))))
