(in-package #:nshell/test)

(describe "assistant-safety-classifier-contracts"
  (it "P1 preserves block across redirects wrappers and recursive short options"
    (let ((cases '("rm -rf / > out" "rm -fr /" "rm -R /" "rm -fR /"
                   "rm -ifr /" "rm --recursive /" "rm -fr ." "rm -R ~"
                   "rm -fr /*" "rm -R $HOME" "\"rm\" -fr /"
                   "sudo -u root rm -fr / > out" "command rm -R / > out"
                   "env DUMMY=1 rm -fr / > out" "DUMMY=1 rm -fr / > out"
                   "sh -c 'rm -fr /' > out" "eval 'rm -fr /' > out"
                   "rm -rf / $(git push)" "ls > out $(rm -fr /)"
                   "ls | rm -fr / > out")))
      (cl-weave:expect-assertions (* 2 (length cases)))
      (dolist (line cases)
        (let ((parsed (nshell.domain.parsing:parse-command-line line)))
          (expect (nshell.domain.parsing:parse-complete-p parsed) :to-be-truthy)
          (expect :block :to-be
                  (nshell.feature.assistant:assistant-safety-result-classification
                   (nshell.feature.assistant:classify-ast
                    (nshell.domain.parsing:parse-result-ast parsed))))))))

  (it "P1 keeps safe and confirm controls without treating operands as options"
    (let ((cases '(("ls" :safe) ("ls > out" :confirm) ("rm -f /" :confirm)
                   ("rm -- -rf /" :confirm) ("rm -- --recursive /" :confirm)
                   ("rm -fr file" :confirm)
                   ("command ls > out" :confirm) ("echo $(ls)" :safe))))
      (cl-weave:expect-assertions (* 2 (length cases)))
      (dolist (case cases)
        (let ((parsed (nshell.domain.parsing:parse-command-line (first case))))
          (expect (nshell.domain.parsing:parse-complete-p parsed) :to-be-truthy)
          (expect (second case) :to-be
                  (nshell.feature.assistant:assistant-safety-result-classification
                   (nshell.feature.assistant:classify-ast
                    (nshell.domain.parsing:parse-result-ast parsed))))))))

  (it "classifies the required command AST cases"
    (flet ((command (name &rest args)
             (nshell.domain.parsing:make-command-node name args))
           (classification (node)
             (nshell.feature.assistant:assistant-safety-result-classification
              (nshell.feature.assistant:classify-ast node))))
      (expect :block :to-be
              (classification (command "rm" "-rf" "/")))
      (expect :block :to-be
              (classification (command "rm" "-rf" "$HOME")))
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
      (expect :confirm :to-be (classification (command "git" "status")))
      (expect :safe :to-be (classification (command "grep" "needle" "file")))))

  (it "matches named rules by command basename"
    (dolist (case '( ("/bin/rm -rf /" :block)
                     ("/usr/bin/rm -rf ~" :block)
                     ("git push" :confirm)
                     ("/usr/bin/git push" :confirm)))
      (with-complete-ast (ast (first case))
        (expect (second case) :to-be
                (nshell.feature.assistant:assistant-safety-result-classification
                 (nshell.feature.assistant:classify-ast ast))))))

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
    (with-complete-ast (safe-ast "git log && ls")
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
               result))))
  (it "classifies S-expression command forms before execution"
    (labels ((classification (source)
               (nshell.feature.assistant:assistant-safety-result-classification
                (nshell.feature.assistant:classify-ast
                 (first
                  (nshell.domain.parsing:read-submission
                   source :reader-context :sexp)))))
             (reader-result (source)
               (first
                (nshell.domain.parsing:read-submission
                 source :reader-context :auto)))
             (reader-result-classification (reader-result)
               (nshell.feature.assistant:assistant-safety-result-classification
                (nshell.feature.assistant:classify-ast reader-result)))
             (legacy-classification (source)
               (nshell.feature.assistant:assistant-safety-result-classification
                (nshell.feature.assistant:classify-ast
                 (nshell.domain.parsing:parse-result-ast
                  (nshell.domain.parsing:parse-command-line source))))))
      (cl-weave:expect-assertions 25)
      (expect :confirm :to-be (classification "(ls)"))
      (expect :safe :to-be (classification "(^ls)"))
      (expect :block :to-be (classification "(rm -rf /)"))
      (expect :block :to-be (classification "(| (ls) (rm -rf /))"))
      (expect :block :to-be (classification "(cat <(rm -rf /))"))
      (progn
        (expect :block :to-be (classification "(^rm -rf /)"))
        (expect :block :to-be (classification "(^rm -rf marker-dir)"))
        (expect :confirm :to-be (legacy-classification "rm -rf marker-dir"))
        (expect :confirm :to-be (classification "(^rm -- -rf marker-dir)")))
      (expect :block :to-be (classification "(|rm| -rf /)"))
      (expect :confirm :to-be (classification "(^ls > /tmp/marker)"))
      (expect :confirm :to-be
              (classification "(^printf value >> /tmp/marker)"))
      (expect :confirm :to-be
              (classification "(| (^ls > /tmp/marker) (^cat))"))
      (expect :confirm :to-be (classification "(unknown-form value)"))
      (expect :block :to-be
              (nshell.feature.assistant:assistant-safety-result-classification
               (nshell.feature.assistant:classify-ast
                (nshell.domain.parsing:read-submission
                 "(^ls) (^rm -rf /)" :reader-context :sexp))))
      (expect :confirm :to-be (legacy-classification "ls > /tmp/marker"))
      (expect :confirm :to-be (nshell.feature.assistant:assistant-safety-result-classification (nshell.feature.assistant:classify-ast (list :unknown "form"))))
      (let* ((result (reader-result "ls"))
             (form (nshell.domain.parsing:reader-result-form result)))
        (expect (nshell.domain.parsing:command-node-p form) :to-be-truthy)
        (expect :safe :to-be (reader-result-classification result)))
      (let* ((result (reader-result "ls > /tmp/marker"))
             (form (nshell.domain.parsing:reader-result-form result)))
        (expect (nshell.domain.parsing:command-node-p form) :to-be-truthy)
        (expect :confirm :to-be (reader-result-classification result)))
      (let* ((result (reader-result "ls > /tmp/marker | cat"))
             (form (nshell.domain.parsing:reader-result-form result)))
        (expect (nshell.domain.parsing:pipeline-node-p form) :to-be-truthy)
        (expect :confirm :to-be (reader-result-classification result)))
      (let* ((result (reader-result "ls ; cat > /tmp/marker"))
             (form (nshell.domain.parsing:reader-result-form result)))
        (expect (nshell.domain.parsing:sequence-node-p form) :to-be-truthy)
        (expect :confirm :to-be (reader-result-classification result)))))
  (it "routes S-expression proposals and agent steps through reader results"
  (let ((original-reader
          (symbol-function
           (find-symbol "READ-SUBMISSION" "NSHELL.DOMAIN.PARSING")))
        (original-classifier
          (symbol-function
           (find-symbol "CLASSIFY-AST" "NSHELL.FEATURE.ASSISTANT")))
        (reader-contexts nil)
        (classified-inputs nil)
        (classification-depth 0)
        (reader-setting "sexp"))
    (with-temporary-function
        ('uiop:getenv
         (lambda (name)
           (when (string= name "NSHELL_READER") reader-setting)))
      (with-temporary-function
          ('nshell.domain.parsing:read-submission
           (lambda (source &key reader-context)
             (push reader-context reader-contexts)
             (funcall original-reader source :reader-context reader-context)))
        (with-temporary-function
            ('nshell.feature.assistant:classify-ast
             (lambda (input)
               (when (zerop classification-depth)
                 (push input classified-inputs))
               (incf classification-depth)
               (unwind-protect
                    (funcall original-classifier input)
                 (decf classification-depth))))
          (cl-weave:expect-assertions 27)
          (multiple-value-bind (status classification reason)
              (nshell.presentation::%assistant-proposal-assessment
               "(^rm -rf /)")
            (expect :classified :to-be status)
            (expect nil :to-be reason)
            (expect :block :to-be
                    (nshell.feature.assistant:assistant-safety-result-classification
                     classification)))
          (let ((step (nshell.application::%agent-step-from-text "(^rm -rf /)")))
            (expect :awaiting-approval :to-be
                    (nshell.application:agent-step-status step))
            (expect :block :to-be
                    (nshell.feature.assistant:assistant-safety-result-classification
                     (nshell.application:agent-step-classification step)))
            (expect (nshell.domain.parsing:command-node-p
                     (nshell.application:agent-step-ast step)) :to-be-truthy)
            (expect "rm" :to-equal
                    (nshell.domain.parsing:command-node-command
                     (nshell.application:agent-step-ast step)))
            (expect (nshell.domain.parsing:command-node-force-external-p
                     (nshell.application:agent-step-ast step)) :to-be-truthy))
          (multiple-value-bind (status classification reason)
              (nshell.presentation::%assistant-proposal-assessment
               "ls > /tmp/marker")
            (expect :classified :to-be status)
            (expect nil :to-be reason)
            (expect :confirm :to-be
                    (nshell.feature.assistant:assistant-safety-result-classification
                     classification)))
          (let ((step (nshell.application::%agent-step-from-text
                       "ls > /tmp/marker")))
            (expect :awaiting-approval :to-be
                    (nshell.application:agent-step-status step))
            (expect :confirm :to-be
                    (nshell.feature.assistant:assistant-safety-result-classification
                     (nshell.application:agent-step-classification step)))
            (expect
              (and
               (nshell.domain.parsing:command-node-p
                (nshell.application:agent-step-ast step))
               (nshell.domain.parsing:command-node-redirects
                (nshell.application:agent-step-ast step)))
              :to-be-truthy))
          (let ((step (nshell.application::%agent-step-from-text
                       "(^ls) (^rm -rf /)")))
            (expect :parse-error :to-be
                    (nshell.application:agent-step-status step))
            (expect nil :to-be
                    (nshell.application:agent-step-ast step)))
          (expect (list :sexp :auto :bare-line :auto :auto) :to-equal
                  (nreverse reader-contexts))
          (let ((reader-result-inputs (nreverse classified-inputs)))
            (expect 4 :to-equal (length reader-result-inputs))
            (expect
              (every
               (lambda (input)
                 (and (consp input)
                      (every (function nshell.domain.parsing:reader-result-p)
                             input)))
               reader-result-inputs)
              :to-be-truthy))
          (setf reader-contexts nil
                reader-setting nil
                classified-inputs nil)
          (multiple-value-bind (status classification reason)
              (nshell.presentation::%assistant-proposal-assessment
               "ls > /tmp/marker")
            (expect :classified :to-be status)
            (expect :confirm :to-be
                    (nshell.feature.assistant:assistant-safety-result-classification
                     classification)))
          (let ((step (nshell.application::%agent-step-from-text
                       "ls > /tmp/marker")))
            (expect :awaiting-approval :to-be
                    (nshell.application:agent-step-status step))
            (expect :confirm :to-be
                    (nshell.feature.assistant:assistant-safety-result-classification
                     (nshell.application:agent-step-classification step)))
            (expect (nshell.domain.parsing:command-node-p
                     (nshell.application:agent-step-ast step)) :to-be-truthy))
          (expect nil :to-equal reader-contexts)
          (let ((legacy-inputs (nreverse classified-inputs)))
            (expect 2 :to-equal (length legacy-inputs))
            (expect (every (function nshell.domain.parsing:command-node-p)
                           legacy-inputs)
                    :to-be-truthy))))))))

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

  (it "keeps git read-only safety as an argument allowlist"
    (dolist (case '( ("git status" :confirm)
                     ("git log" :safe)
                     ("git diff" :confirm)
                     ("git diff --output=x" :confirm)
                     ("git diff -o x" :confirm)
                     ("git diff --output-directory=x" :confirm)
                     ("git diff --ext-diff" :confirm)
                     ("git diff --textconv" :confirm)
                     ("git log --output=x" :confirm)
                     ("git -c core.fsmonitor=true status" :confirm)
                     ("git status --exec-path" :confirm)
                     ("git status --upload-pack=helper" :confirm)
                     ("git commit -m message" :confirm)))
      (with-complete-ast (ast (first case))
        (expect (second case) :to-be
                (nshell.feature.assistant:assistant-safety-result-classification
                 (nshell.feature.assistant:classify-ast ast))))))

  (it "limits git branch safety to an explicit listing grammar"
    (let ((cases '(("git branch" :safe)
                   ("git branch --list" :safe)
                   ("git branch --list feature/*" :safe)
                   ("git branch --list -- -topic" :safe)
                   ("git branch new-name" :confirm)
                   ("git branch new-name HEAD" :confirm)
                   ("git branch -l new-name" :confirm)
                   ("git branch --" :confirm)
                   ("git branch -- new-name" :confirm)
                   ("git branch --list -d topic" :confirm)
                   ("git branch -m old new" :confirm)
                   ("git branch --set-upstream-to=origin/main topic" :confirm))))
      (cl-weave:expect-assertions (* 2 (length cases)))
      (dolist (case cases)
        (let ((parsed (nshell.domain.parsing:parse-command-line (first case))))
          (expect (nshell.domain.parsing:parse-complete-p parsed) :to-be-truthy)
          (expect (second case) :to-be
                  (nshell.feature.assistant:assistant-safety-result-classification
                   (nshell.feature.assistant:classify-ast
                    (nshell.domain.parsing:parse-result-ast parsed))))))))

  (it "limits git remote safety to listing without a subcommand"
    (let ((cases '(("git remote" :safe)
                   ("git remote -v" :safe)
                   ("git remote --verbose" :safe)
                   ("git remote remove origin" :confirm)
                   ("git remote rm origin" :confirm)
                   ("git remote add origin local-repo" :confirm)
                   ("git remote rename origin backup" :confirm)
                   ("git remote set-url origin local-repo" :confirm)
                   ("git remote -v remove origin" :confirm)
                   ("git remote update" :confirm)
                   ("git remote get-url origin" :confirm))))
      (cl-weave:expect-assertions (* 2 (length cases)))
      (dolist (case cases)
        (let ((parsed (nshell.domain.parsing:parse-command-line (first case))))
          (expect (nshell.domain.parsing:parse-complete-p parsed) :to-be-truthy)
          (expect (second case) :to-be
                  (nshell.feature.assistant:assistant-safety-result-classification
                   (nshell.feature.assistant:classify-ast
                    (nshell.domain.parsing:parse-result-ast parsed))))))))

  (it "requires confirmation for source without treating filenames as commands"
    (let ((cases '(("source echo" :confirm)
                   ("source ls" :confirm)
                   ("source git log" :confirm)
                   ("source" :confirm)
                   ("source script.sh" :confirm)
                   ("source rm -rf /" :confirm)
                   ("command source echo" :confirm)
                   ("builtin source echo" :confirm)
                   ("source $(echo echo)" :confirm)
                   ("source $(rm -rf /)" :block))))
      (cl-weave:expect-assertions (* 2 (length cases)))
      (dolist (case cases)
        (let ((parsed (nshell.domain.parsing:parse-command-line (first case))))
          (expect (nshell.domain.parsing:parse-complete-p parsed) :to-be-truthy)
          (expect (second case) :to-be
                  (nshell.feature.assistant:assistant-safety-result-classification
                   (nshell.feature.assistant:classify-ast
                    (nshell.domain.parsing:parse-result-ast parsed))))))))

  (it "preserves the existing safe git log and show argument grammar"
    (let ((cases '("git log" "git log --oneline -n 5"
                   "git log --format=%h HEAD -- file"
                   "git log --graph --all"
                   "git show" "git show --pretty=oneline HEAD"
                   "git show --format %h -- file")))
      (cl-weave:expect-assertions (* 2 (length cases)))
      (dolist (text cases)
        (let ((parsed (nshell.domain.parsing:parse-command-line text)))
          (expect (nshell.domain.parsing:parse-complete-p parsed) :to-be-truthy)
          (expect :safe :to-be
                  (nshell.feature.assistant:assistant-safety-result-classification
                   (nshell.feature.assistant:classify-ast
                    (nshell.domain.parsing:parse-result-ast parsed))))))))

  (it "blocks find output actions and command substitutions in command position"
    (dolist (text '("find . -fprint output" "find . -fprintf output %p"
                    "find . -fls output" "find . -okdir rm {} \\;"
                    "rg --pre=helper needle" "rg --search-zip needle"))
      (with-complete-ast (ast text)
        (expect :confirm :to-be
                (nshell.feature.assistant:assistant-safety-result-classification
                 (nshell.feature.assistant:classify-ast ast)))))
    (with-complete-ast (ast "$(echo rm) -rf /")
      (expect :confirm :to-be
              (nshell.feature.assistant:assistant-safety-result-classification
               (nshell.feature.assistant:classify-ast ast))))
    (dolist (text '("`echo rm` -rf /" "echo `rm -rf /`"))
      (with-complete-ast (ast text)
        (expect :confirm :to-be
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
    (with-complete-ast (ast "echo (rm -rf /)")
      (unless (eq :block
                  (nshell.feature.assistant:assistant-safety-result-classification
                   (nshell.feature.assistant:classify-ast ast)))
        (error "destructive fish-style command substitution was not blocked")))
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

  (it "re-gates an agent command after command-name expansion"
    (let ((context (nshell.application:make-shell-context
                    :environment (nshell.domain.environment:make-environment)))
          (ast (nshell.domain.parsing:make-command-node "$NSHELL_AGENT_CMD"
                                                          '("-rf" "/"))))
      (setf (nshell.application:shell-context-environment context)
            (nshell.domain.environment:env-set
             (nshell.application:shell-context-environment context)
             "NSHELL_AGENT_CMD" "rm" nil))
      (let ((nshell.application::*execution-origin* :agent)
            (nshell.application::*execution-confirmed-p* t))
        (multiple-value-bind (output code)
            (nshell.application:execute-ast-in-context context ast)
          (expect 126 :to-equal code)
          (expect (search "blocked" output) :to-be-truthy)))))

  (it "does not gate commands entered directly by a person"
    (let ((context (nshell.application:make-shell-context))
          (ast (nshell.domain.parsing:make-command-node "rm" '("-f" "file")))
          (executed-p nil))
      (let ((nshell.application::*execution-origin* :typed))
        (with-temporary-function
            ('nshell.application::execute-command-node-in-context
             (lambda (ignored-context ignored-ast)
               (declare (ignore ignored-context ignored-ast))
               (setf executed-p t)
               (values "executed" 0)))
          (multiple-value-bind (output code)
              (nshell.application:execute-ast-in-context context ast)
            (expect t :to-be executed-p)
            (expect "executed" :to-equal output)
            (expect 0 :to-equal code))))))
