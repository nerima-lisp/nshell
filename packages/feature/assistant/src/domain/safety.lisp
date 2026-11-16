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

(defun %assistant-subject-result (command &rest subject)
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

(defun assistant-command-after-wrappers (command args)
  "Return the effective command and arguments after known wrappers."
  (loop
    (multiple-value-bind (kind inner)
        (nshell.feature.kb:command-wrapper command args)
      (if (and kind inner)
          (setf command (first inner)
                args (rest inner))
          (return (values (%assistant-command-basename command) args))))))

(defvar *assistant-reader-stage-p* nil
  "True while classifying a node the reader path runs (a reader result's
form).  The reader executor keeps redirects and assignments in their own
slots and passes every argument word as it is; only the bare-line executor
splits a NAME=value prefix and redirect words off the words.")

(defun %assistant-classify-command-line (text)
  "Classify TEXT as a bare command line: the reader of eval, sh -c, and
process substitutions."
  (let ((parsed (nshell.domain.parsing:parse-command-line text))
        (*assistant-reader-stage-p* nil))
    (if (nshell.domain.parsing:parse-complete-p parsed)
        (classify-ast (nshell.domain.parsing:parse-result-ast parsed))
        (%assistant-unparsable-result "the wrapped command could not be parsed"))))

(defun %assistant-classify-substitution-text (text)
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
       (%assistant-classify-command-line text))
      (t
       (handler-case
           (classify-ast (nshell.domain.parsing:read-submission
                          text :reader-context :auto))
         (error ()
           (%assistant-unparsable-result
            "the command substitution could not be read")))))))

(defparameter +assistant-substitution-markers+
  '(("$(" . :substitution) ("(" . :substitution)
    ("<(" . :command-line) (">(" . :command-line))
  "Substitution openers and the reader their body runs with.")

(defun %assistant-substitution-results (words)
  (loop for word in words
        nconc (loop for (marker . reader) in +assistant-substitution-markers+
                    nconc (mapcar
                           (lambda (text)
                             (cond
                               ((eq text :incomplete)
                                (%assistant-unparsable-result
                                 "an incomplete command substitution cannot be classified safely"))
                               ((eq reader :command-line)
                                (%assistant-classify-command-line text))
                               (t (%assistant-classify-substitution-text text))))
                           (nshell.domain.parsing:parenthesized-substitution-texts
                            word marker)))))

