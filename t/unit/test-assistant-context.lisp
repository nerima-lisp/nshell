(in-package #:nshell/test)

(describe "assistant-context-contracts"
  (it "assembles only redacted, bounded context values"
    (let* ((context
             (nshell.feature.assistant:assemble-assistant-context
              :command "printf ghp_12345678901234567890"
              :exit 1
              :duration-ms 123
              :cwd "/Users/example/project"
              :git-status "main dirty"
              :last-output "old output\nlast visible output"
              :last-output-max-bytes 19
              :environment-names '("API_TOKEN=secret-value" "HOME=/Users/example")))
           (payload (nshell.feature.assistant:assistant-context-payload context))
           (printed (with-output-to-string (stream)
                      (write payload :stream stream))))
      (expect 1 :to-be
              (nshell.feature.assistant:assistant-context-exit context))
      (expect 123 :to-be
              (nshell.feature.assistant:assistant-context-duration-ms context))
      (expect "/Users/example/project" :to-equal
              (nshell.feature.assistant:assistant-context-cwd context))
      (expect "last visible output" :to-equal
              (nshell.feature.assistant:assistant-context-last-output context))
      (expect t :to-be-truthy (search "API_TOKEN" printed))
      (expect nil :to-be (search "secret-value" printed))
      (expect nil :to-be (search "ghp_12345678901234567890" printed))))

  (it "drops denylisted context lines before applying the output bound"
    (let ((context
            (nshell.feature.assistant:assemble-assistant-context
             :last-output "skip /tmp/private.env\nkeep this line"
             :last-output-max-bytes 100
             :denylist-paths '("*/private.env"))))
      (expect "keep this line" :to-equal
              (nshell.feature.assistant:assistant-context-last-output context)))))
