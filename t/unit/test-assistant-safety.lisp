(in-package #:nshell/test)

(describe "assistant-safety-classifier-contracts"
  (it "classifies the required command AST cases"
    (flet ((command (name &rest args)
             (nshell.domain.parsing:make-command-node name args))
           (classification (node)
             (nshell.feature.assistant:assistant-safety-result-classification
              (nshell.feature.assistant:classify-ast node))))
      (expect :block :to-be
              (classification (command "rm" "-rf" "/")))
      (expect :confirm :to-be
              (classification (command "git" "push" "--force")))
      (expect :confirm :to-be
              (classification (command "dd" "if=input" "of=/dev/disk1")))
      (expect :confirm :to-be
              (classification
               (nshell.domain.parsing:make-pipeline-node
                (list (command "curl" "https://example.invalid/script")
                      (command "sh")))))
      (expect :safe :to-be (classification (command "ls")))
      (expect :safe :to-be (classification (command "git" "status")))
      (expect :safe :to-be (classification (command "grep" "needle" "file")))))

  (it "keeps root-recursive delete ahead of generic delete"
    (let ((result
            (nshell.feature.assistant:classify-ast
             (nshell.domain.parsing:make-command-node "rm" '("-rf" "/")))))
      (expect :block :to-be
              (nshell.feature.assistant:assistant-safety-result-classification
               result))))

  (it "uses the most restrictive stage in a pipeline"
    (let* ((safe (nshell.domain.parsing:make-command-node "ls" nil))
           (confirm (nshell.domain.parsing:make-command-node "rm" '("file")))
           (pipeline (nshell.domain.parsing:make-pipeline-node
                      (list safe confirm)))
           (result (nshell.feature.assistant:classify-pipeline pipeline)))
      (expect :confirm :to-be
              (nshell.feature.assistant:assistant-safety-result-classification
               result))))

  (it "returns block as a value for unsupported AST input"
    (let ((result (nshell.feature.assistant:classify-ast nil)))
      (expect :block :to-be
              (nshell.feature.assistant:assistant-safety-result-classification
               result)))))
