(in-package #:nshell/test)
(describe "shared-sexp-ast-contracts"
  (it "constructs-and-reads-every-shared-ast-value"
    (let* ((fragment
             (nshell.domain.parsing:make-command-fragment
              "wild*" :double '(0 4)))
           (argument
             (nshell.domain.parsing:make-command-arg
              "out.txt" :single t (list fragment) '(2 9) nil))
           (evaluated-argument
             (nshell.domain.parsing:make-evaluated-command-arg
              17 '(3 5) t))
           (fd-target
             (nshell.domain.parsing:make-redirect-fd-target 2))
           (close-target
             (nshell.domain.parsing:make-redirect-fd-close-target))
           (heredoc-target
             (nshell.domain.parsing:make-redirect-heredoc-target
              argument "body
" t nil '(10 15)))
           (procsub-command
             (nshell.domain.parsing:make-command-node "cat" nil '(15 18)))
           (procsub-target
             (nshell.domain.parsing:make-redirect-procsub-target
              :output procsub-command))
           (ast-redirect
             (nshell.domain.parsing:make-ast-redirect-entry
              :output-file 1 argument '(2 9) 0))
           (command
             (nshell.domain.parsing:make-command-node
              "echo" (list argument) '(0 20) :double (list fragment)
              (list ast-redirect) t))
           (edge
             (nshell.domain.parsing:make-pipeline-edge
              :pipe-stderr-to-stdout '(20 23)))
           (pipeline
             (nshell.domain.parsing:make-pipeline-node
              (list command procsub-command) '(0 28) (list edge)))
           (sequence
             (nshell.domain.parsing:make-sequence-node
              (list command pipeline) '(:semi) '(0 28)))
           (pair
             (first (nshell.domain.parsing:sequence-node-command-separators
                     sequence))))
      (expect (nshell.domain.parsing:command-fragment-p fragment) :to-be-truthy)
      (expect "wild*" :to-equal
              (nshell.domain.parsing:command-fragment-value fragment))
      (expect :double :to-equal
              (nshell.domain.parsing:command-fragment-quote-style fragment))
      (expect '(0 4) :to-equal
              (nshell.domain.parsing:command-fragment-escaped-positions fragment))
      (expect (nshell.domain.parsing:command-arg-p argument) :to-be-truthy)
      (expect "out.txt" :to-equal
              (nshell.domain.parsing:command-arg-value argument))
      (expect :single :to-equal
              (nshell.domain.parsing:command-arg-quote-style argument))
      (expect (nshell.domain.parsing:command-arg-here-doc-literal-p argument) :to-be-truthy)
      (expect (list fragment) :to-equal
              (nshell.domain.parsing:command-arg-fragments argument))
      (expect '(2 9) :to-equal
              (nshell.domain.parsing:command-arg-source-span argument))
      (expect nil :to-equal
              (nshell.domain.parsing:command-arg-glob-p argument))
      (expect 17 :to-equal
              (nshell.domain.parsing:evaluated-command-arg-value
               evaluated-argument))
      (expect '(3 5) :to-equal
              (nshell.domain.parsing:evaluated-command-arg-source-span
               evaluated-argument))
      (expect (nshell.domain.parsing:evaluated-command-arg-glob-p
               evaluated-argument) :to-be-truthy)
      (expect 2 :to-equal
              (nshell.domain.parsing:redirect-fd-target-file-descriptor
               fd-target))
      (expect (nshell.domain.parsing:redirect-fd-close-target-p close-target) :to-be-truthy)
      (expect argument :to-equal
              (nshell.domain.parsing:redirect-heredoc-target-delimiter
               heredoc-target))
      (expect "body
" :to-equal
              (nshell.domain.parsing:redirect-heredoc-target-body
               heredoc-target))
      (expect (nshell.domain.parsing:redirect-heredoc-target-expand-p
               heredoc-target) :to-be-truthy)
      (expect nil :to-equal
              (nshell.domain.parsing:redirect-heredoc-target-strip-tabs-p
               heredoc-target))
      (expect '(10 15) :to-equal
              (nshell.domain.parsing:redirect-heredoc-target-body-span
               heredoc-target))
      (expect :output :to-equal
              (nshell.domain.parsing:redirect-procsub-target-direction
               procsub-target))
      (expect procsub-command :to-equal
              (nshell.domain.parsing:redirect-procsub-target-form
               procsub-target))
      (expect (nshell.domain.parsing:ast-redirect-entry-p ast-redirect) :to-be-truthy)
      (expect :output-file :to-equal
              (nshell.domain.parsing:ast-redirect-entry-kind ast-redirect))
      (expect 1 :to-equal
              (nshell.domain.parsing:ast-redirect-entry-file-descriptor
               ast-redirect))
      (expect argument :to-equal
              (nshell.domain.parsing:ast-redirect-entry-target ast-redirect))
      (expect '(2 9) :to-equal
              (nshell.domain.parsing:ast-redirect-entry-source-span ast-redirect))
      (expect 0 :to-equal
              (nshell.domain.parsing:ast-redirect-entry-source-order ast-redirect))
      (expect "echo" :to-equal
              (nshell.domain.parsing:command-node-command command))
      (expect :double :to-equal
              (nshell.domain.parsing:command-node-command-quote-style command))
      (expect (list fragment) :to-equal
              (nshell.domain.parsing:command-node-command-fragments command))
      (expect (list argument) :to-equal
              (nshell.domain.parsing:command-node-args command))
      (expect (list ast-redirect) :to-equal
              (nshell.domain.parsing:command-node-redirects command))
      (expect (nshell.domain.parsing:command-node-force-external-p command) :to-be-truthy)
      (expect (keywordp (nshell.domain.parsing:ast-node-type command)) :to-be-truthy)
      (expect '(0 20) :to-equal
              (nshell.domain.parsing:ast-node-span command))
      (expect '("out.txt") :to-equal
              (nshell.domain.parsing:command-node-arg-values command))
      (expect :pipe-stderr-to-stdout :to-equal
              (nshell.domain.parsing:pipeline-edge-kind edge))
      (expect '(20 23) :to-equal
              (nshell.domain.parsing:pipeline-edge-source-span edge))
      (expect (list command procsub-command) :to-equal
              (nshell.domain.parsing:pipeline-node-commands pipeline))
      (expect (list edge) :to-equal
              (nshell.domain.parsing:pipeline-node-edges pipeline))
      (expect (keywordp (nshell.domain.parsing:ast-node-type pipeline)) :to-be-truthy)
      (expect '(0 28) :to-equal
              (nshell.domain.parsing:ast-node-span pipeline))
      (expect (list command pipeline) :to-equal
              (nshell.domain.parsing:sequence-node-commands sequence))
      (expect '(:semi) :to-equal
              (nshell.domain.parsing:sequence-node-separators sequence))
      (expect (keywordp (nshell.domain.parsing:ast-node-type sequence)) :to-be-truthy)
      (expect '(0 28) :to-equal
              (nshell.domain.parsing:ast-node-span sequence))
      (expect (nshell.domain.parsing:sequence-node-command-separator-p pair) :to-be-truthy)
      (expect command :to-equal
              (nshell.domain.parsing:sequence-node-command-separator-command pair))
      (expect :semi :to-equal
              (nshell.domain.parsing:sequence-node-command-separator-separator
               pair))))
  (it "keeps-the-legacy-redirect-runtime-type-distinct"
    (let ((legacy-entry
            (nshell.domain.parsing::%redirect-entry-from-raw
             (cons :> "legacy.txt"))))
      (expect (nshell.domain.parsing::%redirect-entry-p legacy-entry) :to-be-truthy)
      (expect :> :to-be
              (nshell.domain.parsing::%redirect-entry-kind legacy-entry))
      (expect "legacy.txt" :to-equal
              (nshell.domain.parsing::%redirect-entry-target legacy-entry))))
  (it "stores-unevaluated-command-values-in-order"
      (let* ((static-arg
              (nshell.domain.parsing:make-command-arg
               "release" nil nil nil '(0 7)))
             (numeric-token
              (nshell.domain.parsing:make-command-arg
               "42" nil nil nil '(22 24) nil))
             (comma-form
              (nshell.domain.parsing:make-command-value-form
               :value '(unquote branch) '(8 16)))
             (dollar-form
              (nshell.domain.parsing:make-command-value-form
               :value '(unquote branch) '(17 21)))
             (splice-form
              (nshell.domain.parsing:make-command-value-form
               :splice '(unquote-splicing branches) '(22 31)))
             (quoted-form
              (nshell.domain.parsing:make-command-value-form
               :quoted '(list 1 2) '(32 42)))
             (forms (list static-arg comma-form dollar-form
                          splice-form quoted-form numeric-token))
             (command
              (nshell.domain.parsing:make-command-node
               "deploy" (list static-arg numeric-token) '(0 43)
               nil nil nil nil forms))
             (legacy-command
              (nshell.domain.parsing:make-command-node "legacy" (list static-arg))))
        (expect (nshell.domain.parsing:command-value-form-p comma-form) :to-be-truthy)
        (expect :value :to-equal
                (nshell.domain.parsing:command-value-form-kind comma-form))
        (expect '(unquote branch) :to-equal
                (nshell.domain.parsing:command-value-form-form comma-form))
        (expect '(8 16) :to-equal
                (nshell.domain.parsing:command-value-form-source-span comma-form))
        (expect :value :to-equal
                (nshell.domain.parsing:command-value-form-kind dollar-form))
        (expect :splice :to-equal
                (nshell.domain.parsing:command-value-form-kind splice-form))
        (expect :quoted :to-equal
                (nshell.domain.parsing:command-value-form-kind quoted-form))
        (expect forms :to-equal
                (nshell.domain.parsing:command-node-argument-forms command))
        (expect (list static-arg numeric-token) :to-equal
                (nshell.domain.parsing:command-node-args command))
        (expect '("release" "42") :to-equal
                (nshell.domain.parsing:command-node-arg-values command))
        (expect (list static-arg) :to-equal
                (nshell.domain.parsing:command-node-argument-forms legacy-command))
        (expect (lambda ()
                  (nshell.domain.parsing:make-command-value-form :literal 42))
                :to-throw 'error)
        (expect (lambda ()
                  (nshell.domain.parsing:make-command-node
                   "bad" nil nil nil nil nil nil (list "untyped")))
                :to-throw 'error)
        (expect (lambda ()
                  (nshell.domain.parsing:make-command-node
                   "bad" (list numeric-token) nil nil nil nil nil
                   (list static-arg)))
                :to-throw 'error)))
  (it "validates-process-substitution-and-redirect-contracts"
      (let* ((command
              (nshell.domain.parsing:make-command-node "cat" nil '(0 3)))
             (pipeline
              (nshell.domain.parsing:make-pipeline-node
               (list command (nshell.domain.parsing:make-command-node "wc" nil))))
             (sequence
              (nshell.domain.parsing:make-sequence-node (list command)))
             (argument (nshell.domain.parsing:make-command-arg "path" nil))
             (fd-target (nshell.domain.parsing:make-redirect-fd-target 1))
             (close-target (nshell.domain.parsing:make-redirect-fd-close-target))
             (heredoc-target
              (nshell.domain.parsing:make-redirect-heredoc-target
               argument "body" t nil '(10 15)))
             (strip-heredoc-target
              (nshell.domain.parsing:make-redirect-heredoc-target
               argument "body" nil t '(10 15)))
             (procsub-input
              (nshell.domain.parsing:make-redirect-procsub-target :input command))
             (procsub-output
              (nshell.domain.parsing:make-redirect-procsub-target :output pipeline))
             (entries
              (list
               (nshell.domain.parsing:make-ast-redirect-entry
                :input-file 0 argument nil 0)
               (nshell.domain.parsing:make-ast-redirect-entry
                :output-file 1 argument nil 1)
               (nshell.domain.parsing:make-ast-redirect-entry
                :append-output-file 1 argument nil 2)
               (nshell.domain.parsing:make-ast-redirect-entry
                :force-output-file 1 argument nil 3)
               (nshell.domain.parsing:make-ast-redirect-entry
                :error-file 2 argument nil 4)
               (nshell.domain.parsing:make-ast-redirect-entry
                :append-error-file 2 argument nil 5)
               (nshell.domain.parsing:make-ast-redirect-entry
                :both-output-files nil argument nil 6)
               (nshell.domain.parsing:make-ast-redirect-entry
                :append-both-output-files nil argument nil 7)
               (nshell.domain.parsing:make-ast-redirect-entry
                :duplicate-input-fd 0 fd-target nil 8)
               (nshell.domain.parsing:make-ast-redirect-entry
                :duplicate-output-fd 1 close-target nil 9)
               (nshell.domain.parsing:make-ast-redirect-entry
                :here-document 0 heredoc-target nil 10)
               (nshell.domain.parsing:make-ast-redirect-entry
                :here-document-strip-tabs 0 strip-heredoc-target nil 11)
               (nshell.domain.parsing:make-ast-redirect-entry
                :here-string 0 argument nil 12)
               (nshell.domain.parsing:make-ast-redirect-entry
                :process-substitution-input nil procsub-input nil 13)
               (nshell.domain.parsing:make-ast-redirect-entry
                :process-substitution-output nil procsub-output nil 14)
               (nshell.domain.parsing:make-ast-redirect-entry
                :input-file 0 procsub-input nil 15)
               (nshell.domain.parsing:make-ast-redirect-entry
                :output-file 1 procsub-output nil 16))))
        (expect command :to-equal
                (nshell.domain.parsing:redirect-procsub-target-form procsub-input))
        (expect :input :to-equal
                (nshell.domain.parsing:redirect-procsub-target-direction procsub-input))
        (expect pipeline :to-equal
                (nshell.domain.parsing:redirect-procsub-target-form procsub-output))
        (expect
         '(:input-file :output-file :append-output-file :force-output-file
                       :error-file :append-error-file :both-output-files
                       :append-both-output-files :duplicate-input-fd :duplicate-output-fd
                       :here-document :here-document-strip-tabs :here-string
                       :process-substitution-input :process-substitution-output
                       :input-file :output-file)
         :to-equal
         (mapcar #'nshell.domain.parsing:ast-redirect-entry-kind entries))
        (expect
         '(0 1 1 1 2 2 nil nil 0 1 0 0 0 nil nil 0 1)
         :to-equal
         (mapcar
          #'nshell.domain.parsing:ast-redirect-entry-file-descriptor entries))
        (expect 16 :to-equal
                (nshell.domain.parsing:ast-redirect-entry-source-order (car (last entries))))
        (expect argument :to-equal
                (nshell.domain.parsing:ast-redirect-entry-target (first entries)))
        (expect
         (lambda ()
           (nshell.domain.parsing:make-redirect-procsub-target :input sequence))
         :to-throw 'error)
        (dolist (bad-redirect
                 (list
                  (list :output-file nil argument nil 0)
                  (list :input-file -1 argument nil 0)
                  (list :both-output-files 1 argument nil 0)
                  (list :duplicate-input-fd 0 argument nil 0)
                  (list :here-document 0 argument nil 0)
                  (list :here-document-strip-tabs 0 heredoc-target nil 0)
                  (list :here-document 0 strip-heredoc-target nil 0)
                  (list :here-string 0 fd-target nil 0)
                  (list :process-substitution-input nil procsub-output nil 0)
                  (list :process-substitution-output nil procsub-input nil 0)
                  (list :input-file 0 procsub-output nil 0)
                  (list :output-file 1 procsub-input nil 0)
                  (list :input-file 0 close-target nil 0)
                  (list :input-file 0 argument nil -1)
                  (list :not-a-kind 0 argument nil 0)))
          (expect (lambda ()
                    (apply #'nshell.domain.parsing:make-ast-redirect-entry
                           bad-redirect))
                  :to-throw 'error))))
  (it "validates-ast-source-spans-and-sequence-rules"
      (let* ((command
              (nshell.domain.parsing:make-command-node "echo" nil '(0 4)))
             (pipeline
              (nshell.domain.parsing:make-pipeline-node (list command) '(0 4)))
             (empty
              (nshell.domain.parsing:make-sequence-node nil nil '(0 0)))
             (terminal-semi
              (nshell.domain.parsing:make-sequence-node
               (list command) '(:semi)))
             (between-items
              (nshell.domain.parsing:make-sequence-node
               (list command pipeline) '(:semi)))
             (terminal-background
              (nshell.domain.parsing:make-sequence-node
               (list command pipeline) '(:semi :amp))))
        (expect nil :to-equal
                (nshell.domain.parsing:sequence-node-separators empty))
        (expect nil :to-equal
                (nshell.domain.parsing:sequence-node-separators terminal-semi))
        (expect '(:semi) :to-equal
                (nshell.domain.parsing:sequence-node-separators between-items))
        (expect '(:semi :amp) :to-equal
                (nshell.domain.parsing:sequence-node-separators terminal-background))
        (expect '((:semi) (:amp)) :to-equal
                (mapcar
                 (lambda (pair)
                   (list
                    (nshell.domain.parsing:sequence-node-command-separator-separator
                     pair)))
                 (nshell.domain.parsing:sequence-node-command-separators
                  terminal-background)))
        (dolist (constructor
                 (list
                  (lambda () (nshell.domain.parsing:make-command-node "x" nil '(3 2)))
                  (lambda () (nshell.domain.parsing:make-pipeline-node (list command) '(3 2)))
                  (lambda () (nshell.domain.parsing:make-sequence-node (list command) nil '(3 2)))
                  (lambda () (nshell.domain.parsing::make-if-node nil nil nil '(3 2)))
                  (lambda () (nshell.domain.parsing::make-for-node "x" nil nil '(3 2)))
                  (lambda () (nshell.domain.parsing::make-while-node nil nil '(3 2)))
                  (lambda () (nshell.domain.parsing::make-case-node "x" nil '(3 2)))
                  (lambda () (nshell.domain.parsing::make-begin-end-node nil '(3 2)))
                  (lambda () (nshell.domain.parsing:make-pipeline-edge :pipe '(3 2)))
                  (lambda () (nshell.domain.parsing:make-command-arg "x" nil nil nil '(3 2)))
                  (lambda () (nshell.domain.parsing:make-evaluated-command-arg 1 '(3 2)))
                  (lambda ()
                    (nshell.domain.parsing:make-command-value-form :value 'x '(3 2)))
                  (lambda ()
                    (nshell.domain.parsing:make-redirect-heredoc-target
                     (nshell.domain.parsing:make-command-arg "EOF" nil)
                     "body" t nil '(3 2)))
                  (lambda ()
                    (nshell.domain.parsing:make-ast-redirect-entry
                     :input-file 0
                     (nshell.domain.parsing:make-command-arg "path" nil)
                     nil '(3 2) 0))))
          (expect constructor :to-throw 'error))
        (dolist (bad-sequence
                 (list
                  (lambda ()
                    (nshell.domain.parsing:make-sequence-node (list "not-an-ast-node")))
                  (lambda ()
                    (nshell.domain.parsing:make-sequence-node (list command) '(:pipe)))
                  (lambda ()
                    (nshell.domain.parsing:make-sequence-node
                     (list command pipeline command) '(:and)))
                  (lambda ()
                    (nshell.domain.parsing:make-sequence-node
                     (list command pipeline) '(:semi :and)))
                  (lambda ()
                    (nshell.domain.parsing:make-sequence-node
                     (list command pipeline) '(:and :or)))
                  (lambda ()
                    (nshell.domain.parsing:make-sequence-node
                     (list command pipeline) '(:semi :and :amp)))
                  (lambda ()
                    (nshell.domain.parsing:make-sequence-node nil '(:amp)))))
          (expect bad-sequence :to-throw 'error))))
  (it "constructs-and-reads-control-flow-ast-values"
    (let* ((condition
            (nshell.domain.parsing:make-command-node "test" nil '(0 4)))
           (then-command
            (nshell.domain.parsing:make-command-node "yes" nil '(5 8)))
           (else-command
            (nshell.domain.parsing:make-command-node "no" nil '(9 11)))
           (if-node
            (nshell.domain.parsing::make-if-node
             condition (list then-command) (list else-command) '(0 11)))
           (for-node
            (nshell.domain.parsing::make-for-node
             "item" '("a" "b") (list then-command) '(0 11)))
           (while-node
            (nshell.domain.parsing::make-while-node
             condition (list then-command) '(0 8)))
           (clause
            (nshell.domain.parsing:make-case-clause
             "pattern" (list then-command)))
           (case-node
            (nshell.domain.parsing::make-case-node
             "value" (list clause) '(0 11)))
           (begin-node
            (nshell.domain.parsing::make-begin-end-node
             (list then-command) '(0 8)))
           (argument
            (nshell.domain.parsing:make-command-arg "literal" :single t))
           (plain-string "legacy"))
      (expect (nshell.domain.parsing:if-node-p if-node) :to-be-truthy)
      (expect condition :to-equal (nshell.domain.parsing:if-node-condition if-node))
      (expect (list then-command) :to-equal
              (nshell.domain.parsing:if-node-then-branch if-node))
      (expect (list else-command) :to-equal
              (nshell.domain.parsing:if-node-else-branch if-node))
      (expect '(0 11) :to-equal (nshell.domain.parsing:ast-node-span if-node))
      (expect (nshell.domain.parsing:for-node-p for-node) :to-be-truthy)
      (expect "item" :to-equal (nshell.domain.parsing:for-node-var-name for-node))
      (expect '("a" "b") :to-equal (nshell.domain.parsing:for-node-in-values for-node))
      (expect (list then-command) :to-equal (nshell.domain.parsing:for-node-body for-node))
      (expect '(0 11) :to-equal (nshell.domain.parsing:ast-node-span for-node))
      (expect (nshell.domain.parsing:while-node-p while-node) :to-be-truthy)
      (expect condition :to-equal (nshell.domain.parsing:while-node-condition while-node))
      (expect (list then-command) :to-equal (nshell.domain.parsing:while-node-body while-node))
      (expect '(0 8) :to-equal (nshell.domain.parsing:ast-node-span while-node))
      (expect (nshell.domain.parsing:case-clause-p clause) :to-be-truthy)
      (expect "pattern" :to-equal (nshell.domain.parsing:case-clause-pattern clause))
      (expect (list then-command) :to-equal (nshell.domain.parsing:case-clause-body clause))
      (expect (nshell.domain.parsing:case-node-p case-node) :to-be-truthy)
      (expect "value" :to-equal (nshell.domain.parsing:case-node-value case-node))
      (expect (list clause) :to-equal (nshell.domain.parsing:case-node-clauses case-node))
      (expect '(0 11) :to-equal (nshell.domain.parsing:ast-node-span case-node))
      (expect (nshell.domain.parsing:begin-end-node-p begin-node) :to-be-truthy)
      (expect (list then-command) :to-equal
              (nshell.domain.parsing:begin-end-node-body begin-node))
      (expect '(0 8) :to-equal (nshell.domain.parsing:ast-node-span begin-node))
      (expect "literal" :to-equal (nshell.domain.parsing:arg-value argument))
      (expect :single :to-equal (nshell.domain.parsing:arg-quote-style argument))
      (expect (nshell.domain.parsing:arg-here-doc-literal-p argument) :to-be-truthy)
      (expect "legacy" :to-equal (nshell.domain.parsing:arg-value plain-string))
      (expect nil :to-equal (nshell.domain.parsing:arg-quote-style plain-string))
      (expect nil :to-equal (nshell.domain.parsing:arg-here-doc-literal-p plain-string)))))
(describe "owner-interface-contracts"
  (it "keeps-expansion-eligibility-separate-from-quote-style"
    (let* ((quoted
             (nshell.domain.parsing:make-command-arg "literal" :double))
           (source
             (nshell.domain.parsing:make-command-arg
              "~/src" nil nil nil nil nil t))
           (source-arg
             (nshell.domain.parsing:make-evaluated-command-arg
              "~/src" nil nil t))
           (evaluated-value
             (nshell.domain.parsing:make-evaluated-command-arg "~/src")))
      (expect nil :to-equal
              (nshell.domain.parsing:command-arg-expand-p quoted))
      (expect t :to-equal
              (nshell.domain.parsing:command-arg-expand-p source))
      (expect t :to-equal
              (nshell.domain.parsing:evaluated-command-arg-expand-p source-arg))
      (expect nil :to-equal
              (nshell.domain.parsing:evaluated-command-arg-expand-p
               evaluated-value))))
  (it "returns-no-argv-for-empty-evaluated-command-arguments"
    (expect nil :to-equal
            (nshell.application:command-argv-strings
             (nshell.application:make-shell-context)
             nil))))

(describe "p2-owner-interface-contracts"
  (it "uses concrete behavior for implemented owner interfaces"
    (expect 'nshell.application:command-failed :to-be
            (find-symbol "COMMAND-FAILED" "NSHELL.USER"))
    (expect t :to-be
            (listp
             (nshell.presentation::highlight-line-from-scanner
              "" (nshell.domain.parsing:scan-input "") 0 0)))
    (expect t :to-be
            (handler-case
                (progn
                  (nshell.application:execute-reader-ast-in-context
                   (nshell.application:make-shell-context)
                   (nshell.domain.parsing:scan-input "")
                   (function identity))
                  nil)
              (nshell.application:command-execution-plan-error () t)))))

(describe "p2-owner-contract-types"
  (it "loads the L06 conversion condition"
    (expect t :to-equal
            (not (null
                  (find-class 'nshell.application:value-conversion-error nil))))))
(describe "shared-sexp-environment-assignment-contracts"
  (it "preserves-command-scoped-environment-assignments"
    (let* ((assignment
             (nshell.domain.parsing:make-command-arg
              "FOO=1" nil nil nil '(0 5) nil nil))
           (command
             (nshell.domain.parsing:make-command-node
              "cmd" nil '(0 9) nil nil nil nil nil (list assignment))))
      (expect (list assignment) :to-equal
              (nshell.domain.parsing:command-node-environment-assignments
               command))
      (expect nil :to-equal
              (nshell.domain.parsing:command-node-args command))
      (expect nil :to-equal
              (nshell.domain.parsing:command-arg-expand-p assignment))
      (expect "FOO=1 cmd" :to-equal
              (nshell.domain.parsing:ast-node->command-line command))))
  (it "rejects-non-command-arg-environment-assignments"
    (expect
     (lambda ()
       (nshell.domain.parsing:make-command-node
        "cmd" nil nil nil nil nil nil nil (list "FOO=1")))
     :to-throw (quote error))))
