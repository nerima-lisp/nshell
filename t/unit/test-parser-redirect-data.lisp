(in-package #:nshell/test)

(describe "parser-redirect-data-tests"
+  (it "define-redirect-data-expands-to-data-only-assignments"
    "The redirect catalog macro keeps declarative data separate from lookup logic."
    (let ((expansion
            (macroexpand-1
             '(nshell.domain.parsing::define-redirect-data
                ((:entry "2>&1"))
                (:2>&1)
                ((:kind :2>&1 :input-p nil :output-p t
                        :stderr-p t :append-p nil))))))
      (expect 'progn :to-be (first expansion))
      (expect 3 :to-equal (length (rest expansion)))
      (expect 'setf :to-be (first (second expansion)))
      (expect 'setf :to-be (first (third expansion)))
      (expect 'setf :to-be (first (fourth expansion)))))

  (it "redirect-fd-dup-target-round-trips-domain-fields"
    "The public redirect value object preserves its explicit fields and default operator."
    (let ((explicit
            (nshell.domain.parsing:make-redirect-fd-dup-target 2 1 :input))
          (default
            (nshell.domain.parsing:make-redirect-fd-dup-target 2 :close)))
      (expect (nshell.domain.parsing:redirect-fd-dup-target-p explicit)
              :to-be-truthy)
      (expect 2 :to-be
              (nshell.domain.parsing:redirect-fd-dup-target-source explicit))
      (expect 1 :to-be
              (nshell.domain.parsing:redirect-fd-dup-target-target explicit))
      (expect :input :to-be
              (nshell.domain.parsing:redirect-fd-dup-target-operator explicit))
      (expect (nshell.domain.parsing:redirect-fd-dup-target-p default)
              :to-be-truthy)
      (expect :close :to-be
              (nshell.domain.parsing:redirect-fd-dup-target-target default))
      (expect :output :to-be
              (nshell.domain.parsing:redirect-fd-dup-target-operator default))))

  (it "parse-fd-redirects-tokenize-and-need-no-spurious-target"
    "fd-prefixed and combined redirects parse cleanly; 2>&1 needs no file target."
    (expect (nshell.domain.parsing::%redirect-targetless-p "2>&1") :to-be-truthy)
    (with-complete-command-line (result ast "cat x 2>err.txt")
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (expect "cat" :to-equal (nshell.domain.parsing:command-node-command ast)))
    (with-complete-command-line (result ast "cat x 2>&1")
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (expect "cat" :to-equal (nshell.domain.parsing:command-node-command ast))
      (expect '("x" "2>&1") :to-equal (nshell.domain.parsing:command-node-arg-values ast)))
    (with-complete-command-line (result ast "cat x 0<&1")
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (expect '("x" "0<&1") :to-equal (nshell.domain.parsing:command-node-arg-values ast)))
    (with-complete-command-line (result ast "cat x 0<&-")
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (expect '("x" "0<&-") :to-equal (nshell.domain.parsing:command-node-arg-values ast)))
    (with-complete-command-line (result ast "make &>build.log")
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (expect "make" :to-equal (nshell.domain.parsing:command-node-command ast))))

  (it "parser-data-query-functions-handle-boundary-values"
    "Parser data lookups should reject absent domain values without type errors."
    (let ((redirect-facts (nshell.domain.parsing::%redirect-facts "2>&1"))
          (pipe-facts (nshell.domain.parsing::%separator-facts :pipe)))
      (expect (nshell.domain.parsing::%redirect-facts nil) :to-be-null)
      (expect (nshell.domain.parsing::%redirect-target-policy nil) :to-be-null)
      (expect (nshell.domain.parsing::%redirect-facts-p redirect-facts) :to-be-truthy)
      (expect "2>&1" :to-equal (nshell.domain.parsing::%redirect-facts-text
                    redirect-facts))
      (expect :2>&1 :to-be (nshell.domain.parsing::%redirect-facts-kind
               redirect-facts))
      (expect (nshell.domain.parsing::%redirect-facts-fd-dup-p redirect-facts) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-facts "not-a-redirect") :to-be-null)
      (expect (nshell.domain.parsing::%separator-from-token-type :unknown) :to-be-null)
      (expect (nshell.domain.parsing::%separator-facts-p pipe-facts) :to-be-truthy)
      (expect :pipe :to-be (nshell.domain.parsing::%separator-facts-token-type pipe-facts))
      (expect "|" :to-equal (nshell.domain.parsing::%separator-facts-text pipe-facts))
      (expect (nshell.domain.parsing::%separator-facts-continues-p pipe-facts) :to-be-truthy)
      (expect (nshell.domain.parsing::%continuation-separator-p nil) :to-be-falsy)
      (expect (nshell.domain.parsing::%separator-facts nil) :to-be-null)
      (expect (nshell.domain.parsing::%separator-text nil) :to-be-null)))

  (it "dynamic-fd-dup-parser-rejects-incomplete-or-nonnumeric-targets"
    "Dynamic descriptor duplication accepts digits and close markers only."
    (expect (nshell.domain.parsing::%redirect-dynamic-fd-dup-target nil)
            :to-be-null)
    (expect (nshell.domain.parsing::%redirect-dynamic-fd-dup-target "2>&")
            :to-be-null)
    (expect (nshell.domain.parsing::%redirect-dynamic-fd-dup-target "x>&1")
            :to-be-null)
    (expect (nshell.domain.parsing::%redirect-dynamic-fd-dup-target "2>&x")
            :to-be-null)
    (let ((target (nshell.domain.parsing::%redirect-dynamic-fd-dup-target "2>&-")))
      (expect :close :to-be
              (nshell.domain.parsing:redirect-fd-dup-target-target target))))

  (it "redirect-spec-entry-projects-table-shape"
    "Redirect spec entries isolate raw table shape from parser data queries."
    (let ((entry (nshell.domain.parsing::%redirect-spec-entry "2>&1")))
      (expect (every #'nshell.domain.parsing::%redirect-spec-entry-p
                 nshell.domain.parsing::+redirect-specs+) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-spec-entry-p entry) :to-be-truthy)
      (expect "2>&1" :to-equal (nshell.domain.parsing::%redirect-spec-entry-text entry))
      (expect :2>&1 :to-be (nshell.domain.parsing::%redirect-spec-entry-kind entry))
      (expect (nshell.domain.parsing::%redirect-spec-entry nil) :to-be-null)
      (expect (nshell.domain.parsing::%redirect-spec-entry
                 "not-a-redirect") :to-be-null)))

  (it "redirect-entry-projects-runtime-redirect-shape"
    "Runtime redirect entries isolate cons shape from redirect classification."
    (let ((entry (nshell.domain.parsing::%redirect-entry-from-raw
                  '(:>> . "out.txt"))))
      (expect (nshell.domain.parsing::%redirect-entry-p entry) :to-be-truthy)
      (expect :>> :to-be (nshell.domain.parsing::%redirect-entry-kind entry))
      (expect "out.txt" :to-equal (nshell.domain.parsing::%redirect-entry-target entry))
      (expect (nshell.domain.parsing::%redirect-entry-from-raw nil) :to-be-null)))

  (it "redirect-entries-project-runtime-redirect-list"
    "Runtime redirect entry normalization is a collection boundary."
    (let ((entries (nshell.domain.parsing::%redirect-entries-from-raw
                    '((:> . "out.txt")
                      nil
                      (:2>&1)))))
      (expect (every #'nshell.domain.parsing::%redirect-entry-p entries) :to-be-truthy)
      (expect '(:> :2>&1) :to-equal (mapcar #'nshell.domain.parsing::%redirect-entry-kind
                         entries))
      (expect '("out.txt" nil) :to-equal (mapcar #'nshell.domain.parsing::%redirect-entry-target
                         entries))))

  (it "redirect-target-policy-projects-target-requirement"
    "Redirect target policy owns which redirect specs consume a target."
    (let ((fd-dup-policy
            (nshell.domain.parsing::%redirect-target-policy "2>&1"))
          (output-policy
            (nshell.domain.parsing::%redirect-target-policy ">"))
          (stderr-policy
            (nshell.domain.parsing::%redirect-target-policy "2>"))
          (all-output-policy
            (nshell.domain.parsing::%redirect-target-policy "&>"))
          (all-output-append-policy
            (nshell.domain.parsing::%redirect-target-policy "&>>")))
      (expect (nshell.domain.parsing::%redirect-target-policy-p fd-dup-policy) :to-be-truthy)
      (expect :2>&1 :to-be (nshell.domain.parsing::%redirect-target-policy-kind
               fd-dup-policy))
      (expect (nshell.domain.parsing::%redirect-target-policy-target-required-p
                fd-dup-policy) :to-be-falsy)
      (expect (nshell.domain.parsing::%redirect-target-policy-target-required-p
           output-policy) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-target-policy-target-required-p
           stderr-policy) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-target-policy-target-required-p
           all-output-policy) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-target-policy-target-required-p
           all-output-append-policy) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-target-required-p ">") :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-target-required-p "2>") :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-targetless-p "2>&1") :to-be-truthy)
      (expect (fboundp
                'nshell.domain.parsing::%redirect-target-policy-from-kind) :to-be-falsy)
      (expect (nshell.domain.parsing::%redirect-target-policy nil) :to-be-null)
      (expect (nshell.domain.parsing::%redirect-target-policy
                 "not-a-redirect") :to-be-null)
      (expect (nshell.domain.parsing::%redirect-target-required-p nil) :to-be-null)
      (expect (nshell.domain.parsing::%redirect-targetless-p
                 "not-a-redirect") :to-be-null)))

)
