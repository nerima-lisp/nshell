(in-package #:nshell/test)

(describe "assistant-redaction-contracts"
  (it "removes known token shapes and PEM material"
    (let* ((pem "-----BEGIN TEST PRIVATE KEY-----\nsecret-key-material\n-----END TEST PRIVATE KEY-----")
           (raw (format nil "sk-abcdefghijklmnopqrstuvwxyz ghp_12345678901234567890 Bearer abcdefghijklmnopqrstuvwxyz ~a"
                        pem))
           (redacted (nshell.feature.assistant:redact-text raw)))
      (expect nil :to-be (search "sk-abcdefghijklmnopqrstuvwxyz" redacted))
      (expect nil :to-be (search "ghp_12345678901234567890" redacted))
      (expect nil :to-be (search "Bearer abcdefghijklmnopqrstuvwxyz" redacted))
      (expect nil :to-be (search "-----BEGIN TEST PRIVATE KEY-----" redacted))
      (expect t :to-be-truthy (search "[REDACTED]" redacted))))

  (it "keeps environment names while dropping values and denylisted lines"
    (let* ((payload
             (list :environment '("API_TOKEN=secret-environment-value"
                                  ("HOME" . "/Users/example"))
                   :output "cat /tmp/private.env\nvisible output"
                   :command "cat /tmp/private.env"))
           (redacted
             (nshell.feature.assistant:redact-payload
              payload
              :denylist-paths '("*/private.env")
              :denylist-commands '("cat")))
           (printed (with-output-to-string (stream)
                      (write redacted :stream stream))))
      (expect t :to-be-truthy (search "API_TOKEN" printed))
      (expect nil :to-be (search "secret-environment-value" printed))
      (expect nil :to-be (search "/tmp/private.env" printed))
      (expect t :to-be-truthy (search "visible output" printed)))))
