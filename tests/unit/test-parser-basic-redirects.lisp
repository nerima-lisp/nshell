(in-package #:nshell/test)

(in-suite parser-tests)

(test parse-fd-redirects-tokenize-and-need-no-spurious-target
  "fd-prefixed and combined redirects parse cleanly; 2>&1 needs no file target."
  (is (nshell.domain.parsing::%redirect-targetless-p "2>&1"))
  (with-complete-command-line (result ast "cat x 2>err.txt")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (string= "cat" (nshell.domain.parsing:command-node-command ast))))
  (with-complete-command-line (result ast "cat x 2>&1")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (string= "cat" (nshell.domain.parsing:command-node-command ast)))
    (is (equal '("x" "2>&1")
               (nshell.domain.parsing:command-node-arg-values ast))))
  (with-complete-command-line (result ast "make &>build.log")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (string= "make" (nshell.domain.parsing:command-node-command ast)))))

(test parser-data-query-functions-handle-boundary-values
  "Parser data lookups should reject absent domain values without type errors."
  (let ((redirect-facts (nshell.domain.parsing::%redirect-facts "2>&1"))
        (pipe-facts (nshell.domain.parsing::%separator-facts :pipe)))
    (is (null (nshell.domain.parsing::%redirect-facts nil)))
    (is (null (nshell.domain.parsing::%redirect-target-policy nil)))
    (is (nshell.domain.parsing::%redirect-facts-p redirect-facts))
    (is (string= "2>&1"
                 (nshell.domain.parsing::%redirect-facts-text
                  redirect-facts)))
    (is (eq :2>&1
            (nshell.domain.parsing::%redirect-facts-kind
             redirect-facts)))
    (is (nshell.domain.parsing::%redirect-facts-fd-dup-p redirect-facts))
    (is (null (nshell.domain.parsing::%redirect-facts "not-a-redirect")))
    (is (null (nshell.domain.parsing::%separator-from-token-type :unknown)))
    (is (nshell.domain.parsing::%separator-facts-p pipe-facts))
    (is (eq :pipe
            (nshell.domain.parsing::%separator-facts-token-type pipe-facts)))
    (is (string= "|"
                 (nshell.domain.parsing::%separator-facts-text pipe-facts)))
    (is (nshell.domain.parsing::%separator-facts-continues-p pipe-facts))
    (is (not (nshell.domain.parsing::%continuation-separator-p nil)))
    (is (null (nshell.domain.parsing::%separator-facts nil)))
    (is (null (nshell.domain.parsing::%separator-text nil)))))

(test redirect-spec-entry-projects-table-shape
  "Redirect spec entries isolate raw table shape from parser data queries."
  (let ((entry (nshell.domain.parsing::%redirect-spec-entry "2>&1")))
    (is (every #'nshell.domain.parsing::%redirect-spec-entry-p
               nshell.domain.parsing::+redirect-specs+))
    (is (nshell.domain.parsing::%redirect-spec-entry-p entry))
    (is (string= "2>&1"
                 (nshell.domain.parsing::%redirect-spec-entry-text entry)))
    (is (eq :2>&1
            (nshell.domain.parsing::%redirect-spec-entry-kind entry)))
    (is (null (nshell.domain.parsing::%redirect-spec-entry nil)))
    (is (null (nshell.domain.parsing::%redirect-spec-entry
               "not-a-redirect")))))