(defun %assistant-embedded-command-result (args)
  "Classify the operands from the first word that names a command able to
change the system.  The rules use it only for commands they do not know,
so an unknown wrapper such as `nohup-like rm -rf /' stays blocked."
  (loop for tail on args
        when (member (%assistant-command-basename (first tail))
                     '("rm" "mkfs" "dd" "chmod" "git" "curl" "wget"
                       "sh" "bash" "zsh" "fish")
                     :test #'string=)
          return (%assistant-classify-argv tail)))

(defun %assistant-classify-argv (words &key assignments nested writes
                                           redirect-problems raw-words)
  "Classify the command the argv WORDS run.  ASSIGNMENTS are the environment
names assigned before it and NESTED the reasons of its substitutions.
WRITES, REDIRECT-PROBLEMS, and RAW-WORDS describe the redirects and the
written words of the outermost command."
  (let ((command (first words))
        (args (rest words)))
    (multiple-value-bind (kind inner mismatches names env-options source)
        (nshell.feature.kb:command-wrapper command args)
      (let ((wrapped (cond
                       (source (%assistant-classify-command-line source))
                       (inner (%assistant-classify-argv inner))))
            (embedded (unless kind (%assistant-embedded-command-result args))))
        (%assistant-subject-result
         command
         :command (%assistant-command-basename command)
         :invoked-as command
         :arguments args
         :wraps (and kind t)
         :opaque (eq kind :opaque)
         :wrapper-mismatches mismatches
         :assignments (append assignments names)
         :wrapper-options env-options
         :writes writes
         :redirect-problems redirect-problems
         :words raw-words
         :nested (append (and wrapped (%assistant-result-reasons wrapped)) nested)
         :embedded (and embedded (%assistant-result-reasons embedded)))))))

(defparameter +assistant-output-redirect-kinds+
  '(:> :>> :&> :&>> :2> :2>>
    :output-file :append-output-file :force-output-file :error-file
    :append-error-file :both-output-files :append-both-output-files)
  "Redirect kinds that write a file: bare-line kinds from ast-redirect-split
and reader kinds from ast-redirect-entry.")

(defun %assistant-redirects (split-redirects entries)
  "Describe the redirects of one command (D-P1-5 2.5).  SPLIT-REDIRECTS are
the (KIND . TARGET) pairs of ast-redirect-split and ENTRIES the reader's
ast-redirect-entry values.  Return the output targets, a text for each
redirect outside the safe forms, the texts whose substitutions run
(targets, here-document bodies, here-strings), and the results of the
process substitutions."
  (let ((writes nil)
        (problems nil)
        (texts nil)
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
             (push (classify-ast (nshell.domain.parsing:redirect-procsub-target-form
                                  target))
                   results)
             (when (eq (nshell.domain.parsing:redirect-procsub-target-direction target)
                       :output)
               (push "process substitution >(...)" problems)))
            ((nshell.domain.parsing:redirect-heredoc-target-p target)
             (push (nshell.domain.parsing:redirect-heredoc-target-body target) texts))
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
              (nreverse results)))))

(defun %assistant-command-parts (node)
  "Split a command NODE the way the executors split it.  Assignments come
from command-node-assignment-words (a line that runs no command) or, on the
bare-line path, split-command-node-assignments (a prefix), plus a reader
node's own assignment slot.  Redirects come from the reader node's redirect
entries and, on the bare-line path, from ast-redirect-split of the command
that remains, as in %execute-plain-command-node-in-context.  Return the argv of
that command without its redirects (NIL when the line runs no command), the
assigned names, the words as written (redirect targets, here-document
bodies, and assignments included), the output targets, the redirect
problems, and the results of its process substitution redirects."
  (let* ((reader-assignments
           (mapcar #'nshell.domain.parsing:arg-value
                   (nshell.domain.parsing:command-node-environment-assignments node)))
         (assignment-only (nshell.domain.parsing:command-node-assignment-words node)))
    (multiple-value-bind (prefix rest)
        (cond
          (assignment-only (values assignment-only nil))
          (*assistant-reader-stage-p* (values nil node))
          (t (nshell.domain.parsing:split-command-node-assignments node)))
      (let ((split (and rest
                        (not *assistant-reader-stage-p*)
                        (nshell.domain.parsing:split-command-node-redirects rest))))
        (multiple-value-bind (writes problems texts results)
            (%assistant-redirects
             (and split
                  (nshell.domain.parsing:command-redirect-split-result-redirects split))
             (nshell.domain.parsing:command-node-redirects node))
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
                    results)))))))

(defun classify-command (node)
  "Classify a command-node using its effective command and arguments."
  (if (nshell.domain.parsing:command-node-p node)
      (multiple-value-bind (argv assignments words writes problems results)
          (%assistant-command-parts node)
        (let ((nested (mapcan #'%assistant-result-reasons
                              (append results (%assistant-substitution-results words)))))
          (if argv
              (%assistant-classify-argv
               argv
               :assignments assignments
               :writes writes
               :redirect-problems problems
               :raw-words words
               :nested nested)
              (%assistant-subject-result
               nil
               :assignments assignments
               :writes writes
               :redirect-problems problems
               :words words
               :nested nested))))
      (%assistant-unparsable-result "the value is not a command AST node")))

(defun command-effects (node)
  "Return the effects of the command NODE runs: (DELETES PATH), (WRITES PATH),
and :NETWORK.  Writes come from the redirects in the AST (D-P1-5 2.5)."
  (multiple-value-bind (argv assignments words writes)
      (%assistant-command-parts node)
    (declare (ignore assignments words))
    (nshell.feature.kb:subject-effects
     :command (and argv (%assistant-command-basename (first argv)))
     :invoked-as (first argv)
     :arguments (rest argv)
     :writes writes)))

(defun classify-pipeline (node)
  "Classify a pipeline by its most restrictive stage."
  (if (nshell.domain.parsing:pipeline-node-p node)
      (%assistant-most-restrictive-result
       (mapcar #'classify-ast
               (nshell.domain.parsing:pipeline-node-commands node)))
      (%assistant-unparsable-result "the value is not a pipeline AST node")))

(defun %assistant-classify-sequence (node)
  (if (nshell.domain.parsing:sequence-node-p node)
      (%assistant-most-restrictive-result
       (mapcar #'classify-ast
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

(defun %assistant-classify-reader-result (reader-result)
  (let ((form (nshell.domain.parsing:reader-result-form reader-result)))
    (cond
      ((or (nshell.domain.parsing:command-node-p form)
           (nshell.domain.parsing:pipeline-node-p form)
           (nshell.domain.parsing:sequence-node-p form))
       (%assistant-form-result (let ((*assistant-reader-stage-p* t))
                                 (classify-ast form))
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
              (let ((*assistant-reader-stage-p* t))
                (classify-ast ast))
              :sexp-unforced
              (not (and (nshell.domain.parsing:command-node-p ast)
                        (nshell.domain.parsing:command-node-force-external-p ast)
                        (not (%assistant-ast-has-redirect-p ast))
                        (ignore-errors (every #'atom form))))))
         (error ()
           (%assistant-unclassifiable-result "unclassifiable S-expression form"))))
      (t
       (%assistant-unclassifiable-result "unclassifiable S-expression form")))))

(defun classify-ast (node)
  "Classify shell AST and S-expression input without inspecting raw text."
  (cond
    ((nshell.domain.parsing:reader-result-p node)
     (%assistant-classify-reader-result node))
    ((and (consp node)
          (ignore-errors
            (every #'nshell.domain.parsing:reader-result-p node)))
     (%assistant-most-restrictive-result
      (mapcar #'%assistant-classify-reader-result node)))
    ((nshell.domain.parsing:command-node-p node) (classify-command node))
    ((nshell.domain.parsing:pipeline-node-p node) (classify-pipeline node))
    ((nshell.domain.parsing:sequence-node-p node)
     (%assistant-classify-sequence node))
    ((consp node)
     (%assistant-unclassifiable-result "unclassifiable S-expression form"))
    (t (%assistant-unparsable-result "unsupported AST node"))))
