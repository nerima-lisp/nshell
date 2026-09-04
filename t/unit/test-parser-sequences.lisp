(in-package #:nshell/test)

(describe "parser-sequence-tests"
  (it "parse-mixed-sequence-and-pipeline"
    (with-complete-ast (ast "echo one | cat; echo two")
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 2 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect (nshell.domain.parsing:pipeline-node-p
           (first (nshell.domain.parsing:sequence-node-commands ast))) :to-be-truthy)
      (expect (nshell.domain.parsing:command-node-p
           (second (nshell.domain.parsing:sequence-node-commands ast))) :to-be-truthy)
      (expect '(:semi) :to-equal (nshell.domain.parsing:sequence-node-separators ast))))

  (it "parse-mixed-sequence-keeps-pipeline-groups"
    (with-complete-ast (ast "echo one | cat && echo two | wc")
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 2 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect (every #'nshell.domain.parsing:pipeline-node-p
                 (nshell.domain.parsing:sequence-node-commands ast)) :to-be-truthy)
      (expect '(:and) :to-equal (nshell.domain.parsing:sequence-node-separators ast))))

  (it "parse-background-pipeline-preserves-sequence-node"
    "A trailing & backgrounds the whole pipeline, not the final command only."
    (with-complete-ast (ast "echo one | cat &")
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 1 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect (nshell.domain.parsing:pipeline-node-p
           (first (nshell.domain.parsing:sequence-node-commands ast))) :to-be-truthy)
      (expect '(:amp) :to-equal (nshell.domain.parsing:sequence-node-separators ast))))

  (it "parse-newline-sequence"
    (with-complete-ast (ast (format nil "echo one~%echo two"))
      (expect (nshell.domain.parsing:sequence-node-p ast) :to-be-truthy)
      (expect 2 :to-equal (length (nshell.domain.parsing:sequence-node-commands ast)))
      (expect '(:semi) :to-equal (nshell.domain.parsing:sequence-node-separators ast))))

  (it "parse-empty-input"
    (with-parsed-command-line (result "")
      (expect (nshell.domain.parsing:parse-result-ast result) :to-be-null)
      (expect :empty :to-be (nshell.domain.parsing:parse-result-state result))))

  (it "parse-empty-input-case-branch-is-explicit"
    (expect :empty :to-be (nshell.domain.parsing:with-parsed-command-line-case (result ast "")
              (:complete
               (declare (ignore result ast))
               :complete)
              (:empty
               (declare (ignore result ast))
               :empty))))

  (it "parsed-command-line-case-clause-projects-branch-body"
    "Case branch expansion should project macro clauses before generating code."
    (let ((clause (nshell.domain.parsing::%parsed-command-line-case-clause
                   :empty
                   '((:complete :complete-body)
                     (:empty :empty-body-1 :empty-body-2)))))
      (expect (nshell.domain.parsing::%parsed-command-line-case-clause-p clause) :to-be-truthy)
      (expect :empty :to-be (nshell.domain.parsing::%parsed-command-line-case-clause-keyword
               clause))
      (expect '(:empty-body-1 :empty-body-2) :to-equal (nshell.domain.parsing::%parsed-command-line-case-clause-body
                  clause))
      (expect (nshell.domain.parsing::%parsed-command-line-case-clause
                 :error
                 '((:complete :complete-body))) :to-be-null)))
  )
