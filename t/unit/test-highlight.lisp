(in-package #:nshell/test)

(defun %highlight-span-role-at (spans position)
  (nshell.presentation:highlight-span-role
   (find-if (lambda (span)
              (and (<= (nshell.presentation:highlight-span-start span) position)
                   (< position (nshell.presentation:highlight-span-end span))))
            spans)))

(defun %highlight-first-role (input)
  (nshell.presentation:highlight-span-role
   (first (nshell.presentation:highlight-line input))))

(defun %constant-resolver (kind)
  (lambda (name) (declare (ignore name)) kind))

(defun %constant-path-exists-p (result)
  (lambda (path) (declare (ignore path)) result))

(describe "highlight-role-tests"
  (it "highlight-unknown-command-is-error"
    "A first word the resolver cannot place is highlighted as an error."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver nil)))
      (expect :error :to-be (%highlight-first-role "nosuchcmd arg"))))

  (it "highlight-known-builtin-is-builtin"
    "A first word the resolver reports as :builtin gets the :builtin role."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver :builtin)))
      (expect :builtin :to-be (%highlight-first-role "echo hi"))))

  (it "highlight-known-function-is-function-role"
    "Resolver kinds :function, :alias, and :abbreviation all map to :function."
    (dolist (kind '(:function :alias :abbreviation))
      (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver kind)))
        (expect :function :to-be (%highlight-first-role "mytool")))))

  (it "highlight-external-command-is-command"
    "A first word the resolver reports as :external is highlighted as :command."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver :external)))
      (expect :command :to-be (%highlight-first-role "ls -la"))))

  (it "highlight-keyword-resolver-result-is-keyword"
    "A first word the resolver reports as :keyword gets the :keyword role."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver :keyword)))
      (expect :keyword :to-be (%highlight-first-role "if true"))))

  (it "highlight-quoted-word-is-quote"
    "A quoted argument is highlighted as :quote when it is not an existing path."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver nil))
          (nshell.presentation::*highlight-path-exists-p* (%constant-path-exists-p nil)))
      (let ((spans (nshell.presentation:highlight-line "echo \"quoted\"")))
        (expect :quote :to-be (nshell.presentation:highlight-span-role (second spans))))))

  (it "highlight-dollar-word-is-variable"
    "An unquoted argument starting with $ is highlighted as :variable."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver nil))
          (nshell.presentation::*highlight-path-exists-p* (%constant-path-exists-p nil)))
      (let ((spans (nshell.presentation:highlight-line "echo $HOME")))
        (expect :variable :to-be (nshell.presentation:highlight-span-role (second spans))))))

  (it "highlight-mid-word-dollar-stays-argument"
    "$ appearing mid-word does not trigger :variable."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver nil))
          (nshell.presentation::*highlight-path-exists-p* (%constant-path-exists-p nil)))
      (let ((spans (nshell.presentation:highlight-line "echo foo$bar")))
        (expect :argument :to-be (nshell.presentation:highlight-span-role (second spans))))))

  (it "highlight-comment-span-covers-hash-to-end-of-input"
    "A # starting a fresh token position opens a comment span to end of input."
    (let* ((input "echo hi # note")
           (spans (nshell.presentation:highlight-line input))
           (comment-span (find :comment spans :key #'nshell.presentation:highlight-span-role)))
      (expect (null comment-span) :to-be-falsy)
      (expect (search "#" input) :to-equal (nshell.presentation:highlight-span-start comment-span))
      (expect (length input) :to-equal (nshell.presentation:highlight-span-end comment-span))))

  (it "highlight-hash-mid-word-is-not-a-comment"
    "A # embedded inside a word does not open a comment span."
    (let* ((input "echo foo#bar")
           (spans (nshell.presentation:highlight-line input)))
      (expect (find :comment spans :key #'nshell.presentation:highlight-span-role) :to-be-null)))

  (it "highlight-existing-path-argument-is-path"
    "A non-first word resolving to an existing path is highlighted as :path."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver nil))
          (nshell.presentation::*highlight-path-exists-p* (%constant-path-exists-p t)))
      (let ((spans (nshell.presentation:highlight-line "ls /tmp")))
        (expect :path :to-be (nshell.presentation:highlight-span-role (second spans))))))

  (it "highlight-glob-argument-is-not-checked-for-a-path"
    "A word containing a glob character stays :argument even when paths resolve."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver nil))
          (nshell.presentation::*highlight-path-exists-p* (%constant-path-exists-p t)))
      (let ((spans (nshell.presentation:highlight-line "ls *.txt")))
        (expect :argument :to-be (nshell.presentation:highlight-span-role (second spans))))))

  (it "highlight-assignment-word-is-not-an-error"
    "A leading FOO=bar assignment word is a variable assignment, never an error."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver nil)))
      (expect :variable :to-be (%highlight-first-role "FOO=bar"))))

  (it "highlight-path-like-first-word-checks-probe-file"
    "An unresolved first word starting with ./ falls back to a path check."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver nil))
          (nshell.presentation::*highlight-path-exists-p*
            (%constant-path-exists-p t)))
      (expect :command :to-be (%highlight-first-role "./run.sh"))))

  (it "highlight-path-like-first-word-errors-when-unresolvable"
    "An unresolved first word starting with ./ that does not exist is :error."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver nil))
          (nshell.presentation::*highlight-path-exists-p*
            (%constant-path-exists-p nil)))
      (expect :error :to-be (%highlight-first-role "./run.sh"))))

  (it "highlight-nil-resolver-keeps-every-first-word-as-command"
    "With no resolver installed, every first word stays :command."
    (let ((nshell.presentation::*highlight-command-resolver* nil))
      (dolist (input (quote ("ls" "if" "./run.sh" "/bin/sh" "nosuchcmd" "$EDITOR")))
        (expect :command :to-be (%highlight-first-role input)))
      (expect :variable :to-be (%highlight-first-role "FOO=bar"))))

  (it "highlight-line-classifies-a-mixed-command-line"
    "A representative line mixes error, quote, variable, path, and comment roles."
    (let ((nshell.presentation::*highlight-command-resolver* (%constant-resolver nil))
          (nshell.presentation::*highlight-path-exists-p*
            (lambda (path) (string= path "/tmp"))))
      (let* ((input "nosuchcmd \"quoted\" $HOME /tmp # note")
             (spans (nshell.presentation:highlight-line input)))
        (expect :error :to-be (%highlight-span-role-at spans 0))
        (expect :quote :to-be (%highlight-span-role-at spans (search "quoted" input)))
        (expect :variable :to-be (%highlight-span-role-at spans (search "$HOME" input)))
        (expect :path :to-be (%highlight-span-role-at spans (search "/tmp" input)))
        (expect :comment :to-be (%highlight-span-role-at spans (search "# note" input)))))))

