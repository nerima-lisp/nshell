(in-package #:nshell/test)

(defun history-domain-external-symbol-p (name)
  (eq :external (nth-value 1 (find-symbol name "NSHELL.DOMAIN.HISTORY"))))

(describe "history-domain-tests"
  (it "history-entry-creation"
    "History entries can be created."
    (let ((entry (nshell.domain.history:make-history-entry "ls -la")))
      (expect "ls -la" :to-equal (nshell.domain.history:entry-text entry))
      (expect (integerp (nshell.domain.history:entry-timestamp entry)) :to-be-truthy)
      (expect (nshell.domain.history:entry-exit-code entry) :to-be-null)))

  (it "history-entry-with-exit-code"
    "Entry can store exit code."
    (let ((entry (nshell.domain.history:make-history-entry "false" 0 1)))
      (expect 1 :to-equal (nshell.domain.history:entry-exit-code entry))))

  (it "history-raw-constructors-are-internal-boundaries"
    (let ((entry (nshell.domain.history:make-history-entry "echo ok" 0 0))
          (history (nshell.domain.history:make-command-history :max-entries 7)))
      (expect "echo ok" :to-equal (nshell.domain.history:entry-text entry))
      (expect 7 :to-equal (nshell.domain.history:history-capacity history))
      (expect (history-domain-external-symbol-p "MAKE-HISTORY-ENTRY") :to-be-truthy)
      (expect (history-domain-external-symbol-p "ENTRY-TEXT") :to-be-truthy)
      (expect (history-domain-external-symbol-p "ENTRY-TIMESTAMP") :to-be-truthy)
      (expect (history-domain-external-symbol-p "ENTRY-EXIT-CODE") :to-be-truthy)
      (expect (history-domain-external-symbol-p "HISTORY-ENTRY-TEXTS") :to-be-truthy)
      (expect (history-domain-external-symbol-p "HISTORY-ENTRY-P") :to-be-falsy)
      (expect (history-domain-external-symbol-p "HISTORY-ENTRY-TEXT") :to-be-falsy)
      (expect (history-domain-external-symbol-p "HISTORY-ENTRY-TIMESTAMP") :to-be-falsy)
      (expect (history-domain-external-symbol-p "HISTORY-ENTRY-EXIT-CODE") :to-be-falsy)
      (expect :internal :to-be (nth-value 1 (find-symbol "COMMAND-HISTORY-ENTRIES"
                                                   "NSHELL.DOMAIN.HISTORY")))
      (expect :internal :to-be (nth-value 1 (find-symbol "COMMAND-HISTORY-MAX-ENTRIES"
                                                   "NSHELL.DOMAIN.HISTORY")))
      (expect (fboundp 'nshell.domain.history::history-entry-p) :to-be-falsy)
      (expect (fboundp 'nshell.domain.history::copy-history-entry) :to-be-falsy)
      (expect (fboundp 'nshell.domain.history::copy-command-history) :to-be-falsy)
      (expect (fboundp 'nshell.domain.history::copy-history-word) :to-be-falsy)
      (expect (fboundp 'nshell.domain.history::%make-history-entry-with-invariants) :to-be-truthy)
      (expect (fboundp 'nshell.domain.history::%allocate-history-entry) :to-be-truthy)
      (expect (fboundp 'nshell.domain.history::%make-command-history) :to-be-truthy)
      (expect (fboundp 'nshell.domain.history::%allocate-command-history) :to-be-truthy)))

  (it "command-history-construction-validates-capacity"
    (expect (lambda () (nshell.domain.history:make-command-history :max-entries -1)) :to-throw 'type-error)
    (expect (lambda () (nshell.domain.history:make-command-history :max-entries "many")) :to-throw 'type-error)))
