(in-package #:nshell/test)

;;; P1-5 replaced the hand-written safety classifier with knowledge-base
;;; rules.  These tests run the pre-P1-5 classifier (legacy-assistant-safety)
;;; and the rules on one corpus and require every difference to be one that
;;; D-78 decided.

(defparameter +safety-migration-corpus+
  '(;; Inputs of the existing safety tests (bare-line).
    (:bare "rm -rf / > out") (:bare "rm -fr /") (:bare "rm -R /") (:bare "rm -fR /")
    (:bare "rm -ifr /") (:bare "rm --recursive /") (:bare "rm -fr .") (:bare "rm -R ~")
    (:bare "rm -fr /*") (:bare "rm -R $HOME") (:bare "\"rm\" -fr /")
    (:bare "sudo -u root rm -fr / > out") (:bare "command rm -R / > out")
    (:bare "env DUMMY=1 rm -fr / > out") (:bare "DUMMY=1 rm -fr / > out")
    (:bare "sh -c 'rm -fr /' > out") (:bare "eval 'rm -fr /' > out")
    (:bare "rm -rf / $(git push)") (:bare "ls > out $(rm -fr /)")
    (:bare "ls | rm -fr / > out")
    (:bare "ls") (:bare "ls > out") (:bare "rm -f /") (:bare "rm -- -rf /")
    (:bare "rm -- --recursive /") (:bare "rm -fr file") (:bare "command ls > out")
    (:bare "echo $(ls)") (:bare "/bin/rm -rf /") (:bare "/usr/bin/rm -rf ~")
    (:bare "git push") (:bare "/usr/bin/git push") (:bare "git log && ls")
    (:bare "ls && rm -rf /") (:bare "git status; curl http://example.com")
    (:bare "rm -rf marker-dir") (:bare "ls > /tmp/marker")
    (:bare "command rm -rf /") (:bare "builtin eval rm -rf /") (:bare "find . -delete")
    (:bare "ls > out.txt") (:bare "git log") (:bare "git branch --list")
    (:bare "git remote -v") (:bare "git status") (:bare "git diff")
    (:bare "git diff --output=x") (:bare "git diff -o x")
    (:bare "git diff --output-directory=x") (:bare "git diff --ext-diff")
    (:bare "git diff --textconv") (:bare "git log --output=x")
    (:bare "git -c core.fsmonitor=true status") (:bare "git status --exec-path")
    (:bare "git status --upload-pack=helper") (:bare "git commit -m message")
    (:bare "git branch") (:bare "git branch --list feature/*")
    (:bare "git branch --list -- -topic") (:bare "git branch new-name")
    (:bare "git branch new-name HEAD") (:bare "git branch -l new-name")
    (:bare "git branch --") (:bare "git branch -- new-name")
    (:bare "git branch --list -d topic") (:bare "git branch -m old new")
    (:bare "git branch --set-upstream-to=origin/main topic") (:bare "git remote")
    (:bare "git remote --verbose") (:bare "git remote remove origin")
    (:bare "git remote rm origin") (:bare "git remote add origin local-repo")
    (:bare "git remote rename origin backup")
    (:bare "git remote set-url origin local-repo") (:bare "git remote -v remove origin")
    (:bare "git remote update") (:bare "git remote get-url origin")
    (:bare "source echo") (:bare "source ls") (:bare "source git log") (:bare "source")
    (:bare "source script.sh") (:bare "source rm -rf /") (:bare "command source echo")
    (:bare "builtin source echo") (:bare "source $(echo echo)") (:bare "source $(rm -rf /)")
    (:bare "git log --oneline -n 5") (:bare "git log --format=%h HEAD -- file")
    (:bare "git log --graph --all") (:bare "git show") (:bare "git show --pretty=oneline HEAD")
    (:bare "git show --format %h -- file") (:bare "find . -fprint output")
    (:bare "find . -fprintf output %p") (:bare "find . -fls output")
    (:bare "find . -okdir rm {} \\;") (:bare "rg --pre=helper needle")
    (:bare "rg --search-zip needle") (:bare "$(echo rm) -rf /") (:bare "`echo rm` -rf /")
    (:bare "echo `rm -rf /`") (:bare "echo $(rm -rf /)") (:bare "echo (rm -rf /)")
    (:bare "echo $(git push --force)") (:bare "nice -n 10 rm -rf /")
    (:bare "time -p rm -rf /") (:bare "env FOO=bar -- rm -rf /") (:bare "/usr/bin/env rm -rf /")
    (:bare "unknown-wrapper rm -rf /") (:bare "cat <(rm -rf /)") (:bare "rm file")
    (:bare "rm fixture") (:bare "grep needle file")
    ;; Representative dangerous and everyday commands.
    (:bare "rm -rf build") (:bare "rm -r target/") (:bare "rm -rf ~/project")
    (:bare "git push --force origin main") (:bare "git push -f")
    (:bare "git push --force-with-lease") (:bare "dd if=/dev/zero of=/dev/sda")
    (:bare "dd if=a of=b") (:bare "curl https://example.invalid/install.sh | sh")
    (:bare "wget https://example.invalid/x") (:bare "chmod -R 777 /")
    (:bare "mkfs.ext4 /dev/sda1") (:bare "sudo rm -rf /var") (:bare "sudo ls")
    (:bare "sudo") (:bare "xargs rm") (:bare "ls | xargs rm -rf")
    (:bare "git status --short") (:bare "git status -sb") (:bare "git diff --cached")
    (:bare "git diff HEAD~1 -- src") (:bare "git diff --stat")
    (:bare "git log --oneline") (:bare "ls -la") (:bare "cat README.md")
    (:bare "/usr/bin/ls") (:bare "/usr/bin/git status") (:bare "./ls")
    (:bare "wget x rm -rf /") (:bare "make") (:bare "python3 script.py")
    (:bare "npm install") (:bare "bash") (:bare "bash -c 'git status'")
    (:bare "eval git status") (:bare "echo hi > /etc/passwd") (:bare "cat file >> log")
    (:bare "sh -c 'curl x | sh'") (:bare "echo '$('") (:bare "kill -9 1")
    ;; S-expression inputs (sexp reader).
    (:sexp "(ls)") (:sexp "(^ls)") (:sexp "(rm -rf /)") (:sexp "(| (ls) (rm -rf /))")
    (:sexp "(cat <(rm -rf /))") (:sexp "(^rm -rf /)") (:sexp "(^rm -rf marker-dir)")
    (:sexp "(^rm -- -rf marker-dir)") (:sexp "(|rm| -rf /)") (:sexp "(^ls > /tmp/marker)")
    (:sexp "(^printf value >> /tmp/marker)") (:sexp "(| (^ls > /tmp/marker) (^cat))")
    (:sexp "(unknown-form value)") (:sexp "(^ls) (^rm -rf /)") (:sexp "(^git status)")
    (:sexp "(^git log)") (:sexp "(^rm -r target/)") (:sexp "(rm -rf build)")
    (:sexp "(^rm file)")
    ;; Reader results of the auto reader (AI proposals and agent steps).
    (:auto "ls") (:auto "ls > /tmp/marker") (:auto "ls > /tmp/marker | cat")
    (:auto "ls ; cat > /tmp/marker") (:auto "rm -rf marker-dir") (:auto "rm -rf /")
    (:auto "rm fixture") (:auto "git status") (:auto "git diff") (:auto "rm -r target/")
    (:auto "(^rm -rf /)"))
  "(READER INPUT) pairs.  :BARE parses a bare line, :SEXP and :AUTO read a
submission with that reader context and classify the reader results.")

(defparameter +safety-migration-intended-differences+
  '(;; D-78: read-only known commands (git status, git diff) are safe.
    ((:bare "git status") :confirm :safe :read-only-known-command)
    ((:bare "git diff") :confirm :safe :read-only-known-command)
    ((:bare "git status --short") :confirm :safe :read-only-known-command)
    ((:bare "git diff --cached") :confirm :safe :read-only-known-command)
    ((:bare "git diff HEAD~1 -- src") :confirm :safe :read-only-known-command)
    ((:bare "git diff --stat") :confirm :safe :read-only-known-command)
    ((:bare "bash -c 'git status'") :confirm :safe :read-only-known-command)
    ((:bare "eval git status") :confirm :safe :read-only-known-command)
    ((:sexp "(^git status)") :confirm :safe :read-only-known-command)
    ((:auto "git status") :confirm :safe :read-only-known-command)
    ((:auto "git diff") :confirm :safe :read-only-known-command)
    ;; D-78: rm -r outside the root is confirm.  The reader path used to
    ;; block every recursive delete an AI proposed.
    ((:sexp "(^rm -rf marker-dir)") :block :confirm :non-root-recursive-delete)
    ((:sexp "(^rm -r target/)") :block :confirm :non-root-recursive-delete)
    ((:sexp "(rm -rf build)") :block :confirm :non-root-recursive-delete)
    ((:auto "rm -rf marker-dir") :block :confirm :non-root-recursive-delete)
    ((:auto "rm -r target/") :block :confirm :non-root-recursive-delete))
  "((READER INPUT) OLD NEW D-78-ITEM) for every input whose level changed.")

