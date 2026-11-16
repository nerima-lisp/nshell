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

(defun %assistant-wrapper-index-and-kind (command args)
  (let* ((separator (position (code-char 47) command :from-end t))
         (name (if separator (subseq command (1+ separator)) command))
        (value-options '("-u" "--user" "-g" "--group" "-C" "--chdir"
                         "-n" "--adjustment" "-f" "--format" "-I" "--replace")))
    (labels ((target-index (start env-p)
               (loop with index = start
                     while (< index (length args))
                     for arg = (nth index args)
                     do (cond
                          ((string= arg "--") (return (1+ index)))
                          ((and env-p (search "=" arg)) (incf index))
                          ((and (plusp (length arg))
                                (char= (char arg 0) (code-char 45)))
                           (incf index)
                           (when (and (< index (length args))
                                      (member arg value-options :test #'string=))
                             (incf index)))
                          (t (return index))))))
      (cond
        ((member name '("command" "builtin" "exec" "and" "or" "not")
                 :test #'string=)
         (values (target-index 0 nil) :command))
        ((member name '("env" "sudo" "doas" "nice" "time" "nohup" "xargs")
                 :test #'string=)
         (values (target-index 0 (string= name "env")) :command))
        (t (values nil nil))))))

(defun assistant-command-after-wrappers (command args)
  "Return the effective command and arguments after known wrappers."
  (loop
    (multiple-value-bind (index kind)
        (%assistant-wrapper-index-and-kind command args)
      (declare (ignore kind))
      (if index
          (setf command (nth index args)
                args (nthcdr (1+ index) args))
          (return (values (%assistant-command-basename command) args))))))

(defun %assistant-parse-and-classify-text (text)
  (let ((parsed (nshell.domain.parsing:parse-command-line text)))
    (if (nshell.domain.parsing:parse-complete-p parsed)
        (classify-ast (nshell.domain.parsing:parse-result-ast parsed))
        (%assistant-unparsable-result "the wrapped command could not be parsed"))))

(defun %assistant-wrapped-result (command args)
  "Classify the command that a wrapper, eval, or sh -c runs, or return NIL."
  (cond
    ((let ((index (%assistant-wrapper-index-and-kind command args)))
       (when index
         (%assistant-parse-and-classify-text
          (format nil "~{~a~^ ~}" (nthcdr index args))))))
    ((string= command "eval")
     (%assistant-parse-and-classify-text (format nil "~{~a~^ ~}" args)))
    ((member command '("sh" "bash" "zsh" "fish") :test #'string=)
     (let ((index (position "-c" args :test #'string=)))
       (when (and index (nth (1+ index) args))
         (%assistant-parse-and-classify-text (nth (1+ index) args)))))
    (t nil)))

(defun %assistant-embedded-command-result (args)
  "Classify the operands from the first word that names a command able to
change the system.  The rules use it only for commands they do not know,
so an unknown wrapper such as `nohup-like rm -rf /' stays blocked."
  (loop for tail on args
        when (member (%assistant-command-basename (first tail))
                     '("rm" "mkfs" "dd" "chmod" "git" "curl" "wget"
                       "sh" "bash" "zsh" "fish")
                     :test #'string=)
          return (%assistant-parse-and-classify-text
                  (format nil "~{~a~^ ~}" tail))))

(defun %assistant-substitution-results (command args)
  (let ((results nil))
    (dolist (arg (cons command args) (nreverse results))
      (dolist (marker '("$(" "<(" ">(" "("))
        (dolist (text (nshell.domain.parsing:parenthesized-substitution-texts
                       arg marker))
          (push (if (eq text :incomplete)
                    (%assistant-unparsable-result
                     "an incomplete command substitution cannot be classified safely")
                    (%assistant-parse-and-classify-text text))
                results))))))

(defun classify-command (node)
  "Classify a command-node using its effective command and arguments."
  (if (nshell.domain.parsing:command-node-p node)
      (let* ((command (nshell.domain.parsing:command-node-command node))
             (args (nshell.domain.parsing:command-node-arg-values node))
             (wrapped (%assistant-wrapped-result command args))
             (embedded (unless wrapped
                         (%assistant-embedded-command-result args))))
        (%assistant-subject-result
         command
         :command (%assistant-command-basename command)
         :invoked-as command
         :arguments args
         :wraps (and wrapped t)
         :nested (mapcan #'%assistant-result-reasons
                         (append (and wrapped (list wrapped))
                                 (%assistant-substitution-results command args)))
         :embedded (and embedded (%assistant-result-reasons embedded))))
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
