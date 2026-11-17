(in-package #:nshell.feature.assistant)

;;; Safety classification of command ASTs.  This file only reads the AST: it
;;; finds the command a wrapper, eval, or sh -c runs and the commands inside
;;; substitutions, and describes each command to the knowledge base.  The
;;; decision is the classify/4 rule data in packages/feature/kb.

(defstruct (assistant-safety-result
            (:constructor make-assistant-safety-result
                (&key classification reason command rule-name reasons)))
  classification
  reason
  command
  rule-name
  ;; Every (RULE . TEXT) at CLASSIFICATION; RULE-NAME and REASON are the first.
  reasons)

(defun %assistant-command-basename (command)
  (let ((separator (position (code-char 47) command :from-end t)))
    (if separator (subseq command (1+ separator)) command)))

(defvar *assistant-subject-visitor* nil
  "NIL, or a function the walk calls with each subject it describes to the
knowledge base and whether the subject is a command the line runs.")

(defvar *assistant-subject-runs-p* t
  "False while the walk describes a subject the line does not run: a query
target of command -v, or a command named in the operands of an unknown one.")

(defun %assistant-subject-result (command &rest subject)
  (when *assistant-subject-visitor*
    (funcall *assistant-subject-visitor* subject *assistant-subject-runs-p*))
  (multiple-value-bind (level reasons)
      (apply #'nshell.feature.kb:classify-subject subject)
    (make-assistant-safety-result
     :classification level
     :command command
     :rule-name (car (first reasons))
     :reason (cdr (first reasons))
     :reasons reasons)))

(defun %assistant-unparsable-result (text)
  (%assistant-subject-result nil :unparsable (list text)))

(defun %assistant-unclassifiable-result (text)
  (%assistant-subject-result nil :unclassifiable (list text)))

(defun %assistant-result-reasons (result)
  "Return RESULT's reasons as (LEVEL RULE TEXT) for an enclosing subject."
  (mapcar (lambda (reason)
            (list (assistant-safety-result-classification result)
                  (car reason)
                  (cdr reason)))
          (assistant-safety-result-reasons result)))

(defun %assistant-most-restrictive-result (results)
  (if results
      (let* ((merged (%assistant-subject-result
                      nil
                      :nested (mapcan #'%assistant-result-reasons results)))
             (winner (find (assistant-safety-result-classification merged)
                           results
                           :key #'assistant-safety-result-classification)))
        (setf (assistant-safety-result-command merged)
              (and winner (assistant-safety-result-command winner)))
        merged)
      (%assistant-unparsable-result
       "an empty compound command cannot be classified safely")))

;;; Commands a wrapper runs stay argv lists and are classified by recursion.
;;; Only text that is itself a command line is read again, with the reader
;;; that runs it (D-P1-5 2.1 item 5): sh -c SCRIPT, eval with one argument,
;;; and the bodies of substitutions.
;;;
;;; PATH names the executor that runs a node:
;;;   :BARE-LINE  the AST executor on a node it has not expanded yet: it
;;;               splits the NAME=value prefix, expands an alias, then
;;;               resolves the name (execute-command-node-in-context);
;;;   :STAGE      the AST executor on a node it dispatches now by name
;;;               (%execute-command-by-name-in-context): no prefix, no alias;
;;;   :READER     a reader stage (evaluate-command-stage-in-context).
;;; RESOLVE is NIL or a function of a command node and PATH that returns how
;;; the executor resolves the command and the node it then runs (different
;;; after an alias expansion).  The caller builds it from the shell context
;;; the command runs in, with the executor's own resolution functions.  The
;;; kinds are the executor's: :BUILTIN, :EXTERNAL, and anything else (a shell
;;; function, a source function, a sexp alias) runs code the line does not
;;; show.  Without RESOLVE every command counts as external.

(defun %assistant-resolution-kind (kind)
  "Map an executor dispatch kind to the classifier's :BUILTIN, :EXTERNAL, or
:FUNCTION."
  (case kind
    ((:builtin :external) kind)
    (t :function)))

(defun %assistant-resolve (node path resolve)
  "Return the classifier's resolution of NODE's command on PATH and the node
the executor runs instead of NODE, or NIL when it runs NODE itself."
  (if resolve
      (multiple-value-bind (kind run-node) (funcall resolve node path)
        (values (%assistant-resolution-kind kind)
                (and run-node
                     (not (eq run-node node))
                     (not (and (equal (nshell.domain.parsing:command-node-command run-node)
                                      (nshell.domain.parsing:command-node-command node))
                               (equal (nshell.domain.parsing:command-node-arg-values
                                       run-node)
                                      (nshell.domain.parsing:command-node-arg-values
                                       node))))
                     run-node)))
      (values :external nil)))

(defun %assistant-name-resolution (words resolve)
  "The resolution of the command argv WORDS names when a builtin runs it by
name (and, or, not, command, builtin)."
  (values (%assistant-resolve (nshell.domain.parsing:make-command-node
                               (first words) (rest words))
                              :stage resolve)))

(defun %assistant-classify-command-line (text resolve)
  "Classify TEXT as a bare command line: the reader of eval, sh -c, and
process substitutions."
  (let ((parsed (nshell.domain.parsing:parse-command-line text)))
    (if (nshell.domain.parsing:parse-complete-p parsed)
        (%assistant-classify-node (nshell.domain.parsing:parse-result-ast parsed)
                                  :bare-line resolve)
        (%assistant-unparsable-result "the wrapped command could not be parsed"))))

(defun %assistant-classify-substitution-text (text resolve)
  "Classify TEXT as a command substitution runs it: one bare line is parsed
as a command line, anything else goes through the auto reader
(execute-command-substitution.lisp)."
  (let* ((scan (nshell.domain.parsing:scan-input text :reader-context :auto))
         (complete-p (eq (nshell.domain.parsing:scan-result-status scan) :complete))
         (first-token
           (and complete-p
                (find-if-not (lambda (token)
                               (member (nshell.domain.parsing:scan-token-kind token)
                                       '(:whitespace :line-comment :block-comment)))
                             (nshell.domain.parsing:scan-result-tokens scan)))))
    (cond
      ((not complete-p)
       (%assistant-unparsable-result
        "an incomplete command substitution cannot be classified safely"))
      ((and first-token
            (not (find #\Newline text))
            (eq (nshell.domain.parsing:scan-token-reader-context first-token)
                :bare-line))
       (%assistant-classify-command-line text resolve))
      (t
       (handler-case
           (%assistant-classify-node (nshell.domain.parsing:read-submission
                                      text :reader-context :auto)
                                     :reader resolve)
         (error ()
           (%assistant-unparsable-result
            "the command substitution could not be read")))))))

(defparameter +assistant-substitution-markers+
  '(("$(" . :substitution) ("(" . :substitution)
    ("<(" . :command-line) (">(" . :command-line))
  "Substitution openers and the reader their body runs with.")

(defun %assistant-substituted-word-p (word)
  "True when WORD holds a substitution the walk reads as a command."
  (some (lambda (entry)
          (nshell.domain.parsing:parenthesized-substitution-texts word (car entry)))
        +assistant-substitution-markers+))

(defun %assistant-substitution-results (words resolve &optional inert-words)
  "Classify the substitutions in WORDS.  Those in INERT-WORDS, members of
WORDS that the executor passes on without expanding, are judged as a
precaution but do not run."
  (loop with runs-p = *assistant-subject-runs-p*
        for word in words
        nconc (let ((*assistant-subject-runs-p*
                      (and runs-p (not (member word inert-words :test #'eq)))))
                (loop for (marker . reader) in +assistant-substitution-markers+
                      nconc (mapcar
                             (lambda (text)
                               (cond
                                 ((eq text :incomplete)
                                  (%assistant-unparsable-result
                                   "an incomplete command substitution cannot be classified safely"))
                                 ((eq reader :command-line)
                                  (%assistant-classify-command-line text resolve))
                                 (t (%assistant-classify-substitution-text text resolve))))
                             (nshell.domain.parsing:parenthesized-substitution-texts
                              word marker))))))

(defun %assistant-embedded-command-result (args resolve)
  "Classify the operands from the first word that names a command able to
change the system.  The rules use it only for commands they do not know,
so an unknown wrapper such as `nohup-like rm -rf /' stays blocked."
  (loop for tail on args
        when (member (%assistant-command-basename (first tail))
                     '("rm" "mkfs" "dd" "chmod" "git" "curl" "wget"
                       "sh" "bash" "zsh" "fish")
                     :test #'string=)
          return (%assistant-classify-argv
                  tail
                  :resolve resolve
                  :resolution (%assistant-name-resolution tail resolve))))

(defun %assistant-query-argument-expands-p (argument source-arguments-p resolve)
  "Detect source query expansions without enumerating brace results.
Unquoted ( uses the shared substitution scanner as a deliberately broad check.
Outside single quotes, an unescaped $ or backtick conservatively requires confirmation."
  (when (and argument
             (or source-arguments-p
                 (nshell.domain.parsing:command-arg-expand-p argument)))
    (some
     (lambda (fragment)
       (let ((style (nshell.domain.parsing:command-fragment-quote-style fragment))
             (value (copy-seq (nshell.domain.parsing:command-fragment-value fragment))))
         (dolist (position (nshell.domain.parsing:command-fragment-escaped-positions fragment))
           (when (< position (length value))
             (setf (char value position) #\Null)))
         (and (not (eq style :single))
              (or (and (null style)
                       (nshell.domain.parsing:parenthesized-substitution-texts value "("))
                  (position #\$ value)
                  (position #\` value)
                  (and (or (null style) (not source-arguments-p))
                       (or (nshell.domain.expansion:brace-expansion-p value)
                           (funcall resolve
                                    (nshell.domain.parsing:make-command-node value nil)
                                    :query-tilde)
                           (and (nshell.domain.parsing:command-arg-glob-p argument)
                                (nshell.domain.expansion:glob-pattern-p value))))))))
     (nshell.domain.parsing:command-arg-fragments argument))))

(defun %assistant-classify-argv (words &key resolution resolve assignments nested
                                           writes redirect-problems raw-words
                                           argument-nodes argument-forms source-arguments-p)
  "Classify the command the argv WORDS run.  RESOLUTION is how the executor
resolves its command word (:BUILTIN, :EXTERNAL, or :FUNCTION).  ASSIGNMENTS
are the environment names assigned before it and NESTED the reasons of its
substitutions.  WRITES, REDIRECT-PROBLEMS, and RAW-WORDS describe the
redirects and the written words of the outermost command."
  (let ((command (first words))
        (args (rest words)))
    (multiple-value-bind (kind inner mismatches names env-options source runs
                          query-options)
        (nshell.feature.kb:command-wrapper command args resolution)
      (let ((wrapped (cond
                      (source (%assistant-classify-command-line source resolve))
                      (inner (%assistant-classify-argv
                              inner
                              :resolve resolve
                              :source-arguments-p source-arguments-p
                              :argument-forms (nthcdr (- (length words) (length inner))
                                                     argument-forms)
                              :argument-nodes (nthcdr (- (length words) (length inner))
                                                     argument-nodes)
                              :resolution (if (eq runs :by-name)
                                              (%assistant-name-resolution inner resolve)
                                              :external)))))
            (embedded (unless kind
                        (let ((*assistant-subject-runs-p* nil))
                          (%assistant-embedded-command-result args resolve))))
            (queries
             (when query-options
               (let ((*assistant-subject-runs-p* nil))
                 (if (some #'nshell.domain.parsing:command-value-form-p argument-forms)
                     (list (%assistant-subject-result
                            command :command command
                            :wrapper-mismatches (list "query target requires expansion")))
                     (let ((targets args)
                           (target-nodes argument-nodes))
                       (loop while (member (first targets) query-options :test #'equal)
                             do (pop targets) (pop target-nodes))
                       (when (equal (first targets) "--")
                         (pop targets) (pop target-nodes))
                       (loop for name in targets
                             for argument = (pop target-nodes)
                             when (%assistant-query-argument-expands-p argument source-arguments-p resolve)
                             collect (%assistant-subject-result
                                      name :command name
                                      :wrapper-mismatches
                                      (list (format nil "query target requires expansion: ~a" name)))
                             else when (nth-value 2
                                       (funcall resolve
                                                (nshell.domain.parsing:make-command-node name nil)
                                                :query))
                             collect (%assistant-subject-result
                                      name :command name :invoked-as name
                                      :resolution :function))))))))
        (%assistant-subject-result
         command
         :command (%assistant-command-basename command)
         :invoked-as command
         :resolution resolution
         :arguments args
         :substituted-arguments (remove-if-not #'%assistant-substituted-word-p args)
         :wraps (and kind t)
         :opaque (eq kind :opaque)
         :wrapper-mismatches mismatches
         :assignments (append assignments names)
         :wrapper-options env-options
         :writes writes
         :redirect-problems redirect-problems
         :words raw-words
         :nested (append (and wrapped (%assistant-result-reasons wrapped))
                         (mapcan #'%assistant-result-reasons queries) nested)
         :embedded (and embedded (%assistant-result-reasons embedded)))))))

(defparameter +assistant-output-redirect-kinds+
  '(:> :>> :&> :&>> :2> :2>>
    :output-file :append-output-file :force-output-file :error-file
    :append-error-file :both-output-files :append-both-output-files)
  "Redirect kinds that write a file: bare-line kinds from ast-redirect-split
and reader kinds from ast-redirect-entry.")

(defun %assistant-redirects (split-redirects entries path resolve)
  "Describe the redirects of one command (D-P1-5 2.5).  SPLIT-REDIRECTS are
the (KIND . TARGET) pairs of ast-redirect-split and ENTRIES the reader's
ast-redirect-entry values.  Return the output targets, a text for each
redirect outside the safe forms, the texts whose substitutions are judged
(targets, here-document bodies, here-strings), the results of the process
substitutions, read on PATH, and the members of those texts that do not run:
the bodies of quoted here-documents (<<'EOF'), which the executor passes on
as written."
  (let ((writes nil)
        (problems nil)
        (texts nil)
        (inert nil)
        (results nil))
    (labels ((output (kind target)
               (push target writes)
               (unless (string= target "/dev/null")
                 (push (format nil "~(~a~) ~a" kind target) problems)))
             (duplicate (source target)
               ;; 2>&1, 1>&2, and >&2 only; a closed or other descriptor is
               ;; outside the safe forms.
               (unless (member (list source target) '((1 2) (2 1)) :test #'equal)
                 (push (format nil "~a>&~a" source (or target "-")) problems))))
      (dolist (redirect split-redirects)
        (destructuring-bind (kind . target) redirect
          (cond
            ((member kind +assistant-output-redirect-kinds+) (output kind target))
            ((member kind '(:2>&1 :< :<< :<<- :<<<)))
            ((and (eq kind :fd-dup)
                  (nshell.domain.parsing:redirect-fd-dup-target-p target))
             (when (eq (nshell.domain.parsing:redirect-fd-dup-target-operator target)
                       :output)
               (let ((destination
                       (nshell.domain.parsing:redirect-fd-dup-target-target target)))
                 (duplicate (nshell.domain.parsing:redirect-fd-dup-target-source target)
                            (and (integerp destination) destination)))))
            (t (push (format nil "~(~a~)" kind) problems)))))
      (dolist (entry entries)
        (let ((kind (nshell.domain.parsing:ast-redirect-entry-kind entry))
              (target (nshell.domain.parsing:ast-redirect-entry-target entry)))
          (cond
            ((nshell.domain.parsing:redirect-procsub-target-p target)
             (push (%assistant-classify-node
                    (nshell.domain.parsing:redirect-procsub-target-form target)
                    path resolve)
                   results)
             (when (eq (nshell.domain.parsing:redirect-procsub-target-direction target)
                       :output)
               (push "process substitution >(...)" problems)))
            ((nshell.domain.parsing:redirect-heredoc-target-p target)
             (let ((body (nshell.domain.parsing:redirect-heredoc-target-body target)))
               (push body texts)
               (unless (nshell.domain.parsing:redirect-heredoc-target-expand-p target)
                 (push body inert))))
            ((eq kind :duplicate-output-fd)
             (duplicate (nshell.domain.parsing:ast-redirect-entry-file-descriptor entry)
                        (and (nshell.domain.parsing:redirect-fd-target-p target)
                             (nshell.domain.parsing:redirect-fd-target-file-descriptor
                              target))))
            ((eq kind :duplicate-input-fd))
            ((nshell.domain.parsing:command-arg-p target)
             (let ((value (nshell.domain.parsing:command-arg-value target)))
               (push value texts)
               (when (member kind +assistant-output-redirect-kinds+)
                 (output kind value))))
            (t (push (format nil "~(~a~)" kind) problems)))))
      (values (nreverse writes) (nreverse problems) (nreverse texts)
              (nreverse results) inert))))

(defun %assistant-command-parts (node path resolve)
  "Split a command NODE the way the executor on PATH splits it (see PATH
above).  Assignments come from command-node-assignment-words (a line that
runs no command) or, on the :BARE-LINE path, split-command-node-assignments
(a prefix), plus the node's own assignment slot.  Redirects come from the
node's redirect entries and, off the :READER path, from ast-redirect-split
of the command that remains, as in %execute-plain-command-node-in-context.
Return the argv of that command without its redirects (NIL when the line
runs no command), the assigned names, the words as written (redirect
targets, here-document bodies, and assignments included), the output
targets, the redirect problems, the results of its process substitution
redirects, the redirects used, the command's resolution by RESOLVE
(:BUILTIN, :EXTERNAL, or :FUNCTION), and the node the executor runs
instead (after an alias), or NIL, the typed arguments, the argument forms, and
the words whose substitutions do not run (quoted here-document bodies)."
  (let* ((reader-p (eq path :reader))
         (reader-assignments
           (mapcar #'nshell.domain.parsing:arg-value
                   (nshell.domain.parsing:command-node-environment-assignments node)))
         (assignment-only (nshell.domain.parsing:command-node-assignment-words node)))
    (multiple-value-bind (prefix rest)
        (cond
          (assignment-only (values assignment-only nil))
          ((eq path :bare-line)
           (nshell.domain.parsing:split-command-node-assignments node))
          (t (values nil node)))
      (let* ((split (and rest
                         (not reader-p)
                         (nshell.domain.parsing:split-command-node-redirects rest)))
             (split-redirects
               (and split
                    (nshell.domain.parsing:command-redirect-split-result-redirects split)))
             (entries (nshell.domain.parsing:command-node-redirects node)))
        (multiple-value-bind (writes problems texts results inert-texts)
            (%assistant-redirects split-redirects entries path resolve)
          (multiple-value-bind (resolution run-node)
              (if rest (%assistant-resolve rest path resolve) (values nil nil))
            (let ((words (append (list (nshell.domain.parsing:command-node-command node))
                                 (nshell.domain.parsing:command-node-arg-values node)
                                 reader-assignments
                                 texts)))
              (values (and rest
                           (cons (nshell.domain.parsing:command-node-command rest)
                                 (nshell.domain.parsing:command-node-arg-values
                                  (if split
                                      (nshell.domain.parsing:command-redirect-split-result-clean-command
                                       split)
                                      rest))))
                      (mapcar #'nshell.feature.kb:assignment-name
                              (if assignment-only
                                  assignment-only
                                  (append reader-assignments prefix)))
                      words
                      writes
                      (if (some (lambda (word)
                                  (nshell.domain.parsing:parenthesized-substitution-texts
                                   word ">("))
                                words)
                          (append problems (list "process substitution >(...)"))
                          problems)
                      results
                      (append split-redirects entries)
                      resolution
                      run-node
                      (and rest
                           (nshell.domain.parsing:command-node-args
                            (if split
                                (nshell.domain.parsing:command-redirect-split-result-clean-command
                                 split)
                                rest)))
                      (and rest
                           (nshell.domain.parsing:command-node-argument-forms
                            (if split
                                (nshell.domain.parsing:command-redirect-split-result-clean-command
                                 split)
                                rest)))
                      inert-texts))))))))

(defun classify-command (node &key (path :bare-line) resolve
                                   (source-arguments-p (eq path :bare-line)))
  "Classify a command-node using its effective command and arguments.  PATH
and RESOLVE are as for classify-ast."
  (if (nshell.domain.parsing:command-node-p node)
      (multiple-value-bind (argv assignments words writes problems results
                            redirects resolution run-node argument-nodes argument-forms
                            inert-words)
          (%assistant-command-parts node path resolve)
        (declare (ignore redirects))
        (let ((nested (mapcan #'%assistant-result-reasons
                              (append results
                                      (%assistant-substitution-results
                                       words resolve inert-words)))))
          (cond
            ((null argv)
             (%assistant-subject-result
              nil
              :assignments assignments
              :writes writes
              :redirect-problems problems
              :words words
              :nested nested))
            (run-node
             ;; The executor runs RUN-NODE, the alias expansion, as a stage it
             ;; has resolved already; NODE contributes its own assignments,
             ;; redirects, and substitutions.
             (let ((ran (classify-command
                         run-node
                         :path (if (eq path :reader) :reader :stage)
                         :source-arguments-p source-arguments-p
                         :resolve (lambda (command-node command-path)
                                    (if (eq command-node run-node)
                                        (values resolution nil)
                                        (funcall resolve command-node command-path))))))
               (%assistant-subject-result
                (first argv)
                :command (%assistant-command-basename (first argv))
                :invoked-as (first argv)
                :wraps t
                :assignments assignments
                :writes writes
                :redirect-problems problems
                :words words
                :nested (append (%assistant-result-reasons ran) nested))))
            (t
             (%assistant-classify-argv
              argv
              :resolution resolution
              :resolve resolve
              :assignments assignments
              :writes writes
              :redirect-problems problems
              :raw-words words
              :argument-nodes argument-nodes
              :argument-forms argument-forms
              :source-arguments-p source-arguments-p
              :nested nested)))))
      (%assistant-unparsable-result "the value is not a command AST node")))

(defun command-effects (node &key (path :bare-line) resolve)
  "Return the effects of the commands NODE runs: (DELETES PATH), (WRITES PATH),
:NETWORK, and (READS PATH), each once in the order the walk meets them.  The
second value is the classify-ast result of NODE.  Both come from one walk, so
the effects are those of exactly the commands the classifier judges: the
commands in substitutions, the command a wrapper, sh -c, or eval runs, and
the node the executor runs after an alias.  A query target and a command
named in an unknown command's operands are judged but not run, so they have
no effects.  NODE, PATH, and RESOLVE are as for classify-ast; writes come from
the redirects in the AST (D-P1-5 2.5).  A visitor already bound still sees
every subject."
  (let* ((effects '())
         (outer *assistant-subject-visitor*)
         (result
           (let ((*assistant-subject-visitor*
                   (lambda (subject runs-p)
                     (when outer (funcall outer subject runs-p))
                     (when (and runs-p
                                (or (getf subject :command) (getf subject :writes)))
                       (setf effects
                             (revappend (apply #'nshell.feature.kb:subject-effects
                                               subject)
                                        effects))))))
             (classify-ast node :path path :resolve resolve))))
    (values (remove-duplicates (nreverse effects) :test #'equal :from-end t)
            result)))

(defun classify-pipeline (node &key (path :bare-line) resolve)
  "Classify a pipeline by its most restrictive stage."
  (if (nshell.domain.parsing:pipeline-node-p node)
      (%assistant-most-restrictive-result
       (mapcar (lambda (stage) (%assistant-classify-node stage path resolve))
               (nshell.domain.parsing:pipeline-node-commands node)))
      (%assistant-unparsable-result "the value is not a pipeline AST node")))

(defun %assistant-classify-sequence (node path resolve)
  (if (nshell.domain.parsing:sequence-node-p node)
      (%assistant-most-restrictive-result
       (mapcar (lambda (item) (%assistant-classify-node item path resolve))
               (nshell.domain.parsing:sequence-node-commands node)))
      (%assistant-unparsable-result "the value is not a sequence AST node")))

(defun %assistant-ast-has-redirect-p (node)
  (cond
    ((nshell.domain.parsing:command-node-p node)
     (not (null (nshell.domain.parsing:command-node-redirects node))))
    ((nshell.domain.parsing:pipeline-node-p node)
     (some #'%assistant-ast-has-redirect-p
           (nshell.domain.parsing:pipeline-node-commands node)))
    ((nshell.domain.parsing:sequence-node-p node)
     (some #'%assistant-ast-has-redirect-p
           (nshell.domain.parsing:sequence-node-commands node)))
    (t nil)))

(defun %assistant-form-result (inner &rest form-facts)
  (apply #'%assistant-subject-result
         (assistant-safety-result-command inner)
         :nested (%assistant-result-reasons inner)
         form-facts))

(defun %assistant-classify-reader-result (reader-result resolve)
  (let ((form (nshell.domain.parsing:reader-result-form reader-result)))
    (cond
      ((or (nshell.domain.parsing:command-node-p form)
           (nshell.domain.parsing:pipeline-node-p form)
           (nshell.domain.parsing:sequence-node-p form))
       (%assistant-form-result (%assistant-classify-node form :reader resolve)
                               :form-redirect
                               (%assistant-ast-has-redirect-p form)))
      ((consp form)
       (handler-case
           (let ((ast (nshell.domain.parsing:command-form->ast
                       (nshell.domain.parsing:reader-result-source reader-result)
                       form
                       (nshell.domain.parsing:reader-result-form-span-map
                        reader-result)
                       (lambda (head-source)
                         (declare (ignore head-source))
                         :command-island))))
             (%assistant-form-result
              (%assistant-classify-node ast :reader resolve)
              :sexp-unforced
              (not (and (nshell.domain.parsing:command-node-p ast)
                        (nshell.domain.parsing:command-node-force-external-p ast)
                        (not (%assistant-ast-has-redirect-p ast))
                        (ignore-errors (every #'atom form))))))
         (error ()
           (%assistant-unclassifiable-result "unclassifiable S-expression form"))))
      (t
       (%assistant-unclassifiable-result "unclassifiable S-expression form")))))

(defun %assistant-classify-node (node path resolve)
  (cond
    ((nshell.domain.parsing:reader-result-p node)
     (%assistant-classify-reader-result node resolve))
    ((and (consp node)
          (ignore-errors
            (every #'nshell.domain.parsing:reader-result-p node)))
     (%assistant-most-restrictive-result
      (mapcar (lambda (result) (%assistant-classify-reader-result result resolve))
              node)))
    ((nshell.domain.parsing:command-node-p node)
     (classify-command node :path path :resolve resolve))
    ((nshell.domain.parsing:pipeline-node-p node)
     (classify-pipeline node :path path :resolve resolve))
    ((nshell.domain.parsing:sequence-node-p node)
     (%assistant-classify-sequence node path resolve))
    ((consp node)
     (%assistant-unclassifiable-result "unclassifiable S-expression form"))
    (t (%assistant-unparsable-result "unsupported AST node"))))

(defun classify-ast (node &key (path :bare-line) resolve)
  "Classify shell AST and S-expression input using metadata and argument values.
Query expansion detection uses runtime predicates on source argument values.
Brace detection does not enumerate results.  Unquoted ( uses the shared
substitution scanner as a deliberately broad check.  Outside single quotes,
an unescaped $ or backtick conservatively requires confirmation.
PATH names the executor that runs a command, pipeline, or sequence node
(:BARE-LINE, :STAGE, or :READER, described above); reader results always
run as reader stages.  RESOLVE gives the executor's resolution of a
command in the shell context it runs in; without it every command is
external."
  (%assistant-classify-node node path resolve))
