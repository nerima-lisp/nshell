(in-package #:nshell/test)

(describe "assistant-redaction-contracts"
  (it "removes known token shapes and PEM material"
    (let* ((pem (format nil "-----BEGIN TEST PRIVATE KEY-----~%secret-key-material~%-----END TEST PRIVATE KEY-----"))
           (raw (format nil "sk-abcdefghijklmnopqrstuvwxyz ghp_12345678901234567890 Bearer abcdefghijklmnopqrstuvwxyz ~a"
                        pem))
           (redacted (nshell.feature.assistant:redact-text raw)))
      (expect nil :to-be (search "sk-abcdefghijklmnopqrstuvwxyz" redacted))
      (expect nil :to-be (search "ghp_12345678901234567890" redacted))
      (expect nil :to-be (search "Bearer abcdefghijklmnopqrstuvwxyz" redacted))
      (expect nil :to-be (search "-----BEGIN TEST PRIVATE KEY-----" redacted))
      (expect (search "[REDACTED]" redacted) :to-be-truthy)))

  (it "keeps environment names while dropping values and denylisted lines"
    (let* ((payload
             (list :environment '("API_TOKEN=secret-environment-value"
                                  ("HOME" . "/Users/example"))
                   :output (format nil "cat /tmp/private.env~%visible output")
                   :command "cat /tmp/private.env"))
           (redacted
             (nshell.feature.assistant:redact-payload
              payload
              :denylist-paths '("*/private.env")
              :denylist-commands '("cat")))
           (printed (with-output-to-string (stream)
                      (write redacted :stream stream))))
      (expect (search "API_TOKEN" printed) :to-be-truthy)
      (expect nil :to-be (search "secret-environment-value" printed))
      (expect nil :to-be (search "/tmp/private.env" printed))
      (expect (search "visible output" printed) :to-be-truthy))))