(test redirect-entry-projects-runtime-redirect-shape
  "Runtime redirect entries isolate cons shape from redirect classification."
  (let ((entry (nshell.domain.parsing::%redirect-entry-from-raw
                '(:>> . "out.txt"))))
    (is (nshell.domain.parsing::%redirect-entry-p entry))
    (is (eq :>> (nshell.domain.parsing::%redirect-entry-kind entry)))
    (is (string= "out.txt"
                 (nshell.domain.parsing::%redirect-entry-target entry)))
    (is (null (nshell.domain.parsing::%redirect-entry-from-raw nil)))))

(test redirect-entries-project-runtime-redirect-list
  "Runtime redirect entry normalization is a collection boundary."
  (let ((entries (nshell.domain.parsing::%redirect-entries-from-raw
                  '((:> . "out.txt")
                    nil
                    (:2>&1)))))
    (is (every #'nshell.domain.parsing::%redirect-entry-p entries))
    (is (equal '(:> :2>&1)
               (mapcar #'nshell.domain.parsing::%redirect-entry-kind
                       entries)))
    (is (equal '("out.txt" nil)
               (mapcar #'nshell.domain.parsing::%redirect-entry-target
                       entries)))))

(test redirect-target-policy-projects-target-requirement
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
    (is (nshell.domain.parsing::%redirect-target-policy-p fd-dup-policy))
    (is (eq :2>&1
            (nshell.domain.parsing::%redirect-target-policy-kind
             fd-dup-policy)))
    (is (not (nshell.domain.parsing::%redirect-target-policy-target-required-p
              fd-dup-policy)))
    (is (nshell.domain.parsing::%redirect-target-policy-target-required-p
         output-policy))
    (is (nshell.domain.parsing::%redirect-target-policy-target-required-p
         stderr-policy))
    (is (nshell.domain.parsing::%redirect-target-policy-target-required-p
         all-output-policy))
    (is (nshell.domain.parsing::%redirect-target-policy-target-required-p
         all-output-append-policy))
    (is (nshell.domain.parsing::%redirect-target-required-p ">"))
    (is (nshell.domain.parsing::%redirect-target-required-p "2>"))
    (is (nshell.domain.parsing::%redirect-targetless-p "2>&1"))
    (is (not (fboundp
              'nshell.domain.parsing::%redirect-target-policy-from-kind)))
    (is (null (nshell.domain.parsing::%redirect-target-policy nil)))
    (is (null (nshell.domain.parsing::%redirect-target-policy
               "not-a-redirect")))
    (is (null (nshell.domain.parsing::%redirect-target-required-p nil)))
    (is (null (nshell.domain.parsing::%redirect-targetless-p
               "not-a-redirect")))))

(test redirect-kind-facts-project-classification
  "Redirect kind facts should own input/output/stderr/append classification."
  (let ((input-facts (nshell.domain.parsing::%redirect-kind-facts :<))
        (input-spec (nshell.domain.parsing::%redirect-kind-fact-spec :<))
        (stderr-append-facts (nshell.domain.parsing::%redirect-kind-facts :2>>))
        (all-output-append-facts (nshell.domain.parsing::%redirect-kind-facts :&>>)))
    (is (every #'nshell.domain.parsing::%redirect-kind-fact-spec-p
               nshell.domain.parsing::+redirect-kind-fact-specs+))
    (is (notany #'listp
                nshell.domain.parsing::+redirect-kind-fact-specs+))
    (is (nshell.domain.parsing::%redirect-kind-fact-spec-p input-spec))
    (is (eq :<
            (nshell.domain.parsing::%redirect-kind-fact-spec-kind
             input-spec)))
    (is (nshell.domain.parsing::%redirect-kind-fact-spec-input-p input-spec))
    (is (nshell.domain.parsing::%redirect-kind-facts-p input-facts))
    (is (nshell.domain.parsing::%redirect-kind-facts-input-p input-facts))
    (is (not (nshell.domain.parsing::%redirect-kind-facts-output-p input-facts)))
    (is (not (nshell.domain.parsing::%redirect-kind-facts-stderr-p input-facts)))
    (is (nshell.domain.parsing::%redirect-kind-facts-stderr-p
         stderr-append-facts))
    (is (nshell.domain.parsing::%redirect-kind-facts-append-p
         stderr-append-facts))
    (is (nshell.domain.parsing::%redirect-kind-facts-output-p
         all-output-append-facts))
    (is (nshell.domain.parsing::%redirect-kind-facts-stderr-p
         all-output-append-facts))
    (is (nshell.domain.parsing::%redirect-kind-facts-append-p
         all-output-append-facts))
    (is (null (nshell.domain.parsing::%redirect-kind-fact-spec nil)))
    (is (null (nshell.domain.parsing::%redirect-kind-fact-spec :unknown)))
    (is (null (nshell.domain.parsing::%redirect-kind-facts nil)))
    (is (null (nshell.domain.parsing::%redirect-kind-facts :unknown)))))

(test redirect-execution-classification-projects-effective-specs
  "Execution redirect classification belongs to parser-domain data."
  (let ((redirects '((:< . "in.txt")
                     (:> . "out.txt")
                     (:>> . "append.txt")
                     (:2>&1 . nil))))
    (is (nshell.domain.parsing:redirect-input-kind-p :<))
    (is (nshell.domain.parsing:redirect-output-kind-p :&>))
    (is (nshell.domain.parsing:redirect-stderr-kind-p :2>&1))
    (is (nshell.domain.parsing:redirect-append-kind-p :>>))
    (is (nshell.domain.parsing:redirect-append-kind-p :2>>))
    (is (nshell.domain.parsing:redirect-output-kind-p :&>>))
    (is (nshell.domain.parsing:redirect-stderr-kind-p :&>>))
    (is (not (nshell.domain.parsing:redirect-input-kind-p nil)))
    (is (not (nshell.domain.parsing:redirect-output-kind-p :unknown)))
    (is (not (nshell.domain.parsing:redirect-stderr-kind-p :unknown)))
    (is (not (nshell.domain.parsing:redirect-append-kind-p :unknown)))
    (multiple-value-bind (kind target)
        (nshell.domain.parsing:redirect-input-spec redirects)
      (is (eq :< kind))
      (is (string= "in.txt" target)))
    (is (string= "in.txt"
                 (nshell.domain.parsing:redirect-input-file-target redirects)))
    (multiple-value-bind (target mode)
        (nshell.domain.parsing:redirect-output-spec redirects)
      (is (string= "append.txt" target))
      (is (eq :append mode)))
    (multiple-value-bind (kind target mode)
        (nshell.domain.parsing:redirect-stderr-spec redirects)
      (is (eq :merge kind))
      (is (null target))
      (is (null mode)))
    (is (nshell.domain.parsing:redirect-output-p redirects))))

(test redirect-output-destinations-preserve-left-to-right-effects
  "Domain output destination resolution owns shell-significant redirect order."
  (let ((destinations
          (nshell.domain.parsing:redirect-output-destinations
           '((:2> . "early.err")
             (:> . "out.txt")
             (:2>&1 . nil)
             (:>> . "later.out")))))
    (is (nshell.domain.parsing:redirect-output-destinations-p destinations))
    (is (string= "later.out"
                 (nshell.domain.parsing:redirect-output-destinations-stdout-target
                  destinations)))
    (is (eq :append
            (nshell.domain.parsing:redirect-output-destinations-stdout-mode
             destinations)))
    (is (string= "out.txt"
                 (nshell.domain.parsing:redirect-output-destinations-stderr-target
                  destinations)))
    (is (eq :supersede
            (nshell.domain.parsing:redirect-output-destinations-stderr-mode
             destinations))))
  (let ((destinations
          (nshell.domain.parsing:redirect-output-destinations
           '((:&>> . "all.log")))))
    (is (nshell.domain.parsing:redirect-output-destinations-p destinations))
    (is (string= "all.log"
                 (nshell.domain.parsing:redirect-output-destinations-stdout-target
                  destinations)))
    (is (eq :append
            (nshell.domain.parsing:redirect-output-destinations-stdout-mode
             destinations)))
    (is (string= "all.log"
                 (nshell.domain.parsing:redirect-output-destinations-stderr-target
                  destinations)))
    (is (eq :append
            (nshell.domain.parsing:redirect-output-destinations-stderr-mode
             destinations))))
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
    (is (string= "later.out"
                 (nshell.domain.parsing::%redirect-output-destination-state-stdout-target
                  changed-stdout-state)))
    (is (eq :append
            (nshell.domain.parsing::%redirect-output-destination-state-stdout-mode
             changed-stdout-state)))
    (is (string= "out.txt"
                 (nshell.domain.parsing::%redirect-output-destination-state-stderr-target
                  changed-stdout-state)))
    (is (eq :supersede
            (nshell.domain.parsing::%redirect-output-destination-state-stderr-mode
             changed-stdout-state)))))

(test redirect-output-destination-state-folds-raw-entries
  "Destination resolution folds raw redirect entries through an explicit state boundary."
  (let ((state
          (nshell.domain.parsing::%redirect-output-destination-state-from-redirects
           '((:> . "stdout.txt")
             (:2> . "stderr.txt")
             (:2>&1 . nil)
             (:>> . "append.txt")))))
    (is (string= "append.txt"
                 (nshell.domain.parsing::%redirect-output-destination-state-stdout-target
                  state)))
    (is (eq :append
            (nshell.domain.parsing::%redirect-output-destination-state-stdout-mode
             state)))
    (is (string= "stdout.txt"
                 (nshell.domain.parsing::%redirect-output-destination-state-stderr-target
                  state)))
    (is (eq :supersede
            (nshell.domain.parsing::%redirect-output-destination-state-stderr-mode
             state)))))

(test map-redirect-entries-projects-kind-and-target
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
    (is (equal '((:> . "out.txt")
                 (:2>&1 . nil)
                 (:>> . "append.txt"))
               entries))))

(test split-command-node-redirects-preserves-dangling-operator
  "Split command-node redirects preserve dangling operator state explicitly."
  (let* ((command (nshell.domain.parsing:make-command-node "echo" nil))
         (result
           (nshell.domain.parsing:split-command-node-redirects command)))
    (is (nshell.domain.parsing:command-redirect-split-result-p result))
    (is (string= (nshell.domain.parsing:command-node-command command)
                 (nshell.domain.parsing:command-node-command
                  (nshell.domain.parsing:command-redirect-split-result-clean-command
                   result))))
    (is (equal (nshell.domain.parsing:command-node-arg-values command)
               (nshell.domain.parsing:command-node-arg-values
                (nshell.domain.parsing:command-redirect-split-result-clean-command
                 result))))
    (is (null (nshell.domain.parsing:command-redirect-split-result-redirects
               result)))
    ))

(test split-command-node-redirects-preserves-left-to-right-order
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
    (is (equal '("hello")
               (nshell.domain.parsing:command-node-arg-values
                (nshell.domain.parsing:command-redirect-split-result-clean-command
                 result))))
    (is (equal '((:> . "out.txt")
                 (:2>&1 . nil))
               redirects))))

(test command-redirect-split-state-consumes-targeted-redirects
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
    (is (nshell.domain.parsing::%command-redirect-split-state-p state))
    (is (equal '("hello")
               (nshell.domain.parsing::%command-redirect-split-state-clean
                state)))
    (is (equal '((:2>&1 . nil) (:> . "out.txt"))
               (nshell.domain.parsing::%command-redirect-split-state-redirects
                state)))))

