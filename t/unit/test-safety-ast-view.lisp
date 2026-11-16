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
        "ls '>' out" "FOO+=x ls" "(^git branch \"2>&1\")"
        "(^and ls)" "(^or ls)" "(^not ls)")
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
  ;; (%assistant-classify-reader-result passes :READER).
  (multiple-value-bind (argv names words writes problems results redirects resolution)
      (nshell.feature.assistant::%assistant-command-parts
       node (if (eq path :reader) :reader :bare-line))
    (declare (ignore words writes problems results redirects))
    (list names argv resolution)))

(defun %safety-view-bare-resolution (context node)
  ;; %execute-command-by-name-in-context runs a function or a registered
  ;; builtin in this process and anything else as an external command.
  (if (nshell.application::%shell-internal-command-p context node) :builtin :external))

(defun %safety-view-executor (context path node)
  "The names, command words, and resolution (builtin or external) the
executor's own functions give NODE.  The expansion of assignment values is
stubbed so no substitution runs."
  (flet ((names (words)
           (mapcar (lambda (word)
                     (car (nshell.application::%assignment-word-binding context word)))
                   words)))
    (let ((assignment-only (nshell.domain.parsing:command-node-assignment-words node)))
      (cond
        ;; Both executors run an assignment-only line as assignments
        ;; (execute-command-node-in-context, %reader-execute-foreground-in-context).
        (assignment-only (list (names assignment-only) nil nil))
        ((eq path :bare-line)
         (multiple-value-bind (assignments rest)
             (nshell.application::%split-prefix-assignments context node)
           (let ((clean (and rest
                             (nshell.domain.parsing:command-redirect-split-result-clean-command
                              (nshell.application::%extract-command-redirects rest)))))
             (list (mapcar #'car assignments)
                   (and clean
                        (cons (nshell.domain.parsing:command-node-command clean)
                              (nshell.domain.parsing:command-node-arg-values clean)))
                   (and clean (%safety-view-bare-resolution context clean))))))
        ;; A reader stage keeps its assignments in their own slot and runs its
        ;; command word with its arguments (evaluate-command-stage-in-context).
        (t
         (list (names (mapcar #'nshell.domain.parsing:arg-value
                              (nshell.domain.parsing:command-node-environment-assignments
                               node)))
               (cons (nshell.domain.parsing:command-node-command node)
                     (nshell.domain.parsing:command-node-arg-values node))
               (handler-case
                   (nth-value 0 (nshell.application::%resolve-command-stage-binding
                                 context node))
                 (error () :unresolved))))))))

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

  (it "agrees on the assigned names, the command words, and the resolution"
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

;;; The gate classifies the node of a stage the executor is about to run: the
;;; expanded node on the bare-line path (%assistant-gate-expanded-node) and
;;; the evaluated reader stage on the reader path (%reader-gate-command-node).
;;; What the classifier sees there must equal what that stage runs.

(defun %safety-view-reader-stage (context node)
  "Evaluate the reader stage NODE as the reader executor does, or NIL when
its evaluation fails (then nothing runs)."
  (handler-case (nshell.application:evaluate-command-stage-in-context context node)
    (error () nil)))

(defun %safety-view-normal-redirects (redirects)
  (mapcar (lambda (redirect)
            (if (consp redirect)
                (let ((target (cdr redirect)))
                  (list (car redirect)
                        (if (nshell.domain.parsing:redirect-fd-dup-target-p target)
                            (list (nshell.domain.parsing:redirect-fd-dup-target-source target)
                                  (nshell.domain.parsing:redirect-fd-dup-target-target target))
                            target)))
                (list (nshell.domain.parsing:ast-redirect-entry-kind redirect)
                      (nshell.domain.parsing:ast-redirect-entry-source-order redirect))))
          redirects))

(defun %safety-view-gate-classifier (gate)
  "Run GATE (a thunk calling the real gate) and return the names, command
words, redirects, and resolution of the outermost command the classifier
split."
  (let ((original (symbol-function 'nshell.feature.assistant::%assistant-command-parts))
        (seen nil)
        (depth 0))
    (with-temporary-function
        ('nshell.feature.assistant::%assistant-command-parts
         (lambda (&rest arguments)
           ;; Keep the outermost call: splitting a node classifies its
           ;; process substitutions first.
           (let ((parts (progn
                          (incf depth)
                          (unwind-protect (multiple-value-list (apply original arguments))
                            (decf depth)))))
             (unless (or seen (plusp depth)) (setf seen parts))
             (values-list parts))))
      (let ((nshell.application:*execution-origin* :proposal)
            (nshell.application:*execution-approval* :confirm)
            (nshell.application::*execution-gate-parent-kind* nil)
            (nshell.application:*execution-gate-stopped-p* nil))
        (funcall gate)))
    (and seen
         (list (second seen) (first seen)
               (%safety-view-normal-redirects (seventh seen))
               (eighth seen)))))

(defun %safety-view-gate-pair (context path node)
  "Return (CLASSIFIER EXECUTOR) views of the stage NODE at the gate, or NIL
when the executor dispatches no stage for it."
  (unless (nshell.domain.parsing:command-node-assignment-words node)
    (if (eq path :bare-line)
        (multiple-value-bind (assignments rest)
            (nshell.application::%split-prefix-assignments context node)
          (declare (ignore assignments))
          ;; %expand-command-node-in-context with the identity expansion.
          (let* ((expanded (nshell.domain.parsing:make-command-node
                            (nshell.domain.parsing:command-node-command rest)
                            (mapcar #'nshell.domain.parsing:make-command-arg
                                    (nshell.domain.parsing:command-node-arg-values rest))))
                 (split (nshell.application::%extract-command-redirects expanded))
                 (clean (nshell.domain.parsing:command-redirect-split-result-clean-command
                         split)))
            (list (%safety-view-gate-classifier
                   (lambda ()
                     (nshell.application::%assistant-gate-expanded-node context expanded)))
                  (list nil
                        (cons (nshell.domain.parsing:command-node-command clean)
                              (nshell.domain.parsing:command-node-arg-values clean))
                        (%safety-view-normal-redirects
                         (nshell.domain.parsing:command-redirect-split-result-redirects
                          split))
                        (%safety-view-bare-resolution context clean)))))
        (let ((stage (%safety-view-reader-stage context node)))
          (when stage
            (let ((command (nshell.application:evaluated-command-stage-command-node stage)))
              (list (%safety-view-gate-classifier
                     (lambda ()
                       (nshell.application::%reader-assistant-gate
                        context
                        (list (nshell.application::%reader-gate-command-node context stage))
                        nil)))
                    (list (mapcar #'car
                                  (nshell.application:evaluated-command-stage-environment-assignments
                                   stage))
                          (cons (nshell.domain.parsing:command-node-command command)
                                (nshell.application::command-argv-strings
                                 context
                                 (nshell.application:evaluated-command-stage-arguments stage)))
                          (%safety-view-normal-redirects
                           (nshell.domain.parsing:command-node-redirects command))
                          (nshell.application:evaluated-command-stage-dispatch-kind
                           stage)))))))))

(describe "safety classifier sees a stage at the gate as the executor runs it"
  (it "agrees on the names, command words, redirects, and resolution of every gated stage"
    (let ((context (make-test-shell-context))
          (compared 0))
      (with-temporary-function
          ('nshell.application::%expand-source-arg-in-context
           (lambda (context arg &optional environment)
             (declare (ignore context environment))
             (list (nshell.domain.parsing:arg-value arg))))
        (dolist (case (%safety-view-cases))
          (destructuring-bind (label path node) case
            (let ((pair (%safety-view-gate-pair context path node)))
              (when pair
                (incf compared)
                (expect (list label (first pair))
                        :to-equal (list label (second pair))))))))
      (expect (> compared 250) :to-be-truthy)))

  (it "confirms a reader stage whose argument only looks like a redirect"
    ;; The reader executor passes "2>&1" to git as a branch name.
    (let* ((context (make-test-shell-context))
           (result (first (nshell.domain.parsing:read-submission
                           "(^git branch \"2>&1\")" :reader-context :auto)))
           (node (nshell.domain.parsing:command-form->ast
                  (nshell.domain.parsing:reader-result-source result)
                  (nshell.domain.parsing:reader-result-form result)
                  (nshell.domain.parsing:reader-result-form-span-map result)
                  (lambda (head-source)
                    (declare (ignore head-source))
                    :command-island)))
           (stage (nshell.application:evaluate-command-stage-in-context context node)))
      (let ((nshell.application:*execution-origin* :proposal)
            (nshell.application:*execution-approval* :safe)
            (nshell.application::*execution-gate-parent-kind* nil)
            (nshell.application:*execution-gate-stopped-p* nil))
        (expect (second
                 (nshell.application::%reader-assistant-gate
                  context
                  (list (nshell.application::%reader-gate-command-node context stage))
                  nil))
                :to-equal 126)))))
