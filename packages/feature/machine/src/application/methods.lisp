(in-package #:nshell.feature.machine)

;;; The machine methods: explain, initialize, policy and read_output.
;;; explain reads and classifies its input with the code Enter uses and runs
;;; nothing.  Its verdict is for display only (D-81): nothing here
;;; touches the execution gate's approval state.

(defparameter *machine-methods* '("explain" "initialize" "policy" "read_output")
  "The methods implemented now, in name order.  initialize lists exactly
these (ux/U5); a task that implements a method adds its name here.")

(defun make-machine-context ()
  "Return a shell context for a machine request: the process environment
and nothing else, as `nshell --command' starts without the startup file.
The context keeps make-shell-context's autoload hook; explain never reaches
it, because every name it resolves goes through lookups that do not autoload."
  (nshell.application:make-shell-context
   :config (nshell.domain.configuration:default-config)
   :environment (nshell.domain.environment:inject-os-environment
                 (nshell.domain.environment:make-default-environment)
                 (nshell.infrastructure.acl:current-environment-entries)
                 #'nshell.infrastructure.acl:current-working-directory)))

(defun %elapsed-ms (started)
  (round (* 1000 (- (get-internal-real-time) started))
         internal-time-units-per-second))

(defun %command-nodes (ast)
  "Return the command nodes AST runs at its top level: itself, or the stages
of a pipeline and the items of a sequence."
  (cond
    ((nshell.domain.parsing:command-node-p ast) (list ast))
    ((nshell.domain.parsing:pipeline-node-p ast)
     (mapcan #'%command-nodes (nshell.domain.parsing:pipeline-node-commands ast)))
    ((nshell.domain.parsing:sequence-node-p ast)
     (mapcan #'%command-nodes (nshell.domain.parsing:sequence-node-commands ast)))
    (t nil)))

(defun %command-ast (context reader-result)
  (ignore-errors (nshell.application:reader-result-command-ast context reader-result)))

(defun %external-path (context ast resolve)
  "Return the PATH executable a command AST runs, or NIL when the executor
resolves it to a builtin, a function, or an alias."
  (when (nshell.domain.parsing:command-node-p ast)
    (ignore-errors
     (when (eq :external (funcall resolve ast :reader))
       (multiple-value-bind (kind path)
           (nshell.application:resolve-command-path
            context (nshell.domain.parsing:command-node-command ast))
         (and (eq kind :path) (namestring path)))))))

(defun %explain-form (context reader-result source resolve)
  (let ((kind (nshell.application:reader-result-form-kind context reader-result))
        (span (nshell.domain.parsing:reader-result-source-span reader-result)))
    (make-envelope-form
     :text (subseq source (first span) (second span))
     :kind (string-downcase (symbol-name kind))
     ;; D-76: the rule number of language/L2 stays null until P2-2.
     :rule nil
     :path (and (eq kind :command)
                (%external-path context (%command-ast context reader-result)
                                resolve)))))

(defun %explain-effects (context reader-results)
  (knowledge-base-effects
   (remove-duplicates
    (loop for reader-result in reader-results
          append (loop for node in (%command-nodes (%command-ast context reader-result))
                       append (nshell.feature.assistant:command-effects node)))
    :test #'equal :from-end t)))

(defun %explain-parse-error (text start end message started cwd)
  ;; Without an AST the classifier gives its verdict on unparsable input.
  (error-envelope "E_PARSE"
                  :message message
                  :span (source-span text start end)
                  :duration-ms (%elapsed-ms started)
                  :stdout (output-from-text "")
                  :stderr (output-from-text "")
                  :safety (classification-safety
                           (nshell.feature.assistant:classify-ast nil))
                  :state (make-envelope-state :cwd cwd)))

(defun explain-input (context text &key cwd)
  "Return the explain envelope of TEXT in CONTEXT without running it: one
form per top-level form with its kind, the effects of the commands it runs,
and the verdict of the classifier Enter uses, which resolves names with
assistant-command-resolver and so loads no function file.  Input that cannot
be read, or that holds no form, is E_PARSE."
  (let ((started (get-internal-real-time))
        (cwd (or cwd (nshell.application:context-current-directory context))))
    (handler-case
        (let ((reader-results
                (nshell.domain.parsing:read-submission
                 text
                 :reader-context
                 (nshell.domain.parsing:submission-reader-context text))))
          (if (null reader-results)
              (%explain-parse-error text 0 (length text) "nothing to explain"
                                    started cwd)
              (let ((resolve (nshell.application:assistant-command-resolver context)))
                (explain-envelope
                 :forms (mapcar (lambda (reader-result)
                                  (%explain-form context reader-result text resolve))
                                reader-results)
                 :effects (%explain-effects context reader-results)
                 :safety (classification-safety
                          (nshell.feature.assistant:classify-ast
                           reader-results :resolve resolve))
                 :state (make-envelope-state :cwd cwd)
                 :duration-ms (%elapsed-ms started)))))
      (nshell.domain.parsing:sexp-reader-error (condition)
        (let ((span (nshell.domain.parsing:sexp-reader-error-source-span condition)))
          (%explain-parse-error text
                                (if (consp span) (first span) 0)
                                (if (consp span) (second span) (length text))
                                (princ-to-string condition)
                                started cwd))))))

(defun %user-rule-count ()
  (length (nshell.feature.kb:classify-rule-catalog
           nshell.feature.kb:*user-classify-rulebase*)))

(defun %method-envelope (value cwd)
  (result-envelope :duration-ms 0
                   :stdout (output-from-text "")
                   :stderr (output-from-text "")
                   :safety (make-envelope-safety :level :safe)
                   :state (make-envelope-state :cwd cwd)
                   :value value))

(defun initialize-envelope (&key (cwd (nshell.application:context-current-directory
                                       (make-machine-context))))
  "Return the initialize response (ux/U5) in the envelope's value."
  (%method-envelope
   (initialize-value :version (asdf:component-version (asdf:find-system "nshell"))
                     :methods *machine-methods*
                     :cwd cwd
                     :os (string-downcase (software-type))
                     :user-rules (%user-rule-count))
   cwd))

(defun policy-envelope (&key (cwd (nshell.application:context-current-directory
                                   (make-machine-context))))
  "Return the policy response (ux/U7) in the envelope's value."
  (%method-envelope (policy-value :user-rules (%user-rule-count)) cwd))

(defun %read-output-error (code message cwd)
  (error-envelope code
                  :message message
                  :duration-ms 0
                  :stdout (output-from-text "")
                  :stderr (output-from-text "")
                  :safety (make-envelope-safety :level :safe)
                  :state (make-envelope-state :cwd cwd)))

(defun read-output-envelope (&key id (seq 1) (stream "stdout") (offset 0)
                                  (limit +default-max-output-bytes+)
                                  (cwd (nshell.application:context-current-directory
                                        (make-machine-context)))
                                  (root (output-store-root)))
  "Return the read_output response (ux/U6): the text of the output stream STREAM
of run SEQ in session ID that the store under ROOT saved, from byte OFFSET and
at most LIMIT bytes, in the envelope's value.  A malformed request is
E_PROTOCOL; a store that refuses the file is E_PERMISSION."
  (cond
    ((not (and (integerp seq) (plusp seq)))
     (%read-output-error "E_PROTOCOL" "seq must be a positive integer" cwd))
    ((not (member stream '("stdout" "stderr") :test #'equal))
     (%read-output-error "E_PROTOCOL" "stream must be \"stdout\" or \"stderr\"" cwd))
    (t
     (handler-case
         (multiple-value-bind (text next-offset bytes)
             (read-saved-output id (format nil (if (equal stream "stdout")
                                                   "~D.txt"
                                                   "~D.stderr.txt")
                                           seq)
                                :offset offset :limit limit :root root)
           (%method-envelope
            (json-kit:make-json-object
             (list (cons "id" id)
                   (cons "seq" seq)
                   (cons "stream" stream)
                   (cons "offset" offset)
                   (cons "next_offset" next-offset)
                   (cons "bytes" bytes)
                   (cons "eof" (if (= next-offset bytes) t json-kit:+json-false+))
                   (cons "text" text)))
            cwd))
       (saved-output-error (condition)
         (%read-output-error (ecase (saved-output-error-reason condition)
                               (:request "E_PROTOCOL")
                               (:store "E_PERMISSION"))
                             (saved-output-error-message condition)
                             cwd))))))
