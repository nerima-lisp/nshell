(in-package #:nshell/test)

(in-suite history-domain-tests)

(defun history-domain-external-symbol-p (name)
  (eq :external (nth-value 1 (find-symbol name "NSHELL.DOMAIN.HISTORY"))))

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
    (is (string= "echo ok" (nshell.domain.history:entry-text entry)))
    (is (= 7 (nshell.domain.history:history-capacity history)))
    (is (history-domain-external-symbol-p "MAKE-HISTORY-ENTRY"))
    (is (history-domain-external-symbol-p "ENTRY-TEXT"))
    (is (history-domain-external-symbol-p "ENTRY-TIMESTAMP"))
    (is (history-domain-external-symbol-p "ENTRY-EXIT-CODE"))
    (is (history-domain-external-symbol-p "HISTORY-ENTRY-TEXTS"))
    (is (not (history-domain-external-symbol-p "HISTORY-ENTRY-P")))
    (is (not (history-domain-external-symbol-p "HISTORY-ENTRY-TEXT")))
    (is (not (history-domain-external-symbol-p "HISTORY-ENTRY-TIMESTAMP")))
    (is (not (history-domain-external-symbol-p "HISTORY-ENTRY-EXIT-CODE")))
    (is (eq :internal (nth-value 1 (find-symbol "COMMAND-HISTORY-ENTRIES"
                                                 "NSHELL.DOMAIN.HISTORY"))))
    (is (eq :internal (nth-value 1 (find-symbol "COMMAND-HISTORY-MAX-ENTRIES"
                                                 "NSHELL.DOMAIN.HISTORY"))))
    (is (not (fboundp 'nshell.domain.history::history-entry-p)))
    (is (not (fboundp 'nshell.domain.history::copy-history-entry)))
    (is (fboundp 'nshell.domain.history::%make-history-entry-with-invariants))
    (is (fboundp 'nshell.domain.history::%allocate-history-entry))
    (is (fboundp 'nshell.domain.history::%make-command-history))))
