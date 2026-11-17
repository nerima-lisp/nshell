(in-package #:nshell/test)

;;; v0.8 rejects the bare-line builtins and, or, not, break, continue and
;;; function with E_UNSUPPORTED_SYNTAX before any of the input runs, showing
;;; the equivalent S-expression (language/L5-bare-line.md 5.3, L7 7.2), and
;;; removes count, contains, seq, math, prevd, nextd and pipeline-graph (P2-6).

(defparameter +unsupported-syntax-cases+
  '(("not false" "not" 1 "(not (false))")
    ("true; and echo yes" "and" 7 "(and (true) (echo yes))")
    ("false; or echo yes" "or" 8 "(or (false) (echo yes))")
    ("break" "break" 1 "(return)")
    ("continue" "continue" 1
     "restructure the loop body with (when …) or (unless …)")
    ("function greet; echo hi; end" "function" 1 "(defcmd greet () (echo hi))"))
  "(INPUT HEAD COLUMN TEXT): INPUT is rejected at the HEAD that starts at
COLUMN of its line, with a message holding TEXT, its rewrite or advice.")

(defun %unsupported-occurrences (needle text)
  (loop with start = 0
        for position = (search needle text :start2 start)
        while position
        count t
        do (setf start (+ position (length needle)))))

(defun %unsupported-read (input)
  "Read INPUT with READ-SUBMISSION and return the UNSUPPORTED-SYNTAX-ERROR it
signals, or :ACCEPTED."
  (handler-case (progn (nshell.domain.parsing:read-submission input) :accepted)
    (nshell.domain.parsing:unsupported-syntax-error (condition) condition)))

(defun %unsupported-finding (input)
  (let ((result (%unsupported-read input)))
    (if (eq result :accepted)
        :accepted
        (list (nshell.domain.error-codes:condition-error-code result)
              (nshell.domain.parsing:unsupported-syntax-error-head result)
              (nshell.domain.parsing:sexp-reader-error-source-span result)
              (nshell.domain.parsing:unsupported-syntax-error-rewrite result)))))

(defun %unsupported-repl-run (buffer)
  "Submit BUFFER at the REPL prompt. Return its output (error stream
included) and the exit status it leaves."
  (with-repl-test-state
    (with-stable-repl-prompt ()
      (with-fixed-terminal-size (24 80)
        (with-repl-input-state (:buffer buffer :cursor-pos (length buffer))
          (let ((output
                  (capture-standard-output
                    (let ((*error-output* *standard-output*))
                      (let ((continuation
                              (nshell.presentation::process-output-event :execute)))
                        (when continuation
                          (funcall continuation)))))))
            (values output nshell.presentation::*last-exit-code*)))))))

