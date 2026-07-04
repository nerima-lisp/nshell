(in-package #:nshell/test)

(in-suite history-domain-tests)

(test history-entry-creation
  "History entries can be created."
  (let ((entry (nshell.domain.history:make-history-entry "ls -la")))
    (is (string= "ls -la" (nshell.domain.history:entry-text entry)))
    (is (integerp (nshell.domain.history:entry-timestamp entry)))
    (is (null (nshell.domain.history:entry-exit-code entry)))))

(test history-entry-with-exit-code
  "Entry can store exit code."
  (let ((entry (nshell.domain.history:make-history-entry "false" 0 1)))
    (is (= 1 (nshell.domain.history:entry-exit-code entry)))))

(test history-raw-constructors-are-internal-boundaries
  (let ((entry (nshell.domain.history:make-history-entry "echo ok" 0 0))
        (history (nshell.domain.history:make-command-history :max-entries 7)))
    (is (nshell.domain.history:history-entry-p entry))
    (is (string= "echo ok" (nshell.domain.history:entry-text entry)))
    (is (= 7 (nshell.domain.history:command-history-max-entries history)))
    (is (fboundp 'nshell.domain.history::%make-history-entry))
    (is (fboundp 'nshell.domain.history::%make-command-history))))
