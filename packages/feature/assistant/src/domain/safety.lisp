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

(defun %assistant-classify-command-line (text)
  "Classify TEXT as a bare command line: the reader of eval, sh -c, and
process substitutions."
  (let ((parsed (nshell.domain.parsing:parse-command-line text)))
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

(defun %assistant-classify-argv (words &key assignments nested)
  "Classify the command the argv WORDS run.  ASSIGNMENTS are the environment
names assigned before it and NESTED the reasons of its substitutions."
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
         :nested (append (and wrapped (%assistant-result-reasons wrapped)) nested)
         :embedded (and embedded (%assistant-result-reasons embedded)))))))

(defun %assistant-assignment-prefix (words)
  "Split the leading NAME=value words off WORDS when a command follows them.
Any word with `=' counts; the rules judge the name (D-P1-5 2.4)."
  (let ((command (member-if-not (lambda (word) (find #\= word)) words)))
    (if command
        (values (ldiff words command) command)
        (values nil words))))

(defun classify-command (node)
  "Classify a command-node using its effective command and arguments."
  (if (nshell.domain.parsing:command-node-p node)
      (let ((words (cons (nshell.domain.parsing:command-node-command node)
                         (nshell.domain.parsing:command-node-arg-values node))))
        (multiple-value-bind (prefix argv) (%assistant-assignment-prefix words)
          (%assistant-classify-argv
           argv
           :assignments
           (mapcar #'nshell.feature.kb:assignment-name
                   (append (mapcar #'nshell.domain.parsing:arg-value
                                   (nshell.domain.parsing:command-node-environment-assignments
                                    node))
                           prefix))
           :nested (mapcan #'%assistant-result-reasons
                           (%assistant-substitution-results words)))))
      (%assistant-unparsable-result "the value is not a command AST node")))

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
       (%assistant-form-result (classify-ast form)
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
              (classify-ast ast)
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
