(in-package #:nshell/test)

(describe "parser-tests"
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

  (it "redirect-kind-facts-project-classification"
    "Redirect kind facts should own input/output/stderr/append classification."
    (let ((input-facts (nshell.domain.parsing::%redirect-kind-facts :<))
          (input-spec (nshell.domain.parsing::%redirect-kind-fact-spec :<))
          (tabbed-input-facts (nshell.domain.parsing::%redirect-kind-facts :<<-))
          (tabbed-input-spec (nshell.domain.parsing::%redirect-kind-fact-spec :<<-))
          (stderr-append-facts (nshell.domain.parsing::%redirect-kind-facts :2>>))
          (all-output-append-facts (nshell.domain.parsing::%redirect-kind-facts :&>>)))
      (expect (every #'nshell.domain.parsing::%redirect-kind-fact-spec-p
                 nshell.domain.parsing::+redirect-kind-fact-specs+) :to-be-truthy)
      (expect (notany #'listp
                  nshell.domain.parsing::+redirect-kind-fact-specs+) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-fact-spec-p input-spec) :to-be-truthy)
      (expect :< :to-be (nshell.domain.parsing::%redirect-kind-fact-spec-kind
               input-spec))
      (expect (nshell.domain.parsing::%redirect-kind-fact-spec-input-p input-spec) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-p input-facts) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-input-p input-facts) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-output-p input-facts) :to-be-falsy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-stderr-p input-facts) :to-be-falsy)
      (expect (nshell.domain.parsing::%redirect-kind-fact-spec-p tabbed-input-spec) :to-be-truthy)
      (expect :<<- :to-be (nshell.domain.parsing::%redirect-kind-fact-spec-kind
                    tabbed-input-spec))
      (expect (nshell.domain.parsing::%redirect-kind-fact-spec-input-p
               tabbed-input-spec) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-p tabbed-input-facts) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-input-p
               tabbed-input-facts) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-output-p
               tabbed-input-facts) :to-be-falsy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-stderr-p
               tabbed-input-facts) :to-be-falsy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-stderr-p
           stderr-append-facts) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-append-p
           stderr-append-facts) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-output-p
           all-output-append-facts) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-stderr-p
           all-output-append-facts) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-append-p
           all-output-append-facts) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-fact-spec nil) :to-be-null)
      (expect (nshell.domain.parsing::%redirect-kind-fact-spec :unknown) :to-be-null)
      (expect (nshell.domain.parsing::%redirect-kind-facts nil) :to-be-null)
      (expect (nshell.domain.parsing::%redirect-kind-facts :unknown) :to-be-null)))

  (it "redirect-kind-facts-project-tabbed-here-document"
    "The tab-stripping here-document operator is classified as input-only."
    (let ((facts (nshell.domain.parsing::%redirect-kind-facts :<<-))
          (spec (nshell.domain.parsing::%redirect-kind-fact-spec :<<-)))
      (expect (nshell.domain.parsing::%redirect-kind-facts-p facts) :to-be-truthy)
      (expect :<<- :to-be (nshell.domain.parsing::%redirect-kind-facts-kind facts))
      (expect (nshell.domain.parsing::%redirect-kind-facts-input-p facts) :to-be-truthy)
      (expect (nshell.domain.parsing::%redirect-kind-facts-output-p facts) :to-be-falsy)
      (expect (nshell.domain.parsing::%redirect-kind-fact-spec-p spec) :to-be-truthy)
      (expect :<<- :to-be (nshell.domain.parsing::%redirect-kind-fact-spec-kind spec))
      (expect (nshell.domain.parsing::%redirect-kind-fact-spec-input-p spec) :to-be-truthy)))

  (it "redirect-execution-classification-projects-effective-specs"
    "Execution redirect classification belongs to parser-domain data."
    (let ((redirects '((:< . "in.txt")
                       (:> . "out.txt")
                       (:>> . "append.txt")
                       (:2>&1 . nil))))
      (expect (nshell.domain.parsing:redirect-input-kind-p :<) :to-be-truthy)
      (expect (nshell.domain.parsing:redirect-output-kind-p :&>) :to-be-truthy)
      (expect (nshell.domain.parsing:redirect-stderr-kind-p :2>&1) :to-be-truthy)
      (expect (nshell.domain.parsing:redirect-append-kind-p :>>) :to-be-truthy)
      (expect (nshell.domain.parsing:redirect-append-kind-p :2>>) :to-be-truthy)
      (expect (nshell.domain.parsing:redirect-output-kind-p :&>>) :to-be-truthy)
      (expect (nshell.domain.parsing:redirect-stderr-kind-p :&>>) :to-be-truthy)
      (expect (nshell.domain.parsing:redirect-input-kind-p nil) :to-be-falsy)
      (expect (nshell.domain.parsing:redirect-output-kind-p :unknown) :to-be-falsy)
      (expect (nshell.domain.parsing:redirect-stderr-kind-p :unknown) :to-be-falsy)
      (expect (nshell.domain.parsing:redirect-append-kind-p :unknown) :to-be-falsy)
      (multiple-value-bind (kind target)
          (nshell.domain.parsing:redirect-input-spec redirects)
        (expect :< :to-be kind)
        (expect "in.txt" :to-equal target))
      (expect "in.txt" :to-equal (nshell.domain.parsing:redirect-input-file-target redirects))
      (multiple-value-bind (target mode)
          (nshell.domain.parsing:redirect-output-spec redirects)
        (expect "append.txt" :to-equal target)
        (expect :append :to-be mode))
      (multiple-value-bind (kind target mode)
          (nshell.domain.parsing:redirect-stderr-spec redirects)
        (expect :merge :to-be kind)
        (expect target :to-be-null)
        (expect mode :to-be-null))
      (expect (nshell.domain.parsing:redirect-output-p redirects) :to-be-truthy)))

  (it "redirect-output-destinations-preserve-left-to-right-effects"
    "Domain output destination resolution owns shell-significant redirect order."
    (let ((destinations
            (nshell.domain.parsing:redirect-output-destinations
             '((:2> . "early.err")
               (:> . "out.txt")
               (:2>&1 . nil)
               (:>> . "later.out")))))
      (expect (nshell.domain.parsing:redirect-output-destinations-p destinations) :to-be-truthy)
      (expect "later.out" :to-equal (nshell.domain.parsing:redirect-output-destinations-stdout-target
                    destinations))
      (expect :append :to-be (nshell.domain.parsing:redirect-output-destinations-stdout-mode
               destinations))
      (expect "out.txt" :to-equal (nshell.domain.parsing:redirect-output-destinations-stderr-target
                    destinations))
      (expect :supersede :to-be (nshell.domain.parsing:redirect-output-destinations-stderr-mode
               destinations)))
    (let ((destinations
            (nshell.domain.parsing:redirect-output-destinations
             '((:&>> . "all.log")))))
      (expect (nshell.domain.parsing:redirect-output-destinations-p destinations) :to-be-truthy)
      (expect "all.log" :to-equal (nshell.domain.parsing:redirect-output-destinations-stdout-target
                    destinations))
      (expect :append :to-be (nshell.domain.parsing:redirect-output-destinations-stdout-mode
               destinations))
      (expect "all.log" :to-equal (nshell.domain.parsing:redirect-output-destinations-stderr-target
                    destinations))
      (expect :append :to-be (nshell.domain.parsing:redirect-output-destinations-stderr-mode
               destinations)))
    (let* ((state (nshell.domain.parsing::%empty-redirect-output-destination-state))
           (stdout-state
             (nshell.domain.parsing::%redirect-output-destination-state-apply-entry
              state :> "out.txt"))
           (merged-state
             (nshell.domain.parsing::%redirect-output-destination-state-apply-entry
              stdout-state :2>&1 nil))
           (changed-stdout-state
             (nshell.domain.parsing::%redirect-output-destination-state-apply-entry
              merged-state :>> "later.out")))
      (expect "later.out" :to-equal (nshell.domain.parsing::%redirect-output-destination-state-stdout-target
                    changed-stdout-state))
      (expect :append :to-be (nshell.domain.parsing::%redirect-output-destination-state-stdout-mode
               changed-stdout-state))
      (expect "out.txt" :to-equal (nshell.domain.parsing::%redirect-output-destination-state-stderr-target
                    changed-stdout-state))
      (expect :supersede :to-be (nshell.domain.parsing::%redirect-output-destination-state-stderr-mode
               changed-stdout-state))))

  (it "redirect-dynamic-fd-dup-projects-target-and-folds-left-to-right"
    "Dynamic fd duplication should preserve source/target data and shell redirect order."
    (let* ((command
             (nshell.domain.parsing:make-command-node
              "echo"
              '("1>&2")))
           (result
             (nshell.domain.parsing:split-command-node-redirects command))
           (redirects
             (nshell.domain.parsing:command-redirect-split-result-redirects
              result))
           (target (cdar redirects)))
      (expect 1 :to-be
              (nshell.domain.parsing:redirect-fd-dup-target-source target))
      (expect 2 :to-be
              (nshell.domain.parsing:redirect-fd-dup-target-target target))
      (let ((destinations
              (nshell.domain.parsing:redirect-output-destinations redirects)))
        (expect (nshell.domain.parsing:redirect-output-destinations-stdout-target
                 destinations)
                :to-be-null)
        (expect :stderr :to-be
                (nshell.domain.parsing:redirect-output-destinations-stdout-endpoint
                 destinations))
        (expect :stderr :to-be
                (nshell.domain.parsing:redirect-output-destinations-stderr-endpoint
                 destinations))))
    (let ((destinations
            (nshell.domain.parsing:redirect-output-destinations
             (list (cons :>
                         "out.txt")
                   (cons :fd-dup
                         (nshell.domain.parsing:make-redirect-fd-dup-target
                          1
                          2))))))
      (expect (nshell.domain.parsing:redirect-output-destinations-stdout-target
               destinations)
              :to-be-null)
      (expect :stderr :to-be
              (nshell.domain.parsing:redirect-output-destinations-stdout-endpoint
               destinations))))

  (it "redirect-dynamic-fd-dup-requires-shell-wrapper"
    "Descriptor duplication outside stdout/stderr aliases is preserved for a child wrapper."
    (let ((redirects
            (list
             (cons :fd-dup
                   (nshell.domain.parsing:make-redirect-fd-dup-target
                    3
                    1)))))
      (expect (nshell.domain.parsing:redirects-require-shell-wrapper-p redirects)
              :to-be-truthy)
      (let ((destinations
              (nshell.domain.parsing:redirect-output-destinations redirects)))
        (expect :stdout
                :to-be
                (nshell.domain.parsing:redirect-output-destinations-stdout-endpoint
                 destinations))
        (expect :stderr
                :to-be
                 (nshell.domain.parsing:redirect-output-destinations-stderr-endpoint
                 destinations)))))

  (it "redirect-dynamic-fd-dup-preserves-input-and-close"
    "Dynamic fd duplication preserves input direction and explicit closes."
    (let* ((command
             (nshell.domain.parsing:make-command-node
              "cat"
              '("3<&0" "4>&-")))
           (result
             (nshell.domain.parsing:split-command-node-redirects command))
           (redirects
             (nshell.domain.parsing:command-redirect-split-result-redirects
              result))
           (input-target (cdr (first redirects)))
           (close-target (cdr (second redirects)))
           (script (nshell.domain.parsing:shell-redirect-script redirects)))
      (expect 2 :to-be (length redirects))
      (expect :input :to-be
              (nshell.domain.parsing:redirect-fd-dup-target-operator input-target))
      (expect 3 :to-be
              (nshell.domain.parsing:redirect-fd-dup-target-source input-target))
      (expect 0 :to-be
              (nshell.domain.parsing:redirect-fd-dup-target-target input-target))
      (expect :close :to-be
              (nshell.domain.parsing:redirect-fd-dup-target-target close-target))
      (expect (not (null
                    (nshell.domain.parsing:redirects-require-shell-wrapper-p redirects)))
              :to-be-truthy)
      (expect (not (null (search "3<&0" script))) :to-be-truthy)
      (expect (not (null (search "4>&-" script))) :to-be-truthy)))

  (it "shell-redirect-script-lowers-here-string-portably"
    "A child wrapper uses a POSIX here-document instead of a non-POSIX here-string."
    (let ((script
            (nshell.domain.parsing:shell-redirect-script
             (list (cons :<<< "hello")))))
      (expect (search "<<<" script) :to-be-falsy)
      (expect (search "<<'NSHELL_HEREDOC_0'" script) :to-be-truthy)
      (expect (search "hello" script) :to-be-truthy)))

  (it "redirect-output-destination-state-folds-raw-entries"
    "Destination resolution folds raw redirect entries through an explicit state boundary."
    (let ((state
            (nshell.domain.parsing::%redirect-output-destination-state-from-redirects
             '((:> . "stdout.txt")
               (:2> . "stderr.txt")
               (:2>&1 . nil)
               (:>> . "append.txt")))))
      (expect "append.txt" :to-equal (nshell.domain.parsing::%redirect-output-destination-state-stdout-target
                    state))
      (expect :append :to-be (nshell.domain.parsing::%redirect-output-destination-state-stdout-mode
               state))
      (expect "stdout.txt" :to-equal (nshell.domain.parsing::%redirect-output-destination-state-stderr-target
                    state))
      (expect :supersede :to-be (nshell.domain.parsing::%redirect-output-destination-state-stderr-mode
               state))))

  (it "map-redirect-entries-projects-kind-and-target"
    "Redirect entry mapping should project kind and target without exposing raw cons cells."
    (let ((entries '()))
      (flet ((collect (kind target)
               (push (cons kind target) entries)))
        (nshell.domain.parsing:map-redirect-entries
         #'collect
         '((:> . "out.txt")
           (:2>&1 . nil)
           (:>> . "append.txt"))))
      (setf entries (nreverse entries))
      (expect '((:> . "out.txt")
                   (:2>&1 . nil)
                   (:>> . "append.txt")) :to-equal entries)))

  (it "split-command-node-redirects-preserves-here-doc-order"
    "Split command-node redirects preserve the original left-to-right redirect order."
    (let* ((command
             (nshell.domain.parsing:make-command-node
              "echo"
              '("hello" "<<" "EOF" "<<-" "TAB" "2>&1")))
           (result
             (nshell.domain.parsing:split-command-node-redirects command))
           (redirects
             (nshell.domain.parsing:command-redirect-split-result-redirects
              result)))
      (expect '("hello") :to-equal (nshell.domain.parsing:command-node-arg-values
                  (nshell.domain.parsing:command-redirect-split-result-clean-command
                   result)))
      (expect '((:<< . "EOF")
                   (:<<- . "TAB")
                   (:2>&1 . nil)) :to-equal redirects)))

  (it "split-command-node-redirects-preserves-left-to-right-order"
    "Split command-node redirects preserve the original left-to-right redirect order."
    (let* ((command
             (nshell.domain.parsing:make-command-node
              "echo"
              '("hello" ">" "out.txt" "2>&1")))
           (result
             (nshell.domain.parsing:split-command-node-redirects command))
           (redirects
             (nshell.domain.parsing:command-redirect-split-result-redirects
              result)))
      (expect '("hello") :to-equal (nshell.domain.parsing:command-node-arg-values
                  (nshell.domain.parsing:command-redirect-split-result-clean-command
                   result)))
      (expect '((:> . "out.txt")
                   (:2>&1 . nil)) :to-equal redirects)))

  (it "split-command-node-redirects-consumes-tabbed-here-document"
    "Split command-node redirect handling recognizes the tab-stripping here-document operator."
    (let* ((command
             (nshell.domain.parsing:make-command-node
              "cat"
              '("<<-" "EOF")))
           (result
             (nshell.domain.parsing:split-command-node-redirects command))
           (redirects
             (nshell.domain.parsing:command-redirect-split-result-redirects
              result)))
      (let ((clean-command
              (nshell.domain.parsing:command-redirect-split-result-clean-command
               result)))
        (expect "cat" :to-equal
                (nshell.domain.parsing:command-node-command clean-command))
        (expect nil :to-equal
                (nshell.domain.parsing:command-node-arg-values clean-command)))
      (expect '((:<<- . "EOF")) :to-equal redirects)))

  (it "command-redirect-split-state-consumes-targeted-redirects"
    "Command redirect split state should consume redirect-target pairs from staged arguments."
    (let ((state
            (nshell.domain.parsing::%empty-command-redirect-split-state)))
      (setf state
            (nshell.domain.parsing::%command-redirect-split-state-push-clean
             state
             "hello"))
      (setf state
            (nshell.domain.parsing::%command-redirect-split-state-push-redirect
             state
             :>
             "out.txt"))
      (setf state
            (nshell.domain.parsing::%command-redirect-split-state-push-redirect
             state
             :2>&1
             nil))
      (expect (nshell.domain.parsing::%command-redirect-split-state-p state) :to-be-truthy)
      (expect '("hello") :to-equal (nshell.domain.parsing::%command-redirect-split-state-clean
                  state))
      (expect '((:2>&1 . nil) (:> . "out.txt")) :to-equal (nshell.domain.parsing::%command-redirect-split-state-redirects
                  state))))

  (it "command-list-redirect-split-state-preserves-stage-order"
    "Command list redirect split state preserves command and separator order."
    (let* ((commands
             (list (nshell.domain.parsing:make-command-node
                    "echo"
                    '("hello"))
                   (nshell.domain.parsing:make-command-node
                    "cat"
                    '(">" "out.txt"))))
           (result
             (nshell.domain.parsing:split-command-nodes-redirects commands)))
      (expect (nshell.domain.parsing:command-list-redirect-split-result-p result) :to-be-truthy)
      (expect '("hello") :to-equal (nshell.domain.parsing:command-node-arg-values
                  (first (nshell.domain.parsing:command-list-redirect-split-result-clean-commands
                          result))))
      (expect '(nil ((:> . "out.txt"))) :to-equal (nshell.domain.parsing:command-list-redirect-split-result-redirects
                  result))))

  (it "split-command-node-redirects-projects-redirect-table-cases"
    "Split command-node redirect table should expose all handled redirect cases."
    (expect (fboundp 'nshell.domain.parsing:split-command-node-redirects) :to-be-truthy)
    (expect (fboundp 'nshell.domain.parsing:command-redirect-split-result-clean-command) :to-be-truthy)
    (expect (fboundp 'nshell.domain.parsing:command-redirect-split-result-redirects) :to-be-truthy))

  (it "split-command-node-redirects-consumes-redirect-facts-boundary"
    "Split command-node redirect handling should consume redirect facts explicitly."
    (let ((state (nshell.domain.parsing::%empty-command-redirect-split-state)))
      (expect (nshell.domain.parsing::%command-redirect-split-state-p state) :to-be-truthy)
      (expect (nshell.domain.parsing::%command-redirect-split-state-redirects
                 state) :to-be-null)))

  (it "separator-rule-entry-projects-separator-facts"
    "Separator rule entries should expose rule facts and token types explicitly."
    (let ((entry (nshell.domain.parsing::%separator-rule-entry :pipe)))
      (expect (nshell.domain.parsing::%separator-rule-entry-p entry) :to-be-truthy)
      (expect :pipe :to-be (nshell.domain.parsing::%separator-rule-entry-token-type entry))
      (expect "|" :to-equal (nshell.domain.parsing::%separator-rule-entry-text entry))
      (expect (nshell.domain.parsing::%separator-rule-entry-continues-p entry) :to-be-truthy)))

  (it "separator-rule-entry-projects-token-type-lookup"
    "Separator token type lookup should remain a data boundary."
    (expect :pipe :to-be (nshell.domain.parsing::%separator-from-token-type :pipe))
    (expect :and :to-be (nshell.domain.parsing::%separator-from-token-type :and))
    (expect (nshell.domain.parsing::%separator-from-token-type :unknown) :to-be-null))

  (it "separator-facts-preserve-unknown-separator-fallback"
    "Unknown separators should not be projected into continuation facts."
    (let ((facts (nshell.domain.parsing::%separator-facts :unknown)))
      (expect (nshell.domain.parsing::%separator-facts-p facts) :to-be-truthy)
      (expect :unknown :to-be (nshell.domain.parsing::%separator-facts-kind facts))
      (expect (nshell.domain.parsing::%separator-facts-token-type facts) :to-be-null)
      (expect "unknown" :to-equal (nshell.domain.parsing::%separator-facts-text facts))
      (expect (nshell.domain.parsing::%separator-facts-continues-p facts) :to-be-null)
      (expect (nshell.domain.parsing::%separator-text nil) :to-be-null)
      (expect (nshell.domain.parsing::%separator-facts nil) :to-be-null)))

  (it "redirect-specs-cover-non-file-and-empty-inputs"
    "Redirect projections preserve here-document kinds and empty-state semantics."
    (multiple-value-bind (kind target)
        (nshell.domain.parsing:redirect-input-spec '((:<< . "EOF")))
      (expect :<< :to-be kind)
      (expect "EOF" :to-equal target))
    (expect (nshell.domain.parsing:redirect-input-file-target '((:<< . "EOF")))
            :to-be-null)
    (multiple-value-bind (target mode)
        (nshell.domain.parsing:redirect-output-spec nil)
      (expect target :to-be-null)
      (expect mode :to-be-null))
    (multiple-value-bind (kind target mode)
        (nshell.domain.parsing:redirect-stderr-spec '((:2>> . "errors.log")))
      (expect :file :to-be kind)
      (expect "errors.log" :to-equal target)
      (expect :append :to-be mode))
    (multiple-value-bind (kind target mode)
        (nshell.domain.parsing:redirect-stderr-spec nil)
      (expect kind :to-be-null)
      (expect target :to-be-null)
      (expect mode :to-be-null)))

  (it "shell-redirect-script-renders-file-and-merge-forms"
    "Shell-wrapper lowering covers every direct file and stderr merge operator."
    (let ((script
            (nshell.domain.parsing:shell-redirect-script
             (list (cons :< "in.txt")
                   (cons :> "out.txt")
                   (cons :>> "append.txt")
                   (cons :2> "err.txt")
                   (cons :2>> "err-append.txt")
                   (cons :&> "all.txt")
                   (cons :&>> "all-append.txt")
                   (cons :2>&1 nil)))))
      (expect (search "<'in.txt'" script) :to-be-truthy)
      (expect (search ">'out.txt'" script) :to-be-truthy)
      (expect (search ">>'append.txt'" script) :to-be-truthy)
      (expect (search "2>'err.txt'" script) :to-be-truthy)
      (expect (search "2>>'err-append.txt'" script) :to-be-truthy)
      (expect (search ">'all.txt' 2>&1" script) :to-be-truthy)
      (expect (search ">>'all-append.txt' 2>&1" script) :to-be-truthy)
      (expect (search " 2>&1" script) :to-be-truthy)))

  (it "shell-redirect-script-quotes-and-avoids-heredoc-collisions"
    "Shell-wrapper lowering quotes file names and chooses collision-free delimiters."
    (let ((script
            (nshell.domain.parsing:shell-redirect-script
             (list (cons :< "a'b")
                   (cons :<< "NSHELL_HEREDOC_0")
                   (cons :<<< "NSHELL_HEREDOC_1")
                   (cons :<<- "TAB")))))
      (expect (search "'a'\\''b'" script) :to-be-truthy)
      (expect (search "<<'NSHELL_HEREDOC_1'" script) :to-be-truthy)
      (expect (search "<<'NSHELL_HEREDOC_2'" script) :to-be-truthy)
      (expect (search "<<-'NSHELL_HEREDOC_2'" script) :to-be-truthy)))

  (it "shell-redirect-script-rejects-unknown-kinds"
    "Unsupported redirect kinds fail at the shell-wrapper boundary."
    (expect (lambda ()
              (nshell.domain.parsing:shell-redirect-script
               (list (cons :unknown "target"))))
            :to-throw 'error)))
