(in-package #:nshell/test)

(defun %kb-classify-line (line)
  (let ((parsed (nshell.domain.parsing:parse-command-line line)))
    (unless (nshell.domain.parsing:parse-complete-p parsed)
      (error "test input does not parse: ~S" line))
    (%test-classify-ast
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
            :to-equal '((nshell.feature.kb::writes "log")
                        (nshell.feature.kb::reads ".")))
    (expect (nshell.feature.kb:subject-effects
             :command "grep" :arguments '(">" "log"))
            :to-equal nil))

  (it "derives read effects only from the commands whose reads it states"
    (flet ((effects (line)
             (nshell.feature.assistant:command-effects
              (nshell.domain.parsing:parse-result-ast
               (nshell.domain.parsing:parse-command-line line)))))
      ;; proposal/02: git status reads the working tree.
      (expect (effects "git status --short")
              :to-equal '((nshell.feature.kb::reads ".")))
      (expect (effects "cat -n a.txt -- -b")
              :to-equal '((nshell.feature.kb::reads "a.txt")
                          (nshell.feature.kb::reads "-b")))
      (expect (effects "ls -la src")
              :to-equal '((nshell.feature.kb::reads "src")))
      (expect (effects "ls -la")
              :to-equal '((nshell.feature.kb::reads ".")))
      ;; Without an operand wc and cat read only standard input.
      (dolist (line '("wc -l" "cat" "git log -n 3" "grep x f" "head -n 5"))
        (expect (list line (effects line)) :to-equal (list line nil)))))

  (it "reads operands as the spec row separates them and - as standard input"
    (flet ((effects (line)
             (nshell.feature.assistant:command-effects
              (nshell.domain.parsing:parse-result-ast
               (nshell.domain.parsing:parse-command-line line)))))
      ;; The value of a value flag is no operand.
      (expect (effects "head -n 5 f") :to-equal '((nshell.feature.kb::reads "f")))
      (expect (effects "tail -n5 -c 10 f g")
              :to-equal '((nshell.feature.kb::reads "f") (nshell.feature.kb::reads "g")))
      ;; - is standard input, not a path, for the commands whose spec row
      ;; says so, after -- too; ls reads a file named -.
      (expect (effects "cat - f") :to-equal '((nshell.feature.kb::reads "f")))
      (expect (effects "ls -") :to-equal '((nshell.feature.kb::reads "-")))
      (expect (effects "ls -- -") :to-equal '((nshell.feature.kb::reads "-")))
      (dolist (line '("cat -- -" "wc -l -- -" "head -n 1 -- -"))
        (expect (list line (effects line)) :to-equal (list line nil)))
      ;; An option the row does not describe may take a value, so no word
      ;; is known to be an operand: file -F takes a separator.
      (dolist (line '("wc -" "cat -" "file -F : x" "cat -Z f" "ls -Z"))
        (expect (list line (effects line)) :to-equal (list line nil))))))

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

  (it "keeps only the nearest fixes and ignores far names and other statuses"
    (flet ((inputs (input end known)
             (mapcar (lambda (fix) (getf fix :input))
                     (nshell.feature.kb:diagnose-typo
                      :input input :status 127 :command-start 0 :command-end end
                      :known-commands known))))
      ;; sl is one transposition from ls and two edits from sed and ssh.
      (expect (inputs "sl -a" 2 '("ssh" "ls" "sed" "make")) :to-equal '("ls -a"))
      ;; The builtin ai is two edits from gti, git one.
      (expect (inputs "gti status" 3 '("ai" "git" "at"))
              :to-equal '("git status"))
      ;; Every fix at the nearest distance is kept, in name order.
      (expect (inputs "gti status" 3 '("gtx" "ai" "git" "gt"))
              :to-equal '("git status" "gt status" "gtx status"))
      ;; With nothing one edit away, the names two edits away are the fixes.
      (expect (nshell.feature.kb:diagnose-typo
               :input "sl -a" :status 127 :command-start 0 :command-end 2
               :known-commands '("ssh" "sed" "make"))
              :to-equal '((:input "sed -a" :why "edit distance 2" :rule "diagnose/typo")
                          (:input "ssh -a" :why "edit distance 2" :rule "diagnose/typo"))))
    (expect (nshell.feature.kb:diagnose-typo
             :input "gti status" :status 1 :command-start 0 :command-end 3
             :known-commands '("git"))
            :to-equal nil)
    (expect (nshell.feature.kb:diagnose-typo
             :input "gti status" :status 127 :command-start 0 :command-end 3
             :known-commands nil)
            :to-equal nil)))

(defun %kb-read-line (line)
  (nshell.domain.parsing:read-submission
   line :reader-context (nshell.domain.parsing:submission-reader-context line)))

(defun %kb-walk-subjects (thunk)
  "Call THUNK with a subject visitor bound; return THUNK's values and, after
them, the (SUBJECT . RUNS-P) pairs the walk described, in order."
  (let ((seen '()))
    (let ((values (let ((nshell.feature.assistant::*assistant-subject-visitor*
                          (lambda (subject runs-p)
                            (push (cons (copy-list subject) runs-p) seen))))
                    (multiple-value-list (funcall thunk)))))
      (values-list (append values (list (nreverse seen)))))))

(defun %kb-alias-context ()
  (let ((context (make-test-shell-context)))
    (setf (gethash "del" (nshell.application:shell-context-alias-table context))
          "rm -f")
    context))

(describe "knowledge-base effects follow the classifier's walk"
  (it "collects the effects of the commands in substitutions"
    (flet ((effects (line)
             (nshell.feature.assistant:command-effects (%kb-read-line line))))
      (expect (effects "echo $(rm victim)")
              :to-equal '((nshell.feature.kb::deletes "victim")))
      (expect (effects "echo $(cat fixture)")
              :to-equal '((nshell.feature.kb::reads "fixture")))
      (expect (effects "cat <(cat f) > out")
              :to-equal '((nshell.feature.kb::reads "f")
                          (nshell.feature.kb::writes "out")))
      ;; The body of a quoted here-document is passed on as written; only
      ;; an unquoted one runs its substitutions.
      (expect (effects (format nil "cat <<'EOF'~%$(cat fixture)~%EOF")) :to-equal nil)
      (expect (effects (format nil "cat <<EOF~%$(cat fixture)~%EOF"))
              :to-equal '((nshell.feature.kb::reads "fixture")))))

  (it "follows an alias of the context to the command it runs"
    (let ((resolve (nshell.application:assistant-command-resolver (%kb-alias-context))))
      (multiple-value-bind (effects result)
          (nshell.feature.assistant:command-effects (%kb-read-line "del victim")
                                                    :resolve resolve)
        (expect effects :to-equal '((nshell.feature.kb::deletes "victim")))
        (expect (%kb-rule-names result) :to-equal '("classify/delete")))
      ;; An alias the same input defines has not run when the line is
      ;; judged: neither the verdict nor the effects see its expansion.
      (multiple-value-bind (effects result)
          (nshell.feature.assistant:command-effects
           (%kb-read-line "alias del2='rm -f'; del2 victim")
           :resolve (nshell.application:assistant-command-resolver
                     (make-test-shell-context)))
        (expect effects :to-equal nil)
        (expect (%kb-rule-names result) :to-equal '("classify/unknown-command")))))

  (it "collects effects from exactly the subjects the classifier judges"
    (let ((context (%kb-alias-context)))
      (dolist (line (list "echo $(rm victim)" "cat a | wc -l > out" "ls; rm -r build"
                          "(| (git status --short) (wc -l))" "(rm -rf build)"
                          "env FOO=1 rm x" "sh -c 'cat f'" "sudo rm x" "timeout 5 cat f"
                          "del victim" "cat <(cat f)" "command -v ls" "foo rm -rf x"
                          (format nil "cat <<'EOF'~%$(rm victim)~%EOF")
                          (format nil "cat <<EOF~%$(rm victim)~%EOF")))
        (let ((resolve (nshell.application:assistant-command-resolver context))
              (input (%kb-read-line line)))
          (multiple-value-bind (verdict judged)
              (%kb-walk-subjects
               (lambda () (nshell.feature.assistant:classify-ast input :resolve resolve)))
            (multiple-value-bind (effects result walked)
                (%kb-walk-subjects
                 (lambda ()
                   (nshell.feature.assistant:command-effects input :resolve resolve)))
              ;; The effect walk is the classifier's walk ...
              (expect (list line walked) :to-equal (list line judged))
              (expect (list line
                            (nshell.feature.assistant:assistant-safety-result-classification
                             result)
                            (nshell.feature.assistant:assistant-safety-result-reasons result))
                      :to-equal
                      (list line
                            (nshell.feature.assistant:assistant-safety-result-classification
                             verdict)
                            (nshell.feature.assistant:assistant-safety-result-reasons verdict)))
              ;; ... and the effects are those of the subjects it runs.
              (expect (list line effects)
                      :to-equal
                      (list line
                            (remove-duplicates
                             (loop for (subject . runs-p) in judged
                                   when runs-p
                                     append (apply #'nshell.feature.kb:subject-effects
                                                   subject))
                             :test #'equal :from-end t)))))))))

  (it "gives no effects to commands it judges but the line does not run"
    ;; The walk judges the command named in the operands as if it ran:
    ;; echo prints it, and what foo does with it is unknown.
    (dolist (line '("echo rm x" "foo rm -rf x"))
      (multiple-value-bind (effects result judged)
          (%kb-walk-subjects
           (lambda ()
             (nshell.feature.assistant:command-effects
              (%kb-read-line line)
              :resolve (nshell.application:assistant-command-resolver
                        (make-test-shell-context)))))
        (declare (ignore result))
        (expect (list line (notevery #'cdr judged)) :to-equal (list line t))
        (expect (list line effects) :to-equal (list line nil))))))
