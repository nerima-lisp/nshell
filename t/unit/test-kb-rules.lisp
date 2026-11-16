(in-package #:nshell/test)

(defun %kb-classify-line (line)
  (let ((parsed (nshell.domain.parsing:parse-command-line line)))
    (unless (nshell.domain.parsing:parse-complete-p parsed)
      (error "test input does not parse: ~S" line))
    (nshell.feature.assistant:classify-ast
     (nshell.domain.parsing:parse-result-ast parsed))))

(defun %kb-rule-names (result)
  (mapcar #'car (nshell.feature.assistant:assistant-safety-result-reasons result)))

(describe "knowledge-base classify rules"
  (it "reports the rule that decided the level"
    (let ((result (%kb-classify-line "rm -r target/")))
      (expect (nshell.feature.assistant:assistant-safety-result-classification result)
              :to-be :confirm)
      (expect (nshell.feature.assistant:assistant-safety-result-reasons result)
              :to-equal '(("classify/delete-dir" . "deletes a directory")))
      (expect (nshell.feature.assistant:assistant-safety-result-rule-name result)
              :to-equal "classify/delete-dir")
      (expect (nshell.feature.assistant:assistant-safety-result-reason result)
              :to-equal "deletes a directory")))

  (it "applies the D-78 base levels"
    (dolist (case '(("git status" :safe "classify/read-only")
                    ("git log" :safe "classify/read-only")
                    ("git diff" :safe "classify/read-only")
                    ("ls" :safe "classify/read-only")
                    ("cat README.md" :safe "classify/read-only")
                    ("frobnicate --all" :confirm "classify/unknown-command")
                    ("rm -rf build" :confirm "classify/delete-dir")
                    ("rm -rf /" :block "classify/root-recursive-delete")))
      (let ((result (%kb-classify-line (first case))))
        (expect (nshell.feature.assistant:assistant-safety-result-classification result)
                :to-be (second case))
        (expect (%kb-rule-names result) :to-equal (list (third case))))))

  (it "lists every rule at the highest level and drops lower ones"
    (let ((result (%kb-classify-line "git push --force > out")))
      (expect (nshell.feature.assistant:assistant-safety-result-classification result)
              :to-be :confirm)
      (expect (%kb-rule-names result)
              :to-equal '("classify/force-push" "classify/git-not-read-only"
                          "classify/output-redirect")))
    (let ((result (%kb-classify-line "ls; rm -rf /")))
      (expect (%kb-rule-names result)
              :to-equal '("classify/root-recursive-delete"))))

  (it "keeps the inner rule name through wrappers and substitutions"
    (expect (%kb-rule-names (%kb-classify-line "sudo rm -rf /"))
            :to-equal '("classify/root-recursive-delete"))
    (expect (%kb-rule-names (%kb-classify-line "echo $(rm -r build)"))
            :to-equal '("classify/delete-dir")))

  (it "uses the inner level only behind harmless environment assignments"
    (dolist (case '(("LANG=C git status" :safe ("classify/read-only"))
                    ("env TZ=UTC ls" :safe ("classify/read-only"))
                    ("LC_ALL=C NO_COLOR=1 TERM=dumb COLUMNS=80 ls" :safe
                     ("classify/read-only"))
                    ("GIT_EXTERNAL_DIFF=x git diff" :confirm
                     ("classify/environment-assignment"))
                    ("env GIT_EXTERNAL_DIFF=/tmp/helper git diff HEAD~1 HEAD" :confirm
                     ("classify/environment-assignment"))
                    ("env TZ=UTC GIT_EXTERNAL_DIFF=x git log" :confirm
                     ("classify/environment-assignment"))
                    ("sudo PAGER=x ls" :confirm
                     ("classify/opaque-wrapper" "classify/environment-assignment"))
                    ("env -i git status" :confirm
                     ("classify/opaque-wrapper" "classify/env-option"))
                    ("env -u PATH ls" :confirm
                     ("classify/opaque-wrapper" "classify/env-option"))
                    ("env -S 'git status'" :confirm
                     ("classify/opaque-wrapper" "classify/env-option"))
                    ("PATH=/tmp/x rm -rf /" :block ("classify/root-recursive-delete"))))
      (let ((result (%kb-classify-line (first case))))
        (expect (nshell.feature.assistant:assistant-safety-result-classification result)
                :to-be (second case))
        (expect (%kb-rule-names result) :to-equal (third case)))))

  (it "keeps git global options out of the read-only grammar"
    (dolist (line '("git -c core.pager=x log" "git -C /x status"
                    "git --exec-path=/x log" "git --exec-path log"
                    "git --config-env=core.pager=V log"
                    "git -c core.fsmonitor=x status" "git status -C x"
                    "git diff -c x"))
      (let ((result (%kb-classify-line line)))
        (expect (nshell.feature.assistant:assistant-safety-result-classification result)
                :to-be :confirm)
        (expect (%kb-rule-names result) :to-equal '("classify/git-not-read-only")))))

  (it "recognizes the root after lexical normalization"
    (dolist (line '("rm -rf --no-preserve-root /./" "rm -rf //" "rm -rf /../"
                    "rm -rf /." "rm -rf /tmp/.." "rm -rf /../../.." "rm -rf //*"
                    "rm -rf ~/" "rm -rf ./"))
      (expect (nshell.feature.assistant:assistant-safety-result-classification
               (%kb-classify-line line))
              :to-be :block))
    (dolist (line '("rm -rf /tmp/./x" "rm -rf /.x" "rm -rf ./.." "rm -rf ~/.."
                    "rm -rf /tmp//x"))
      (expect (nshell.feature.assistant:assistant-safety-result-classification
               (%kb-classify-line line))
              :to-be :confirm)))

  (it "derives command effects from the effect model"
    (expect (nshell.feature.kb:subject-effects
             :command "rm" :arguments '("-r" "target/" "--" "-x"))
            :to-equal '((nshell.feature.kb::deletes "target/")
                        (nshell.feature.kb::deletes "-x")))
    ;; Writes come from the redirects of the AST, not from argument words.
    (expect (nshell.feature.assistant:command-effects
             (nshell.domain.parsing:parse-result-ast
              (nshell.domain.parsing:parse-command-line
               "curl -o page http://x > out")))
            :to-equal '((nshell.feature.kb::writes "out") :network))
    (expect (nshell.feature.assistant:command-effects
             (nshell.domain.parsing:parse-result-ast
              (nshell.domain.parsing:parse-command-line "ls >log")))
            :to-equal '((nshell.feature.kb::writes "log")))
    (expect (nshell.feature.kb:subject-effects
             :command "grep" :arguments '(">" "log"))
            :to-equal nil)))

(describe "knowledge-base user rules"
  (it "caps a user block at confirm"
    (let ((nshell.feature.kb:*user-classify-rulebase*
            (nshell.feature.kb:make-user-classify-rulebase
             '(((nshell.feature.kb::classify ?c :block "user/no-ls" "no ls here")
                (nshell.feature.kb::command ?c "ls"))))))
      (let ((result (%kb-classify-line "ls")))
        (expect (nshell.feature.assistant:assistant-safety-result-classification result)
                :to-be :confirm)
        (expect (nshell.feature.assistant:assistant-safety-result-reasons result)
                :to-equal '(("user/no-ls" . "no ls here"))))))

  (it "cannot lower a built-in level"
    (let ((nshell.feature.kb:*user-classify-rulebase*
            (nshell.feature.kb:make-user-classify-rulebase
             '(((nshell.feature.kb::classify ?c :safe "user/allow" "allowed"))
               ((nshell.feature.kb::known-command ?c))
               ((nshell.feature.kb::read-only-command ?c))))))
      (expect (nshell.feature.assistant:assistant-safety-result-classification
               (%kb-classify-line "rm -rf /"))
              :to-be :block)
      (expect (nshell.feature.assistant:assistant-safety-result-classification
               (%kb-classify-line "frobnicate"))
              :to-be :confirm)
      (expect (%kb-rule-names (%kb-classify-line "frobnicate"))
              :to-equal '("classify/unknown-command"))))

  (it "turns a failing user rulebase into confirm"
    (let ((nshell.feature.kb:*user-classify-rulebase*
            (nshell.feature.kb:make-user-classify-rulebase
             '(((nshell.feature.kb::classify ?c :safe "user/broken" "broken")
                (nshell.feature.kb::undefined-predicate ?c))))))
      (let ((result (%kb-classify-line "ls")))
        (expect (nshell.feature.assistant:assistant-safety-result-classification result)
                :to-be :confirm)
        (expect (%kb-rule-names result) :to-equal '("kb/user-rules-error"))))))

(describe "knowledge-base evaluation budget"
  (it "blocks when the built-in rules exceed the inference budget"
    (let ((nshell.feature.kb:*classify-max-inferences* 1))
      (let ((result (%kb-classify-line "ls")))
        (expect (nshell.feature.assistant:assistant-safety-result-classification result)
                :to-be :block)
        (expect (%kb-rule-names result) :to-equal '("kb/evaluation-limit"))))))

(describe "knowledge-base diagnose/typo"
  ;; The proposal/02 E_COMMAND_NOT_FOUND example.  t/golden has no runner
  ;; until P1-7b, so the same input and fixes are fixed here.
  (it "proposes the proposal/02 fix for gti status"
    (expect (nshell.feature.kb:diagnose-typo
             :input "gti status" :status 127 :command-start 0 :command-end 3
             :known-commands '("git" "ls" "cat" "grep"))
            :to-equal '((:input "git status" :why "edit distance 1"
                         :rule "diagnose/typo"))))

  (it "orders fixes by distance and ignores far names and other statuses"
    (expect (mapcar (lambda (fix) (getf fix :input))
                    (nshell.feature.kb:diagnose-typo
                     :input "sl -a" :status 127 :command-start 0 :command-end 2
                     :known-commands '("ls" "sed" "ssh" "make")))
            :to-equal '("ls -a" "sed -a" "ssh -a"))
    (expect (nshell.feature.kb:diagnose-typo
             :input "gti status" :status 1 :command-start 0 :command-end 3
             :known-commands '("git"))
            :to-equal nil)
    (expect (nshell.feature.kb:diagnose-typo
             :input "gti status" :status 127 :command-start 0 :command-end 3
             :known-commands nil)
            :to-equal nil)))
