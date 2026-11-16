(in-package #:nshell/test)

;;; The safety classifier must see a command the way the executor runs it
;;; (D-P1-5 2.1 item 5, R-P1-5).  For every command node of the inputs below,
;;; the names the classifier says are assigned and the command words it
;;; judges must equal the ones the executor's own functions produce.  A
;;; classifier that starts to guess shell structure from strings again (an
;;; `=' in a word, a `>' in a word) makes these lists differ.

(defparameter +safety-view-rp15-sources+
  (list "env GIT_EXTERNAL_DIFF=/tmp/helper git diff HEAD~1 HEAD"
        "env FOO+=x ls" "env LANG+=C ls" "env 1=x ls" "env '=x' ls"
        "rg --hostname-bin=/tmp/helper needle" "file -C -m magic x"
        "/usr/bin/time -o FILE ls" "ls | xargs git diff"
        "find -- . -name a -delete" "git log --format=%G?"
        "printf '\\e]52;c;aGk=\\a'" "nohup ls" "sudo sh -c 'rm -rf /'"
        "rm -rf --no-preserve-root /./"
        "\"LANG=C\"" "'LANG=C'" "LANG=C \"TZ=UTC\"" "(^LANG=C)"
        "(^LANG=C \"TZ=UTC\")" "eval 'PATH=/tmp/x'" "eval 'TZ=UTC'"
        "PATH=/tmp/x" "TZ=UTC" "LANG=C"
        "(^LANG=C ls)" "\"LANG=C\" ls" "'LANG=C' cat" "LANG=C \"TZ=UTC\" ls"
        "LANG=C ls" "LANG=C TZ=UTC ls > /dev/null" "FOO=1 \"BAR=2\" ls"
        "ls '>' out" "FOO+=x ls")
  "Inputs R-P1-5 used, read with every reader that accepts them.")

(defun %safety-view-command-nodes (ast)
  (cond
    ((nshell.domain.parsing:command-node-p ast) (list ast))
    ((nshell.domain.parsing:pipeline-node-p ast)
     (mapcan #'%safety-view-command-nodes
             (nshell.domain.parsing:pipeline-node-commands ast)))
    ((nshell.domain.parsing:sequence-node-p ast)
     (mapcan #'%safety-view-command-nodes
             (nshell.domain.parsing:sequence-node-commands ast)))
    (t nil)))

(defun %safety-view-reader-nodes (source reader-context)
  "Return the command nodes the reader path runs for SOURCE, or :UNREAD."
  (handler-case
      (mapcan
       (lambda (result)
         (let ((form (nshell.domain.parsing:reader-result-form result)))
           (%safety-view-command-nodes
            (if (consp form)
                (nshell.domain.parsing:command-form->ast
                 (nshell.domain.parsing:reader-result-source result)
                 form
                 (nshell.domain.parsing:reader-result-form-span-map result)
                 (lambda (head-source)
                   (declare (ignore head-source))
                   :command-island))
                form))))
       (nshell.domain.parsing:read-submission source :reader-context reader-context))
    (error () :unread)))

(defun %safety-view-cases ()
  "Return (LABEL PATH NODE) for every command node of the inputs.  PATH is
:BARE-LINE for nodes run by execute-command-node-in-context and :READER for
nodes run as reader stages."
  (let ((cases nil))
    (flet ((add-bare (source)
             (let ((parsed (nshell.domain.parsing:parse-command-line source)))
               (when (nshell.domain.parsing:parse-complete-p parsed)
                 (dolist (node (%safety-view-command-nodes
                                (nshell.domain.parsing:parse-result-ast parsed)))
                   (push (list (list :bare source) :bare-line node) cases)))))
           (add-reader (source reader-context)
             (let ((nodes (%safety-view-reader-nodes source reader-context)))
               (unless (eq nodes :unread)
                 (dolist (node nodes)
                   (push (list (list reader-context source) :reader node) cases))))))
      (dolist (entry +safety-migration-corpus+)
        (destructuring-bind (reader source) entry
          (if (eq reader :bare)
              (add-bare source)
              (add-reader source reader))))
      (dolist (source +safety-view-rp15-sources+)
        (add-bare source)
        (add-reader source :auto)))
    (nreverse cases)))

(defun %safety-view-classifier (path node)
  ;; The classifier reads a reader result's form as a reader stage
  ;; (%assistant-classify-reader-result binds the same variable).
  (let ((nshell.feature.assistant::*assistant-reader-stage-p* (eq path :reader)))
    (multiple-value-bind (argv names)
        (nshell.feature.assistant::%assistant-command-parts node)
      (list names argv))))

(defun %safety-view-executor (context path node)
  "The names and command words the executor's own functions give NODE.  The
expansion of assignment values is stubbed so no substitution runs."
  (flet ((names (words)
           (mapcar (lambda (word)
                     (car (nshell.application::%assignment-word-binding context word)))
                   words)))
    (let ((assignment-only (nshell.domain.parsing:command-node-assignment-words node)))
      (cond
        ;; Both executors run an assignment-only line as assignments
        ;; (execute-command-node-in-context, %reader-execute-foreground-in-context).
        (assignment-only (list (names assignment-only) nil))
        ((eq path :bare-line)
         (multiple-value-bind (assignments rest)
             (nshell.application::%split-prefix-assignments context node)
           (list (mapcar #'car assignments)
                 (and rest
                      (let ((clean (nshell.domain.parsing:command-redirect-split-result-clean-command
                                    (nshell.application::%extract-command-redirects rest))))
                        (cons (nshell.domain.parsing:command-node-command clean)
                              (nshell.domain.parsing:command-node-arg-values clean)))))))
        ;; A reader stage keeps its assignments in their own slot and runs its
        ;; command word with its arguments (evaluate-command-stage-in-context).
        (t
         (list (names (mapcar #'nshell.domain.parsing:arg-value
                              (nshell.domain.parsing:command-node-environment-assignments
                               node)))
               (cons (nshell.domain.parsing:command-node-command node)
                     (nshell.domain.parsing:command-node-arg-values node))))))))

(describe "safety classifier sees commands as the executor runs them"
  (it "compares a corpus that covers both execution paths and the R-P1-5 inputs"
    (let ((cases (%safety-view-cases)))
      (expect (> (length cases) 250) :to-be-truthy)
      (expect (and (find :bare-line cases :key #'second)
                   (find :reader cases :key #'second)
                   t)
              :to-be-truthy)
      (dolist (source +safety-view-rp15-sources+)
        (expect (list source
                      (and (find source cases :key (lambda (case) (second (first case)))
                                              :test #'string=)
                           t))
                :to-equal (list source t)))))

  (it "agrees on the assigned names and the command words"
    (let ((context (make-test-shell-context)))
      (with-temporary-function
          ('nshell.application::%expand-source-arg-in-context
           (lambda (context arg &optional environment)
             (declare (ignore context environment))
             (list (nshell.domain.parsing:arg-value arg))))
        (dolist (case (%safety-view-cases))
          (destructuring-bind (label path node) case
            (expect (list label (%safety-view-classifier path node))
                    :to-equal (list label (%safety-view-executor context path node)))))))))