(test command-list-redirect-split-state-preserves-stage-order
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
    (is (nshell.domain.parsing:command-list-redirect-split-result-p result))
    (is (equal '("hello")
               (nshell.domain.parsing:command-node-arg-values
                (first (nshell.domain.parsing:command-list-redirect-split-result-clean-commands
                        result)))))
    (is (equal '(nil ((:> . "out.txt")))
               (nshell.domain.parsing:command-list-redirect-split-result-redirects
                result)))))

(test split-command-node-redirects-projects-redirect-table-cases
  "Split command-node redirect table should expose all handled redirect cases."
  (is (fboundp 'nshell.domain.parsing:split-command-node-redirects))
  (is (fboundp 'nshell.domain.parsing:command-redirect-split-result-clean-command))
  (is (fboundp 'nshell.domain.parsing:command-redirect-split-result-redirects)))

(test split-command-node-redirects-consumes-redirect-facts-boundary
  "Split command-node redirect handling should consume redirect facts explicitly."
  (let ((state (nshell.domain.parsing::%empty-command-redirect-split-state)))
    (is (nshell.domain.parsing::%command-redirect-split-state-p state))
    (is (null (nshell.domain.parsing::%command-redirect-split-state-redirects
               state)))))

(test separator-rule-entry-projects-separator-facts
  "Separator rule entries should expose rule facts and token types explicitly."
  (let ((entry (nshell.domain.parsing::%separator-rule-entry :pipe)))
    (is (nshell.domain.parsing::%separator-rule-entry-p entry))
    (is (eq :pipe (nshell.domain.parsing::%separator-rule-entry-token-type entry)))
    (is (string= "|" (nshell.domain.parsing::%separator-rule-entry-text entry)))
    (is (nshell.domain.parsing::%separator-rule-entry-continues-p entry))))

(test separator-rule-entry-projects-token-type-lookup
  "Separator token type lookup should remain a data boundary."
  (is (eq :pipe (nshell.domain.parsing::%separator-from-token-type :pipe)))
  (is (eq :and (nshell.domain.parsing::%separator-from-token-type :and)))
  (is (null (nshell.domain.parsing::%separator-from-token-type :unknown))))

(test separator-facts-preserve-unknown-separator-fallback
  "Unknown separators should not be projected into continuation facts."
  (let ((facts (nshell.domain.parsing::%separator-facts :unknown)))
    (is (nshell.domain.parsing::%separator-facts-p facts))
    (is (eq :unknown (nshell.domain.parsing::%separator-facts-kind facts)))
    (is (null (nshell.domain.parsing::%separator-facts-token-type facts)))
    (is (string= "unknown" (nshell.domain.parsing::%separator-facts-text facts)))
    (is (null (nshell.domain.parsing::%separator-facts-continues-p facts)))
    (is (null (nshell.domain.parsing::%separator-text nil)))
    (is (null (nshell.domain.parsing::%separator-facts nil)))))
