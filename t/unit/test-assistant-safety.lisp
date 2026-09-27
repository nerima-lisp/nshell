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

  (it "classifies parsed command sequences by their most restrictive stage"
    (with-complete-ast (safe-ast "git status && ls")
      (expect (nshell.domain.parsing:sequence-node-p safe-ast)
              :to-be-truthy)
      (expect :safe :to-be
              (nshell.feature.assistant:assistant-safety-result-classification
               (nshell.feature.assistant:classify-ast safe-ast))))
    (with-complete-ast (blocked-ast "ls && rm -rf /")
      (expect :block :to-be
              (nshell.feature.assistant:assistant-safety-result-classification
               (nshell.feature.assistant:classify-ast blocked-ast))))
    (with-complete-ast (confirmed-ast "git status; curl http://example.com")
      (expect :confirm :to-be
              (nshell.feature.assistant:assistant-safety-result-classification
               (nshell.feature.assistant:classify-ast confirmed-ast)))))

  (it "returns block as a value for unsupported AST input"
    (let ((result (nshell.feature.assistant:classify-ast nil)))
      (expect :block :to-be
               (nshell.feature.assistant:assistant-safety-result-classification
               result)))))

  (it "fails closed through command wrappers and strictens the safe allowlist"
    (dolist (case '( ("command rm -rf /" :block)
                     ("builtin eval rm -rf /" :block)
                     ("find . -delete" :confirm)
                     ("ls > out.txt" :confirm)
                     ("git log" :safe)
                     ("git branch --list" :safe)
                     ("git remote -v" :safe)))
      (with-complete-ast (ast (first case))
        (expect (second case) :to-be
                 (nshell.feature.assistant:assistant-safety-result-classification
                 (nshell.feature.assistant:classify-ast ast))))))

  (it "classifies dangerous command substitutions by their inner command"
    (with-complete-ast (ast "echo $(ls)")
      (unless (eq :safe
                  (nshell.feature.assistant:assistant-safety-result-classification
                   (nshell.feature.assistant:classify-ast ast)))
        (error "safe command substitution was not classified as safe")))
    (with-complete-ast (ast "echo $(rm -rf /)")
      (unless (eq :block
                  (nshell.feature.assistant:assistant-safety-result-classification
                   (nshell.feature.assistant:classify-ast ast)))
        (error "destructive command substitution was not blocked")))
    (with-complete-ast (ast "echo $(git push --force)")
      (unless (eq :confirm
                  (nshell.feature.assistant:assistant-safety-result-classification
                   (nshell.feature.assistant:classify-ast ast)))
        (error "confirmable command substitution was not classified as confirm"))))

  (it "blocks destructive commands through option-bearing wrappers"
    (flet ((expect-blocked (command)
             (with-complete-ast (ast command)
               (unless (eq :block
                           (nshell.feature.assistant:assistant-safety-result-classification
                            (nshell.feature.assistant:classify-ast ast)))
                 (error "destructive wrapper was not blocked: ~a" command)))))
      (expect-blocked "sudo -u root rm -rf /")
      (expect-blocked "nice -n 10 rm -rf /")
      (expect-blocked "time -p rm -rf /")
      (expect-blocked "env FOO=bar -- rm -rf /")
      (expect-blocked "/usr/bin/env rm -rf /")
      (expect-blocked "unknown-wrapper rm -rf /")))

  (it "blocks destructive commands inside process substitutions"
    (with-complete-ast (ast "cat <(rm -rf /)")
      (expect :block :to-be
              (nshell.feature.assistant:assistant-safety-result-classification
               (nshell.feature.assistant:classify-ast ast)))))

  (it "classifies aliases by the command they expand to at the execution gate"
    (let ((context (nshell.application:make-shell-context))
          (ast (nshell.domain.parsing:make-command-node "x" '("/"))))
      (setf (gethash "x" (nshell.application:shell-context-alias-table context))
            "rm -rf")
      (let ((nshell.application::*execution-origin* :agent)
            (nshell.application::*execution-confirmed-p* nil))
        (multiple-value-bind (output code)
            (nshell.application:execute-ast-in-context context ast)
          (expect 126 :to-equal code)
          (expect (search "blocked" output) :to-be-truthy)))))

  (it "does not let outer confirmation approve an inner eval command"
    (with-repl-test-state
      (let ((context (make-test-shell-context))
            (ast (nshell.domain.parsing:make-command-node
                  "eval" '("git push --force"))))
        (let ((nshell.application::*execution-origin* :agent)
              (nshell.application::*execution-confirmed-p* t))
          (multiple-value-bind (output code)
              (nshell.application:execute-ast-in-context context ast)
            (expect 126 :to-equal code)
            (expect (search "confirmation" output) :to-be-truthy))))))