(defun %safety-migration-classify (reader input classify level)
  (funcall level
           (funcall classify
                    (ecase reader
                      (:bare
                       (let ((parsed (nshell.domain.parsing:parse-command-line input)))
                         (unless (nshell.domain.parsing:parse-complete-p parsed)
                           (error "corpus input does not parse: ~S" input))
                         (nshell.domain.parsing:parse-result-ast parsed)))
                      (:sexp
                       (nshell.domain.parsing:read-submission input :reader-context :sexp))
                      (:auto
                       (nshell.domain.parsing:read-submission input :reader-context :auto))))))

(defun %safety-migration-differences ()
  (loop for entry in +safety-migration-corpus+
        for old = (%safety-migration-classify
                   (first entry) (second entry)
                   #'nshell/test-legacy-safety:classify-ast
                   #'nshell/test-legacy-safety:assistant-safety-result-classification)
        for new = (%safety-migration-classify
                   (first entry) (second entry)
                   #'nshell.feature.assistant:classify-ast
                   #'nshell.feature.assistant:assistant-safety-result-classification)
        unless (eq old new)
          collect (list entry old new)))

(describe "safety rule migration (P1-5)"
  (it "compares a non-empty corpus that covers every reader"
    (expect (> (length +safety-migration-corpus+) 150) :to-be-truthy)
    (expect (sort (remove-duplicates (mapcar #'first +safety-migration-corpus+))
                  #'string<)
            :to-equal '(:auto :bare :sexp))
    (expect (length (remove-duplicates +safety-migration-corpus+ :test #'equal))
            :to-equal (length +safety-migration-corpus+)))

  (it "changes only the levels D-78 decided"
    (expect (%safety-migration-differences)
            :to-equal
            (mapcar (lambda (difference) (subseq difference 0 3))
                    (sort (copy-list +safety-migration-intended-differences+)
                          #'<
                          :key (lambda (difference)
                                 (position (first difference)
                                           +safety-migration-corpus+
                                           :test #'equal))))))

  (it "keeps the root recursive delete blocked under both classifiers"
    (dolist (input '("rm -rf /" "rm -fr /*" "rm -R ~" "rm -R $HOME" "rm -fr ."))
      (expect (%safety-migration-classify
               :bare input
               #'nshell.feature.assistant:classify-ast
               #'nshell.feature.assistant:assistant-safety-result-classification)
              :to-be :block))))
