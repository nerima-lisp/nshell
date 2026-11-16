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
       node (if (eq path :reader) :reader :bare-line)
       (nshell.application:assistant-command-resolver (make-test-shell-context)))
    (declare (ignore words writes problems results redirects))
    (list names argv resolution)))

(defun %safety-view-bare-resolution (context node)
  ;; %execute-command-by-name-in-context runs what this resolution names.
  (%safety-view-kind
   (nshell.application::%resolve-command-by-name
    context (nshell.domain.parsing:command-node-command node))))

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
                   (%safety-view-kind
                    (nth-value 0 (nshell.application::%resolve-command-stage-binding
                                  context node)))
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
                       (nshell.application::%reader-gate-evaluated-stages
                        context (list stage) nil)))
                    (list (mapcar #'car
                                  (nshell.application:evaluated-command-stage-environment-assignments
                                   stage))
                          (cons (nshell.domain.parsing:command-node-command command)
                                (nshell.application::command-argv-strings
                                 context
                                 (nshell.application:evaluated-command-stage-arguments stage)))
                          (%safety-view-normal-redirects
                           (nshell.domain.parsing:command-node-redirects command))
                          (%safety-view-kind
                           (nshell.application:evaluated-command-stage-dispatch-kind
                            stage))))))))))

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
                 (nshell.application::%reader-gate-evaluated-stages
                  context (list stage) nil))
                :to-equal 3)))))

;;; R-P1-5: the executor runs a registered shell function or an alias before
;;; the builtin or external command of that name.  The classifier at Enter,
;;; the gate, and the executor must resolve a command the same way, because
;;; they all ask the executor's own resolution functions.

(defun %safety-view-register-function (context name ran)
  "Register a shell function NAME in CONTEXT that records its call in RAN."
  (nshell.application::register-shell-function
   (nshell.application:context-shell-function-registry context)
   name
   (nshell.application:make-shell-function-binding
    (lambda (&rest arguments)
      (declare (ignore arguments))
      (push name (car ran))
      (values nil 0))
    nil name nil nil)))

(defun %safety-view-run-ai-line (context source reader-context approval)
  "Run SOURCE as an AI line approved at APPROVAL; return its status and
whether the gate stopped it."
  (let ((nshell.application:*execution-origin* :proposal)
        (nshell.application:*execution-approval* approval)
        (nshell.application:*execution-gate-stopped-p* nil)
        (status nil))
    (capture-standard-output
      (let ((*error-output* (make-string-output-stream)))
        (dolist (result (nshell.domain.parsing:read-submission
                         source :reader-context reader-context))
          (setf status
                (nth-value 1 (nshell.presentation:call-with-command-failure-restarts
                              (lambda ()
                                (nshell.application:evaluate-reader-result-in-context
                                 context result))))))))
    (values status nshell.application:*execution-gate-stopped-p*)))

