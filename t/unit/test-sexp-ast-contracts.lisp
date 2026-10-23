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
              (nshell.domain.parsing::%redirect-entry-target legacy-entry)))))
