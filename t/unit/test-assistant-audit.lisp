(in-package #:nshell/test)

(defun %write-assistant-audit-test-file (path content)
  (with-open-file (stream path :direction :output :if-exists :supersede
                                :if-does-not-exist :create)
    (write-string content stream)))

(defun %assistant-audit-test-lines (count)
  (multiple-value-bind (lines present-p)
      (nshell.feature.assistant:assistant-audit-tail count)
    (values lines present-p)))

(describe "assistant-audit-tail-boundaries"
  (it "handles zero, exact, short, and excessive counts"
    (with-temporary-output-file (path :prefix "nshell-assistant-audit-tail-")
      (%write-assistant-audit-test-file path (format nil "one~%two~%three"))
      (let ((nshell.feature.assistant:*assistant-audit-file-path-override* path))
        (multiple-value-bind (lines present-p)
            (%assistant-audit-test-lines 0)
          (expect nil :to-equal lines)
          (expect nil :to-be present-p))
        (multiple-value-bind (lines present-p)
            (%assistant-audit-test-lines 1)
          (expect '("three") :to-equal lines)
          (expect t :to-be present-p))
        (expect '("one" "two" "three")
                :to-equal (first (multiple-value-list
                                  (%assistant-audit-test-lines 3))))
        (expect '("one" "two" "three")
                :to-equal (first (multiple-value-list
                                  (%assistant-audit-test-lines 10)))))))

  (it "does not add a phantom line for a trailing newline"
    (with-temporary-output-file (path :prefix "nshell-assistant-audit-tail-")
      (%write-assistant-audit-test-file path (format nil "one~%two~%"))
      (let ((nshell.feature.assistant:*assistant-audit-file-path-override* path))
        (expect '("one" "two")
                :to-equal (first (multiple-value-list
                                  (%assistant-audit-test-lines 3)))))))

  (it "returns no lines for an empty file"
    (with-temporary-output-file (path :prefix "nshell-assistant-audit-tail-")
      (%write-assistant-audit-test-file path "")
      (let ((nshell.feature.assistant:*assistant-audit-file-path-override* path))
        (multiple-value-bind (lines present-p)
            (%assistant-audit-test-lines 3)
          (expect nil :to-equal lines)
          (expect t :to-be present-p)))))

  (it "keeps long lines intact when selecting the tail"
    (with-temporary-output-file (path :prefix "nshell-assistant-audit-tail-")
      (let ((long-line (make-string 16384 :initial-element #\x)))
        (%write-assistant-audit-test-file
         path (format nil "first~%~a~%last" long-line))
        (let ((nshell.feature.assistant:*assistant-audit-file-path-override* path))
          (multiple-value-bind (lines present-p)
              (%assistant-audit-test-lines 2)
            (expect (list long-line "last") :to-equal lines)
            (expect t :to-be present-p)))))))

(describe "assistant-audit-log-contracts"
  (it "does not write through an audit file symlink"
    (host-kit:with-temporary-directory (directory)
      (let ((target (merge-pathnames "audit-target.jsonl" directory))
            (path (merge-pathnames "ai-audit.jsonl" directory)))
        (unwind-protect
             (progn
               (host-kit:write-file-string "unchanged\n" target)
               (sb-posix:symlink (namestring target) (namestring path))
               (let ((nshell.feature.assistant:*assistant-audit-file-path-override*
                       path))
                 (expect nil :to-be
                         (nshell.feature.assistant:append-assistant-audit-entry
                          '(("command" . "printf safe"))
                          '(("summary" . "safe")))))
               (expect "unchanged\n" :to-equal
                       (host-kit:read-file-string target))
               (expect #o120000
                       :to-equal
                       (logand (sb-posix:stat-mode (sb-posix:lstat path))
                               #o170000)))
          (when (probe-file path)
            (delete-file path))
          (when (probe-file target)
            (delete-file target))))))

  (it "appends JSONL after applying the same redaction to payload and response"
    (let ((path (merge-pathnames
                 (format nil "nshell-assistant-audit-~a.jsonl" (gensym))
                 (uiop:temporary-directory))))
      (unwind-protect
           (let ((nshell.feature.assistant:*assistant-audit-file-path-override*
                   path))
             (host-kit:write-file-string "" path)
             (sb-posix:chmod (namestring path) #o644)
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
                 (expect nil :to-be (search "response-secret-value" content))))
             (expect #o600
                     :to-equal
                     (logand (sb-posix:stat-mode
                              (sb-posix:stat path)) #o777)))
        (when (probe-file path)
          (delete-file path))))))
