(in-package #:nshell/test)

;;; The closed-world safety model of P1-5 (D-P1-5 2.1-2.5): a command is safe
;;; only when its name, every option, every operand, every redirect, and
;;; every assignment prefix match the allowed form in the spec table.

(defun %closed-world-classify (line)
  (let ((parsed (nshell.domain.parsing:parse-command-line line)))
    (unless (nshell.domain.parsing:parse-complete-p parsed)
      (error "test input does not parse: ~S" line))
    (nshell.feature.assistant:classify-ast
     (nshell.domain.parsing:parse-result-ast parsed))))

(defun %closed-world-level (line)
  (nshell.feature.assistant:assistant-safety-result-classification
   (%closed-world-classify line)))

(defun %closed-world-rule-names (line)
  (mapcar #'car (nshell.feature.assistant:assistant-safety-result-reasons
                 (%closed-world-classify line))))

(defun %closed-world-expect-levels (cases)
  (dolist (case cases)
    (expect (list (first case) (%closed-world-level (first case)))
            :to-equal (list (first case) (second case)))))

(describe "closed-world safety: wrappers keep argv and quoting"
  (it "blocks a root delete that sudo runs through sh -c"
    (expect (%closed-world-level "sudo sh -c 'rm -rf /'") :to-be :block)
    (expect (%closed-world-rule-names "sudo sh -c 'rm -rf /'")
            :to-equal '("classify/root-recursive-delete")))

  (it "treats opaque wrappers as confirm at least"
    (%closed-world-expect-levels
     '(("nohup ls" :confirm) ("sudo ls" :confirm) ("xargs ls" :confirm)
       ("ls | xargs git diff" :confirm) ("bash -c 'git status'" :confirm)
       ("eval git status" :confirm) ("exec ls" :confirm)
       ("builtin echo hi" :confirm) ("command ls" :confirm)
       ("env -i ls" :confirm) ("/usr/bin/time -o FILE ls" :confirm)
       ("/usr/bin/nice ls" :confirm) ("/usr/bin/env TZ=UTC ls" :confirm)))
    (expect (%closed-world-rule-names "nohup ls")
            :to-equal '("classify/opaque-wrapper")))

  (it "finds a block inside opaque wrappers"
    (%closed-world-expect-levels
     '(("nohup rm -rf /" :block) ("xargs -n 1 rm -rf /" :block)
       ("sudo -u root sh -c 'rm -rf /'" :block)
       ("bash -c 'ls; rm -rf /'" :block) ("/usr/bin/time -o FILE rm -rf /" :block)
       ("eval 'rm -rf /'" :block) ("exec rm -rf /" :block))))

  (it "reads transparent wrapper options with the wrapper spec"
    (%closed-world-expect-levels
     '(("nice -n 10 ls" :safe) ("timeout 5 ls" :safe)
       ("timeout -s KILL -k 1 5 ls -la" :safe) ("time -p ls" :safe)
       ("not ls" :safe) ("time -o FILE ls" :confirm) ("time -a ls" :confirm)
       ("nice -n -5 ls" :confirm) ("timeout --foreground 5 ls" :confirm)
       ("nice -n 10 rm -rf /" :block) ("time -o FILE rm -rf /" :block)))
    (expect (%closed-world-rule-names "time -o FILE ls")
            :to-equal '("classify/argument-not-allowed"))))

(describe "closed-world safety: assignment prefixes"
  (it "matches assignment names against the harmless table only"
    (%closed-world-expect-levels
     '(("env TZ=UTC ls" :safe) ("LC_ALL=C TZ=UTC ls" :safe)
       ("env LC_MESSAGES=C ls" :safe)
       ("env GIT_EXTERNAL_DIFF=/tmp/helper git diff HEAD~1 HEAD" :confirm)
       ("env FOO+=x ls" :confirm) ("env LANG+=C ls" :confirm)
       ("env 1=x ls" :confirm) ("env '=x' ls" :confirm)
       ("env LC_=x ls" :confirm) ("env LC_ALL+=x ls" :confirm)))
    (dolist (line '("env FOO+=x ls" "env LANG+=C ls" "env 1=x ls" "env '=x' ls"))
      (expect (list line (%closed-world-rule-names line))
              :to-equal (list line '("classify/environment-assignment"))))))

(describe "closed-world safety: argument specs"
  (it "closes the options the review found"
    (%closed-world-expect-levels
     '(("rg --hostname-bin=/tmp/helper needle" :confirm)
       ("rg --hyperlink-format=x needle" :confirm) ("rg -z needle" :confirm)
       ("rg --pre=helper needle" :confirm) ("rg --pre-glob=x needle" :confirm)
       ("rg --search-zip needle" :confirm)
       ("file -C -m magic x" :confirm) ("file -m magic x" :confirm)
       ("file --compile x" :confirm) ("file -i x" :confirm)
       ("find -- . -name a -delete" :confirm) ("find . -fprint0 x" :confirm)
       ("find . -name a -exec rm {} \\;" :confirm) ("find . -name a stray" :confirm)
       ("git log --format=%G?" :confirm) ("git show --pretty=format:%GS" :confirm)
       ("git log --show-signature" :confirm) ("git show --output=x" :confirm)
       ("ls --hyperlink" :confirm) ("ls -G" :confirm) ("cat -u x" :confirm)))
    (expect (%closed-world-rule-names "rg --hostname-bin=/tmp/helper needle")
            :to-equal '("classify/argument-not-allowed"))
    (expect (search "--hostname-bin=/tmp/helper"
                    (nshell.feature.assistant:assistant-safety-result-reason
                     (%closed-world-classify "rg --hostname-bin=/tmp/helper needle")))
            :to-be-truthy)
    (expect (%closed-world-rule-names "git log --format=%G?")
            :to-equal '("classify/git-not-read-only")))

  (it "accepts the allowed forms"
    (%closed-world-expect-levels
     '(("ls --color=auto" :safe) ("ls --color" :safe) ("ls -la src" :safe)
       ("ls -1 -- -odd-name" :safe) ("cat -n README.md" :safe)
       ("file -b --mime-type x" :safe)
       ("rg -i -e -pattern -g '*.lisp' -A3 needle src" :safe)
       ("rg --glob=*.lisp --type lisp --color=never needle" :safe)
       ("find . -name '*.lisp' -type f -print" :safe)
       ("find -L src ! -name a -o -name b -prune" :safe)
       ("git status -sb" :safe) ("git status -uno --porcelain=v2" :safe)
       ("git log --oneline -n 5" :safe) ("git log --pretty=fuller" :safe)
       ("git log --format=%h%x09%s" :safe) ("git branch --" :safe)
       ("git branch -a" :safe) ("git remote -v" :safe))))

  (it "matches grep against its spec row without long-name prefixes"
    (%closed-world-expect-levels
     '(("grep needle file" :safe) ("grep -rn --include=*.lisp -e needle src" :safe)
       ("grep --inclu=*.lisp needle src" :confirm) ("grep -P needle file" :confirm))))

  (it "keeps the git branch listing grammar"
    (%closed-world-expect-levels
     '(("git branch -- new-name" :confirm) ("git branch -a new-name" :confirm)
       ("git branch --list -- -topic" :safe) ("git branch -d topic" :confirm))))

  (it "closes echo and printf escapes"
    (%closed-world-expect-levels
     '(("echo hello world" :safe) ("echo -n hello" :safe) ("printf '%s' x" :safe)
       ("echo -e hello" :confirm) ("echo -E hello" :confirm)
       ("printf '\\e]52;c;aGk=\\a'" :confirm) ("printf '%s\\n' x" :confirm)
       ("echo 'a\\b'" :confirm) ("printf -v x y" :confirm)))
    (expect (%closed-world-level
             (format nil "echo '~a]52;c;aGk=~a'" (code-char 27) (code-char 7)))
            :to-be :confirm))

  (it "matches only the bare command name"
    (%closed-world-expect-levels
     '(("/bin/ls" :confirm) ("./ls -la" :confirm) ("/usr/bin/git status" :confirm))))

  (it "changes no other command when the table grows by one row"
    (let ((before (mapcar #'%closed-world-level '("ls -la" "frobnicate" "git status"))))
      (let ((nshell.feature.kb::+safe-command-specs+
              (cons '("frobnicate" :flags "q" :positionals 0)
                    nshell.feature.kb::+safe-command-specs+)))
        (expect (%closed-world-level "frobnicate -q") :to-be :safe)
        (expect (%closed-world-level "frobnicate x") :to-be :confirm)
        (expect (list (%closed-world-level "ls -la") (%closed-world-level "git status"))
                :to-equal (list (first before) (third before))))
      (expect (second before) :to-be :confirm))))

(describe "closed-world safety: redirects from the AST"
  (it "allows only /dev/null and the stdout/stderr duplications"
    (%closed-world-expect-levels
     '(("ls > /dev/null" :safe) ("ls 2>/dev/null" :safe) ("ls &> /dev/null" :safe)
       ("ls 2>&1" :safe) ("ls 1>&2" :safe) ("cat < README.md" :safe)
       ("ls > out" :confirm) ("ls >> out" :confirm) ("ls 2> err" :confirm)
       ("ls 3>&1" :confirm) ("ls >(cat)" :confirm)))
    (expect (%closed-world-rule-names "ls > out")
            :to-equal '("classify/output-redirect")))

  (it "judges substitutions inside here-documents and here-strings"
    (%closed-world-expect-levels
     (list (list (format nil "cat <<EOF~%hello~%EOF") :safe)
           (list (format nil "cat <<EOF~%$(rm -rf /)~%EOF") :block)
           (list "cat <<< hello" :safe)
           (list "cat <<< $(rm -rf /)" :block)
           (list "cat <<< `ls`" :confirm))))

  (it "builds write effects from the AST redirects"
    (with-complete-ast (ast "curl -o page http://x > out")
      (expect (nshell.feature.assistant:command-effects ast)
              :to-equal '((nshell.feature.kb::writes "out") :network)))
    (with-complete-ast (ast "grep x f")
      (expect (nshell.feature.assistant:command-effects ast) :to-equal nil))))

;;; R-P1-5: the classifier must read assignments from the AST the way the
;;; executors split them, not from the `=' in a word.  A quoted or forced
;;; NAME=value word, and every word after one, names a command.
(describe "closed-world safety: assignments come from the AST"
  (it "treats quoted and forced NAME=value words as commands"
    (dolist (case '((:bare "\"LANG=C\" ls") (:bare "'LANG=C' cat")
                    (:bare "LANG=C \"TZ=UTC\" ls") (:auto "(^LANG=C ls)")))
      (destructuring-bind (reader source) case
        (expect (list source
                      (nshell.feature.assistant:assistant-safety-result-classification
                       (if (eq reader :bare)
                           (%closed-world-classify source)
                           (nshell.feature.assistant:classify-ast
                            (nshell.domain.parsing:read-submission
                             source :reader-context :auto)))))
                :to-equal (list source :confirm)))))

  (it "stops an alias whose expansion starts with a NAME=value word"
    ;; On the AST path the executor splits the prefix before it expands the
    ;; alias, so an alias ls='LANG=C ls' runs a command named LANG=C.
    (let ((context (make-test-shell-context)))
      (setf (gethash "ls" (nshell.application:shell-context-alias-table context))
            "LANG=C ls")
      (let ((nshell.application:*execution-origin* :proposal)
            (nshell.application:*execution-approval* :safe)
            (nshell.application:*execution-gate-stopped-p* nil))
        (multiple-value-bind (output code)
            (nshell.application:execute-ast-in-context
             context (nshell.domain.parsing:make-command-node "ls" nil))
          (declare (ignore output))
          (expect 126 :to-equal code)
          (expect t :to-be nshell.application:*execution-gate-stopped-p*))))))

;;; R-P1-5: a forced (^name) command runs the external program, so specs and
;;; wrapper rows written for the builtin of that name must not apply.
(describe "closed-world safety: builtin rows apply only to builtins"
  (it "judges forced and, or, and not as external commands"
    (dolist (source '("(^and ls)" "(^or ls)" "(^not ls)"))
      (expect (list source
                    (nshell.feature.assistant:assistant-safety-result-classification
                     (nshell.feature.assistant:classify-ast
                      (nshell.domain.parsing:read-submission
                       source :reader-context :auto))))
              :to-equal (list source :confirm)))))