(describe "safety classifier resolves commands with the executor"
  (it "does not run a shell function named echo on a safe approval"
    (dolist (reader-context '(:bare-line :sexp))
      (let* ((context (make-test-shell-context))
             (ran (list nil))
             (source (if (eq reader-context :sexp) "(echo hi)" "echo hi")))
        (%safety-view-register-function context "echo" ran)
        (multiple-value-bind (status stopped-p)
            (%safety-view-run-ai-line context source reader-context :safe)
          (expect (list source status stopped-p (car ran))
                  :to-equal (list source 3 t nil))))))

  (it "does not run a shell function named echo on a safe approval on the AST path"
    (let ((context (make-test-shell-context))
          (ran (list nil)))
      (%safety-view-register-function context "echo" ran)
      (let ((nshell.application:*execution-origin* :proposal)
            (nshell.application:*execution-approval* :safe)
            (nshell.application:*execution-gate-stopped-p* nil))
        (multiple-value-bind (output code)
            (nshell.application:execute-ast-in-context
             context (nshell.domain.parsing:make-command-node "echo" '("hi")))
          (declare (ignore output))
          (expect (list code nshell.application:*execution-gate-stopped-p* (car ran))
                  :to-equal (list 3 t nil)))))))

(defparameter +safety-view-resolution-sources+
  '((:bare "echo hi") (:bare "ls -la") (:bare "git status") (:bare "not ls")
    (:bare "command echo x") (:bare "ls | cat")
    (:auto "echo hi") (:auto "ls -la") (:auto "git status") (:auto "not ls")
    (:auto "(echo hi)") (:auto "(ls)") (:auto "(^ls)") (:auto "(git status)")
    (:auto "ls | cat"))
  "Inputs whose command names a shell function or an alias in some context.")

(defun %safety-view-write-function-file (directory name marker)
  "Write the autoloadable function file NAME.nsh under DIRECTORY's
nshell/functions/.  Evaluating it writes MARKER and defines NAME."
  (let ((path (merge-pathnames (format nil "nshell/functions/~a.nsh" name) directory)))
    (ensure-directories-exist path)
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (format stream "(CL:WITH-OPEN-FILE (S ~S :DIRECTION :OUTPUT :IF-EXISTS :APPEND :IF-DOES-NOT-EXIST :CREATE) (CL:WRITE-LINE ~S S))~%(defun ~a () \"autoload-body\")~%"
              (namestring marker) name name))
    path))

(defun %safety-view-call-restoring-user-functions (names thunk)
  "Call THUNK, then restore the NSHELL.USER definitions of NAMES: a loaded
function file defines its function there for the whole image."
  (let ((saved (mapcar (lambda (name)
                         (let ((symbol (find-symbol name "NSHELL.USER")))
                           (list name
                                 symbol
                                 (and symbol (fboundp symbol) (symbol-function symbol)))))
                       ;; The reader keeps the case of the name.
                       (remove-duplicates
                        (append names (mapcar #'string-upcase names))
                        :test #'string=))))
    (unwind-protect (funcall thunk)
      (loop for (name symbol function) in saved
            for current = (find-symbol name "NSHELL.USER")
            do (cond
                 ((null symbol) (when current (unintern current "NSHELL.USER")))
                 (function (setf (symbol-function symbol) function))
                 (t (fmakunbound symbol)))))))

(defun %safety-view-autoload-context (directory)
  "A context whose function directory is DIRECTORY/nshell/functions/."
  (let ((context (make-test-shell-context)))
    (setf (nshell.application:shell-context-environment context)
          (nshell.domain.environment:env-set
           (nshell.application:shell-context-environment context)
           "XDG_CONFIG_HOME" (namestring directory) t))
    context))

(defun %safety-view-registered-count (context)
  (hash-table-count
   (nshell.application::shell-function-registry-global-table
    (nshell.application:context-shell-function-registry context))))

(defun %safety-view-resolution-contexts (&optional directory)
  "Return (LABEL CONTEXT) pairs: nothing defined, shell functions named
echo, ls, and git, aliases of those names to other commands, and, with
DIRECTORY, autoloadable function files named echo and ls."
  (list* (list :plain (make-test-shell-context))
        (list :functions
              (let ((context (make-test-shell-context)))
                (dolist (name '("echo" "ls" "git") context)
                  (%safety-view-register-function context name (list nil)))))
        (list :aliases
              (let ((context (make-test-shell-context)))
                ;; Each alias runs a command of another resolution.
                (loop for (name . text) in '(("echo" . "ls -la")
                                             ("ls" . "echo aliased")
                                             ("git" . "not ls"))
                      do (setf (gethash name (nshell.application:shell-context-alias-table
                                              context))
                               text))
                context))
        (and directory
             (list (list :autoload
                         (progn
                           (dolist (name '("echo" "ls"))
                             (%safety-view-write-function-file
                              directory name (merge-pathnames "loaded" directory)))
                           (%safety-view-autoload-context directory)))))))

(defun %safety-view-kind (kind)
  (case kind
    ((:builtin :external) kind)
    ((nil) nil)
    (t :function)))

(defun %safety-view-recorded-resolutions (thunk)
  "Call THUNK and return the resolution of every outermost command the
classifier split meanwhile.  The node an alias expands to is classified
right after its alias and is not counted again."
  (let ((original (symbol-function 'nshell.feature.assistant::%assistant-command-parts))
        (depth 0)
        (skip nil)
        (seen nil))
    (with-temporary-function
        ('nshell.feature.assistant::%assistant-command-parts
         (lambda (&rest arguments)
           (let ((parts (progn
                          (incf depth)
                          (unwind-protect (multiple-value-list (apply original arguments))
                            (decf depth)))))
             (when (zerop depth)
               (if skip
                   (setf skip nil)
                   (push (eighth parts) seen))
               (when (ninth parts) (setf skip t)))
             (values-list parts))))
      (let ((nshell.application:*execution-origin* :proposal)
            (nshell.application:*execution-approval* :confirm)
            (nshell.application::*execution-gate-parent-kind* nil)
            (nshell.application:*execution-gate-stopped-p* nil))
        (funcall thunk)))
    (nreverse seen)))

(defun %safety-view-resolution-triple (context reader source)
  "Return the resolutions of SOURCE's commands as the classifier at Enter,
the gate, and the executor see them."
  (let ((resolve (nshell.application::assistant-command-resolver context)))
    (if (eq reader :bare)
        (let* ((ast (nshell.domain.parsing:parse-result-ast
                     (nshell.domain.parsing:parse-command-line source)))
               (nodes (%safety-view-command-nodes ast)))
          (list (%safety-view-recorded-resolutions
                 (lambda ()
                   (nshell.feature.assistant:classify-ast ast :resolve resolve)))
                (%safety-view-recorded-resolutions
                 (lambda () (nshell.application::%assistant-execution-gate context ast)))
                ;; %expand-command-node-in-context expands the alias, then
                ;; %execute-command-by-name-in-context resolves the name.
                (mapcar (lambda (node)
                          (let ((run (nshell.application:expand-command-alias-node
                                      node
                                      (nshell.application:shell-context-alias-table
                                       context))))
                            (%safety-view-kind
                             (nshell.application::%resolve-command-by-name
                              context (nshell.domain.parsing:command-node-command run)))))
                        nodes)))
        (let* ((results (nshell.domain.parsing:read-submission
                         source :reader-context :auto))
               (nodes (%safety-view-reader-nodes source :auto))
               (stages (mapcar (lambda (node)
                                 (nshell.application:evaluate-command-stage-in-context
                                  context node))
                               nodes)))
          (list (%safety-view-recorded-resolutions
                 (lambda ()
                   (nshell.feature.assistant:classify-ast results :resolve resolve)))
                (%safety-view-recorded-resolutions
                 (lambda ()
                   (nshell.application::%reader-gate-evaluated-stages
                    context stages nil)))
                (mapcar (lambda (stage)
                          (%safety-view-kind
                           (nshell.application:evaluated-command-stage-dispatch-kind
                            stage)))
                        stages))))))

(describe "safety classifier, gate, and executor resolve a command alike"
  (it "agrees with shell functions, aliases, and function files defined"
    ;; The classifier and the gate see a function file as a shell function
    ;; without loading it; the executor loads it and runs the function.
    (host-kit:with-temporary-directory (directory)
     (%safety-view-call-restoring-user-functions
      '("echo" "ls")
      (lambda ()
     (let ((compared 0))
      (dolist (entry (%safety-view-resolution-contexts directory))
        (destructuring-bind (label context) entry
          (dolist (input +safety-view-resolution-sources+)
            (destructuring-bind (reader source) input
              (destructuring-bind (enter gate executor)
                  (%safety-view-resolution-triple context reader source)
                (incf compared)
                (expect (list label reader source enter gate)
                        :to-equal (list label reader source executor executor)))))))
      (expect compared :to-equal 60)))))))

(describe "safety classification loads no function file"
  (it "leaves function files unread at Enter, at the gate, and for the rerun check"
    (host-kit:with-temporary-directory (directory)
      (let ((marker (merge-pathnames "loaded" directory)))
        (%safety-view-write-function-file directory "echo" marker)
        ;; Enter and the rerun check classify in the REPL context.
        (with-repl-test-state
          (let ((nshell.presentation::*environment*
                  (nshell.domain.environment:env-set
                   (nshell.domain.environment:make-environment)
                   "XDG_CONFIG_HOME" (namestring directory) t))
                (nshell.presentation::*functions* (make-hash-table :test #'equal)))
            (expect (nshell.presentation::%assistant-proposal-level "echo hi")
                    :to-be :confirm)
            (expect (getf (nshell.presentation::%rerun-command-assessment "echo hi")
                          :classification)
                    :to-be :confirm)
            (expect (%safety-view-registered-count
                     (nshell.presentation::%make-repl-shell-context))
                    :to-equal 0)))
        ;; The gate classifies the line just before it runs.
        (let ((context (%safety-view-autoload-context directory)))
          (let ((nshell.application:*execution-origin* :proposal)
                (nshell.application:*execution-approval* :safe)
                (nshell.application::*execution-gate-parent-kind* nil)
                (nshell.application:*execution-gate-stopped-p* nil))
            (expect (second (nshell.application::%assistant-execution-gate
                             context
                             (nshell.domain.parsing:make-command-node "echo" '("hi"))))
                    :to-equal 3))
          (expect (%safety-view-registered-count context) :to-equal 0))
        (expect (probe-file marker) :to-be nil))))

  (it "lets the executor load and run the function after a confirm approval"
    (host-kit:with-temporary-directory (directory)
     (%safety-view-call-restoring-user-functions
      '("echo")
      (lambda ()
      (let ((marker (merge-pathnames "loaded" directory)))
        (%safety-view-write-function-file directory "echo" marker)
        (let ((context (%safety-view-autoload-context directory)))
          ;; A safe approval stops at the gate: nothing is loaded.
          (let ((nshell.application:*execution-origin* :proposal)
                (nshell.application:*execution-approval* :safe)
                (nshell.application:*execution-gate-stopped-p* nil))
            (expect (nth-value 1 (nshell.application:execute-ast-in-context
                                  context
                                  (nshell.domain.parsing:make-command-node "echo" nil)))
                    :to-equal 3)
            (expect (probe-file marker) :to-be nil))
          ;; A confirm approval passes the gate; then the executor loads the
          ;; file and runs the function it defines.
          (let ((nshell.application:*execution-origin* :proposal)
                (nshell.application:*execution-approval* :confirm)
                (nshell.application:*execution-gate-stopped-p* nil))
            (nshell.application:execute-ast-in-context
             context (nshell.domain.parsing:make-command-node "echo" nil))
            (expect nshell.application:*execution-gate-stopped-p* :to-be nil))
          (expect (and (probe-file marker) t) :to-be t)
          (expect (%safety-view-registered-count context) :to-equal 1))))))))