(defun %unsupported-bin-directory (directory names)
  "Write an executable script for each of NAMES into DIRECTORY that prints
external-NAME and its arguments."
  (dolist (name names directory)
    (let ((path (merge-pathnames name directory)))
      (with-open-file (stream path :direction :output :if-exists :supersede)
        (format stream "#!/bin/sh~%echo external-~a \"$@\"~%" name))
      (sb-posix:chmod (namestring path) #o755))))

(describe "unsupported bare-line syntax: reader"
  (it "rejects each removed builtin at its head with its L5.3 rewrite"
    (dolist (case +unsupported-syntax-cases+)
      (destructuring-bind (input head column text) case
        (let ((condition (%unsupported-read input)))
          (expect (list input
                        (nshell.domain.error-codes:condition-error-code condition)
                        (nshell.domain.parsing:unsupported-syntax-error-head condition)
                        (first (nshell.domain.parsing:sexp-reader-error-source-span
                                condition))
                        (%unsupported-occurrences text (princ-to-string condition))
                        (%unsupported-occurrences "E_UNSUPPORTED_SYNTAX"
                                                  (princ-to-string condition)))
                  :to-equal (list input "E_UNSUPPORTED_SYNTAX" head (1- column) 1 1))))))

  (it "builds the rewrite from the commands around the head"
    (dolist (case '(("not false; and echo not-and" "(and (not (false)) (echo not-and))")
                    ("true; and not false" "(and (true) (not (false)))")
                    ("a; and b; or c" "(or (and (a) (b)) (c))")
                    ("not grep x | wc -l" "(not (grep x | wc -l))")
                    ;; && and || bind tighter than ; (L5.1) and fold from the left.
                    ("a && b; and c" "(and (and (a) (b)) (c))")
                    ("a || b; or c" "(or (or (a) (b)) (c))")
                    ("a || b; and c" "(and (or (a) (b)) (c))")
                    ("a; and b && c" "(and (and (a) (b)) (c))")
                    ("a; or b || c" "(or (or (a) (b)) (c))")
                    ("a && not b" "(and (a) (not (b)))")
                    ("a || not b" "(or (a) (not (b)))")
                    ("not a && b" "(and (not (a)) (b))")
                    ("a && b || not c" "(or (and (a) (b)) (not (c)))")
                    ("a && not b; or c" "(or (and (a) (not (b))) (c))")
                    ;; fish runs a; and b || c as a; and (b || c), v0.7.0 as
                    ;; (a; and b) || c; and and or after && or ||, or a list run
                    ;; in the background, have no S-expression: the generic form.
                    ("a; and b || c" "(and (cmd1) (cmd2))")
                    ("a; or b && c" "(or (cmd1) (cmd2))")
                    ("a && and b" "(and (cmd1) (cmd2))")
                    ("a || or b" "(or (cmd1) (cmd2))")
                    ("a & and b" "(and (cmd1) (cmd2))")
                    ("a; and b &" "(and (cmd1) (cmd2))")
                    ("a && not b &" "(not (cmd))")
                    ("echo pre; function f; echo hi; end; f" "(defcmd f () (echo hi))")
                    ("function f" "(defcmd f () …)")
                    ;; The name is the first word that is neither an option nor
                    ;; the value of one; with none, the generic form.
                    ("function -d desc greet; echo hi; end" "(defcmd greet () (echo hi))")
                    ("function greet -d desc" "(defcmd greet () …)")
                    ("function --description desc greet" "(defcmd greet () …)")
                    ("function --description=desc greet" "(defcmd greet () …)")
                    ("function -ddesc greet" "(defcmd greet () …)")
                    ("function -Sd desc greet" "(defcmd greet () …)")
                    ("function -S greet" "(defcmd greet () …)")
                    ("function -a x -w ls -e e -v v -j 1 -p 2 -s INT -V y greet"
                     "(defcmd greet () …)")
                    ("function --argument-names x --wraps ls --on-event e --on-variable v --on-job-exit 1 --on-process-exit 2 --on-signal INT --inherit-variable y greet"
                     "(defcmd greet () …)")
                    ("function -- -greet" "(defcmd -greet () …)")
                    ("function -e greet" "(defcmd f () …)")
                    ("function -d desc; echo hi; end" "(defcmd f () …)")
                    ("function --" "(defcmd f () …)")
                    ("and echo x" "(and (cmd1) (cmd2))")
                    ("echo x | not cat" "(not (cmd))")
                    ;; Each further not wraps the command it negates.
                    ("not not true" "(not (not (true)))")
                    ("true; and not not false" "(and (true) (not (not (false))))")
                    ("not not grep x | wc -l" "(not (not (grep x | wc -l)))")
                    ;; No command name follows the head: the generic form.
                    ("not" "(not (cmd))")
                    ("not <<< x" "(not (cmd))")
                    ("not > out cmd" "(not (cmd))")
                    ("true; and <<< x" "(and (cmd1) (cmd2))")))
      (destructuring-bind (input rewrite) case
        (expect (list input (fourth (%unsupported-finding input)))
                :to-equal (list input rewrite)))))

  (it "reads a line continuation in the rewrite as one space"
    (let ((input (format nil "echo line1 \\~%  more; and echo z")))
      (expect (fourth (%unsupported-finding input))
              :to-equal "(and (echo line1 more) (echo z))")))

  (it "reads a line continuation in a script's rewrite as one space"
    (multiple-value-bind (status output error-output)
        (%crash-cause-run-script (format nil "echo line1 \\~%  more; and echo z~%"))
      (expect status :to-equal 2)
      (expect output :to-equal "")
      (expect (search "use (and (echo line1 more) (echo z))" error-output)
              :to-be-truthy)))

  (it "finds the head inside command and process substitutions"
    (expect (%unsupported-finding "echo $(not true)")
            :to-equal '("E_UNSUPPORTED_SYNTAX" "not" (7 10) "(not (true))"))
    (expect (%unsupported-finding "echo \"$(echo $(break))\"")
            :to-equal '("E_UNSUPPORTED_SYNTAX" "break" (15 20) "(return)"))
    (expect (%unsupported-finding "cat <(not ls)")
            :to-equal '("E_UNSUPPORTED_SYNTAX" "not" (6 9) "(not (ls))")))

  (it "accepts the names where they are not a bare-line command head"
    (dolist (input '("(not (false))" "(and (true) (echo x))" "(or (false) (echo x))"
                     "(function car)" "(if (not (false)) (echo yes))"
                     "echo not and or break continue function"
                     "echo '$(not true)'" "^not x" "'and' x" "\"break\""
                     "echo $((1 + 2))" "alias x='not false'"
                     "count a b" "contains a b" "seq 3" "math 1+2"
                     "prevd" "nextd" "pipeline-graph 'a | b'"))
      (expect (list input (%unsupported-read input)) :to-equal (list input :accepted)))))

(describe "unsupported bare-line syntax: entry points"
  (it "rejects the input at the REPL with exit status 2 before running any of it"
    (host-kit:with-temporary-directory (directory)
      (dolist (case +unsupported-syntax-cases+)
        (destructuring-bind (input head column text) case
          (declare (ignore head))
          (let* ((marker (namestring (merge-pathnames "ran" directory)))
                 (prefix (format nil "echo ran > ~a; " marker))
                 (buffer (concatenate 'string prefix input)))
            (multiple-value-bind (output status) (%unsupported-repl-run buffer)
              (expect (list input
                            status
                            (%unsupported-occurrences "E_UNSUPPORTED_SYNTAX" output)
                            (%unsupported-occurrences text output)
                            (%unsupported-occurrences
                             (format nil "<input>:1:~d:" (+ (length prefix) column))
                             output)
                            (probe-file marker))
                      :to-equal (list input 2 1 1 1 nil))))))))

  (it "reports E_UNSUPPORTED_SYNTAX with status 2 in a --json run"
    (host-kit:with-temporary-directory (directory)
      (dolist (case +unsupported-syntax-cases+)
        (destructuring-bind (input head column text) case
          (declare (ignore head column))
          (let ((marker (namestring (merge-pathnames "ran" directory))))
            (multiple-value-bind (envelope status)
                (json-command (format nil "echo ran > ~a; ~a" marker input))
              (expect (list input
                            status
                            (json-at envelope "error" "code")
                            (%unsupported-occurrences
                             text (or (json-at envelope "error" "message") ""))
                            (json-at envelope "stdout" "text")
                            (probe-file marker))
                      :to-equal (list input 2 "E_UNSUPPORTED_SYNTAX" 1 "" nil))))))))

  (it "rejects a script with exit status 2 and FILE:LINE:COLUMN before its first line runs"
    (host-kit:with-temporary-directory (directory)
      (dolist (case +unsupported-syntax-cases+)
        (destructuring-bind (input head column text) case
          (declare (ignore head))
          (let ((marker (namestring (merge-pathnames "ran" directory))))
            (multiple-value-bind (status output error-output crash-logs)
                (%crash-cause-run-script (format nil "echo ran > ~a~%~a~%" marker input))
              (expect (list input
                            status
                            output
                            (%unsupported-occurrences "E_UNSUPPORTED_SYNTAX" error-output)
                            (%unsupported-occurrences text error-output)
                            (%unsupported-occurrences
                             (format nil "case.nsh:2:~d:" column) error-output)
                            crash-logs
                            (probe-file marker))
                      :to-equal (list input 2 "" 1 1 1 0 nil)))))))))

(describe "unsupported bare-line syntax: names defined another way"
  (it "rejects a removed head even when an alias of that name exists"
    (multiple-value-bind (status output error-output)
        (%crash-cause-run-script (format nil "alias not='echo aliased'~%not~%"))
      (expect status :to-equal 2)
      (expect output :to-equal "")
      (expect (search "E_UNSUPPORTED_SYNTAX" error-output) :to-be-truthy)))

  (it "runs a removed builtin name that a defun defines"
    (multiple-value-bind (status output error-output)
        (%crash-cause-run-script
         (format nil "(defun count () (echo my-count))~%count~%"))
      (expect (list status output error-output)
              :to-equal (list 0 (format nil "my-count~%") ""))))

  (it "keeps and and not as Lisp forms in S-expressions"
    ;; As in v0.7.0 (probes not-cmd and and-in-if); what a direct command
    ;; returns in test position is S3's (probes and-cmd, or-cmd).
    (multiple-value-bind (status output error-output)
        (%crash-cause-run-script
         (format nil "(if (not (false)) (echo not-ok))~%(if (and (true) (true)) (echo both))~%"))
      (expect (list status output error-output)
              :to-equal (list 0 (format nil "not-ok~%both~%") ""))))

  (it "runs an external program for a removed name but still rejects and"
    (host-kit:with-temporary-directory (bin)
      (%unsupported-bin-directory bin '("count" "seq" "prevd" "and"))
      (multiple-value-bind (status output error-output)
          (%crash-cause-run-script (format nil "count a b~%seq 3~%prevd~%")
                                   :path-directory bin)
        (expect (list status output error-output)
                :to-equal (list 0
                                (format nil "external-count a b~%external-seq 3~%external-prevd~%")
                                "")))
      (multiple-value-bind (status output error-output)
          (%crash-cause-run-script (format nil "and x~%") :path-directory bin)
        (expect status :to-equal 2)
        (expect output :to-equal "")
        (expect (search "E_UNSUPPORTED_SYNTAX" error-output) :to-be-truthy))))

  (it "reports a removed name with no program of that name as not found"
    (host-kit:with-temporary-directory (empty-bin)
      (dolist (name '("count" "contains" "seq" "math" "prevd" "nextd" "pipeline-graph"))
        (multiple-value-bind (status output error-output)
            (%crash-cause-run-script (format nil "~a~%" name) :path-directory empty-bin)
          (expect (list name status output
                        (and (search (format nil "~a: command not found" name)
                                     error-output)
                             t))
                  :to-equal (list name 127 "" t)))))))