(describe "highlight-ansi-render-tests"
  (it "highlight-ansi-emits-one-reset-per-colored-span-and-none-for-empty"
    "highlight->ansi colors the command word once and leaves a plain word bare."
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* :truecolor)
          (nshell.presentation::*highlight-command-resolver* nil)
          (nshell.presentation::*highlight-path-exists-p* (%constant-path-exists-p nil)))
      (let* ((input "echo hi")
             (theme (nshell.domain.configuration:default-theme))
             (rendered (nshell.presentation:highlight->ansi
                        (nshell.presentation:highlight-line input) input theme)))
        (expect (concatenate 'string (esc-sequence "[1;38;2;95;175;255m") "echo"
                              (esc-sequence "[0m") " hi")
                :to-equal rendered)))))

(describe "repl-command-kind-tests"
  (it "repl-command-kind-recognizes-shell-keywords"
    "Control-flow words classify as :keyword before any table lookup."
    (with-repl-test-state
      (expect :keyword :to-be (nshell.presentation::%repl-command-kind "if"))
      (expect :keyword :to-be (nshell.presentation::%repl-command-kind "function"))))

  (it "repl-command-kind-recognizes-registered-builtins"
    "A name in the builtin registry classifies as :builtin."
    (with-repl-test-state
      (expect :builtin :to-be (nshell.presentation::%repl-command-kind "echo"))))

  (it "repl-command-kind-recognizes-session-tables"
    "Function, alias, and abbreviation session tables classify their entries."
    (with-repl-test-state
      (repl-test-define-function "myfun" '("echo hi"))
      (repl-test-define-alias "myalias" "echo hi")
      (setf (gethash "myabbr" nshell.presentation::*abbreviations*) "echo hi")
      (expect :function :to-be (nshell.presentation::%repl-command-kind "myfun"))
      (expect :alias :to-be (nshell.presentation::%repl-command-kind "myalias"))
      (expect :abbreviation :to-be (nshell.presentation::%repl-command-kind "myabbr"))))

  (it "repl-command-kind-tolerates-nil-tables"
    "A NIL session table is treated as empty rather than signalling."
    (let ((nshell.presentation::*functions* nil)
          (nshell.presentation::*aliases* nil)
          (nshell.presentation::*abbreviations* nil)
          (nshell.presentation::*environment* nil))
      (expect nil :to-be (nshell.presentation::%repl-command-kind "nosuchcmd"))))

  (it "repl-command-kind-finds-an-executable-on-path"
    "A name resolvable through the session's PATH classifies as :external."
    (let ((directory (format nil "/tmp/nshell-highlight-path-test-~d" (get-universal-time))))
      (unwind-protect
           (progn
             (ensure-directories-exist (concatenate 'string directory "/"))
             (let ((program-path (concatenate 'string directory "/mytool")))
               (with-open-file (stream program-path :direction :output
                                       :if-exists :supersede :if-does-not-exist :create)
                 (write-line "#!/bin/sh" stream))
               (sb-posix:chmod program-path #o700)
               (with-repl-test-state
                 (repl-test-set-env "PATH" directory)
                 (expect :external :to-be (nshell.presentation::%repl-command-kind "mytool"))
                 (expect nil :to-be (nshell.presentation::%repl-command-kind "nosuchtool")))))
        (when (probe-file directory)
          (host-kit:delete-directory-tree directory :if-does-not-exist :ignore))))))

(describe "repl-command-correction-tests"
  (it "edit-distance-within-one-covers-every-single-edit"
    (flet ((near (a b) (nshell.presentation::%edit-distance-within-one-p a b)))
      (expect (near "git" "gti") :to-be-truthy)
      (expect (near "git" "gi") :to-be-truthy)
      (expect (near "git" "gitt") :to-be-truthy)
      (expect (near "git" "got") :to-be-truthy)
      (expect (near "git" "git") :to-be-truthy)
      (expect (near "git" "grep") :to-be-falsy)
      (expect (near "echo" "ecoh") :to-be-truthy)
      (expect (near "echo" "eco") :to-be-truthy)
      (expect (near "echo" "chose") :to-be-falsy)
      (expect (near "" "a") :to-be-truthy)))

  (it "command-corrections-propose-builtins-one-edit-away"
    (with-repl-test-state
      (expect (member "echo" (nshell.presentation::%repl-command-corrections "ehco")
                      :test #'string=)
              :to-be-truthy)
      (expect (member "pwd" (nshell.presentation::%repl-command-corrections "pdw")
                      :test #'string=)
              :to-be-truthy)
      (expect (member "echo" (nshell.presentation::%repl-command-corrections "ECHO")
                      :test #'string=)
              :to-be-truthy)))

  (it "command-corrections-cover-keywords-and-session-tables"
    (with-repl-test-state
      (repl-test-define-alias "deploy" "echo deploying")
      (expect (member "deploy" (nshell.presentation::%repl-command-corrections "deploz")
                      :test #'string=)
              :to-be-truthy)
      (expect (member "while" (nshell.presentation::%repl-command-corrections "whle")
                      :test #'string=)
              :to-be-truthy)))

  (it "command-corrections-stay-empty-far-from-any-command"
    (let ((nshell.presentation::*functions* nil)
          (nshell.presentation::*aliases* nil)
          (nshell.presentation::*abbreviations* nil)
          (nshell.presentation::*environment* nil))
      (expect (nshell.presentation::%repl-command-corrections "zzqqxxjj") :to-be-null)
      (expect (nshell.presentation::%repl-command-corrections "") :to-be-null)))

  (it "command-corrections-return-at-most-three-names"
    (with-repl-test-state
      (expect (>= 3 (length (nshell.presentation::%repl-command-corrections "sit")))
              :to-be-truthy))))

(describe "highlight-path-probe-cache-tests"
  (it "repeated-probes-of-the-same-word-hit-the-cache"
    "Highlighting reclassifies the whole line per keystroke, so the same word
must not be stat-ed twice in a row."
    (let ((probes 0))
      (setf nshell.presentation::*highlight-path-probe-cache-stamp* nil)
      (with-rebound-function (nshell.presentation::%path-exists-on-disk-p
                              (lambda (path) (declare (ignore path)) (incf probes) nil))
        (nshell.presentation::%highlight-probe-path "/tmp/whatever")
        (nshell.presentation::%highlight-probe-path "/tmp/whatever")
        (expect 1 :to-equal probes))))

  (it "an-expired-cache-probes-again"
    (let ((probes 0))
      (setf nshell.presentation::*highlight-path-probe-cache-stamp* nil)
      (with-rebound-function (nshell.presentation::%path-exists-on-disk-p
                              (lambda (path) (declare (ignore path)) (incf probes) nil))
        (nshell.presentation::%highlight-probe-path "/tmp/whatever")
        (setf nshell.presentation::*highlight-path-probe-cache-stamp*
              (cons (car nshell.presentation::*highlight-path-probe-cache-stamp*) 0))
        (nshell.presentation::%highlight-probe-path "/tmp/whatever")
        (expect 2 :to-equal probes)))))
