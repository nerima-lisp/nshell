(in-package #:nshell.feature.machine)

;;; The machine methods.  run lives with the --json command it shares; the
;;; others are built here.  explain reads and classifies its input with the
;;; code Enter uses and runs nothing.  Its verdict is for display only (D-81):
;;; nothing here touches the execution gate's approval state.

(defparameter *machine-methods*
  '("initialize" "run" "explain" "complete" "state" "history" "help" "query"
    "read_output" "policy")
  "The methods the machine interface answers, in the order of the ux/U5
initialize example.  initialize lists exactly these, and --mcp offers each as
a tool; query answers E_NOT_IMPLEMENTED until the knowledge base can (P4-5).")

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

(defun reader-results-effects (context reader-results)
  "Return the ENVELOPE-EFFECTs of the commands READER-RESULTS run in CONTEXT,
and as a second value the classifier's result.  Both come from one walk of
the classifier with the resolver of CONTEXT, so the effects are those of the
commands it judges, substitutions and alias expansions included.  explain
and --json both report these effects."
  (multiple-value-bind (effects result)
      (nshell.feature.assistant:command-effects
       reader-results
       :resolve (nshell.application:assistant-command-resolver context))
    (values (knowledge-base-effects effects) result)))

(defun %explain-parse-error (text start end message started cwd
                             &optional (code "E_PARSE"))
  ;; Without an AST the classifier gives its verdict on unparsable input.
  (error-envelope code
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
be read, or that holds no form, is E_PARSE; input the reader rejects with its
own code, such as E_UNSUPPORTED_SYNTAX, keeps that code."
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
              (multiple-value-bind (effects verdict)
                  (reader-results-effects context reader-results)
                (explain-envelope
                 :forms (let ((resolve (nshell.application:assistant-command-resolver
                                        context)))
                          (mapcar (lambda (reader-result)
                                    (%explain-form context reader-result text resolve))
                                  reader-results))
                 :effects effects
                 :safety (classification-safety verdict)
                 :state (make-envelope-state :cwd cwd)
                 :duration-ms (%elapsed-ms started)))))
      (nshell.domain.parsing:sexp-reader-error (condition)
        (let ((span (nshell.domain.parsing:sexp-reader-error-source-span condition)))
          (%explain-parse-error text
                                (if (consp span) (first span) 0)
                                (if (consp span) (second span) (length text))
                                (princ-to-string condition)
                                started cwd
                                (nshell.domain.error-codes:condition-error-code
                                 condition)))))))

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
                                       (make-machine-context)))
                                 session-id)
  "Return the initialize response (ux/U5) in the envelope's value.  SESSION-ID
names the session of a server that keeps one."
  (%method-envelope
   (initialize-value :version (asdf:component-version (asdf:find-system "nshell"))
                     :methods *machine-methods*
                     :cwd cwd
                     :os (string-downcase (software-type))
                     :user-rules (%user-rule-count)
                     :session-id session-id)
   cwd))

(defun policy-envelope (&key (cwd (nshell.application:context-current-directory
                                   (make-machine-context))))
  "Return the policy response (ux/U7) in the envelope's value."
  (%method-envelope (policy-value :user-rules (%user-rule-count)) cwd))

(defun method-error-envelope (code message cwd)
  "Return the envelope of a method request that failed with CODE before
running anything."
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
     (method-error-envelope "E_PROTOCOL" "seq must be a positive integer" cwd))
    ((not (member stream '("stdout" "stderr") :test #'equal))
     (method-error-envelope "E_PROTOCOL" "stream must be \"stdout\" or \"stderr\"" cwd))
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
         (method-error-envelope (ecase (saved-output-error-reason condition)
                               (:request "E_PROTOCOL")
                               (:store "E_PERMISSION"))
                             (saved-output-error-message condition)
                             cwd))))))

;;; complete, state, history, help and query.  Their value shapes are the
;;; smallest that carry what proposal/02 lists for them; the design does not
;;; fix them yet.

(defun complete-envelope (context input &key cursor (cwd (nshell.application:context-current-directory context)))
  "Return the completion candidates for INPUT up to CURSOR (its end by
default) in CONTEXT: value {\"candidates\": [{text, kind, description}]}, in
the order the line editor ranks them.  A CURSOR outside INPUT is E_PROTOCOL."
  (let ((cursor (or cursor (length input))))
    (if (not (and (integerp cursor) (<= 0 cursor (length input))))
        (method-error-envelope "E_PROTOCOL"
                               "cursor must be an integer from 0 to the input's length"
                               cwd)
        (let* ((environment (nshell.application:shell-context-environment context))
               (candidates
                 (nshell.domain.completion:complete
                  (nshell.application:shell-context-knowledge-base context)
                  (subseq input 0 cursor)
                  :path (nshell.domain.environment:env-get environment "PATH")
                  :filesystem (nshell.application:shell-context-filesystem context)
                  :alias-table (nshell.application:shell-context-alias-table context)
                  :function-table (nshell.application:shell-context-function-table context)
                  :variable-names (mapcar (lambda (binding)
                                            (cons (nshell.domain.environment:env-binding-name binding)
                                                  (nshell.domain.environment:env-binding-value binding)))
                                          (nshell.domain.environment:env-bindings environment))
                  :directory (nshell.infrastructure.acl:current-working-directory)
                  :home-directory (nshell.domain.environment:env-get environment "HOME"))))
          (%method-envelope
           (json-kit:make-json-object
            (list (cons "candidates"
                        (map 'vector
                             (lambda (candidate)
                               (let ((kind (nshell.domain.completion:candidate-kind candidate))
                                     (description
                                       (nshell.domain.completion:candidate-description candidate)))
                                 (json-kit:make-json-object
                                  (list (cons "text" (nshell.domain.completion:candidate-text candidate))
                                        (cons "kind" (if kind
                                                         (string-downcase (princ-to-string kind))
                                                         json-kit:+json-null+))
                                        (cons "description"
                                              (if (plusp (length description))
                                                  description
                                                  json-kit:+json-null+))))))
                             candidates))))
           cwd)))))

(defun state-envelope (&key cwd session-id seq last-status)
  "Return the state response: value {cwd, session: {id, seq}, last_status},
SEQ the number of runs so far and LAST-STATUS the last run's status or NIL.
The envelope's state carries LAST-STATUS too."
  (result-envelope :duration-ms 0
                   :stdout (output-from-text "")
                   :stderr (output-from-text "")
                   :safety (make-envelope-safety :level :safe)
                   :state (make-envelope-state :cwd cwd :last-status last-status)
                   :value (json-kit:make-json-object
                           (list (cons "cwd" cwd)
                                 (cons "session"
                                       (json-kit:make-json-object
                                        (list (cons "id" (or session-id json-kit:+json-null+))
                                              (cons "seq" (or seq 0)))))
                                 (cons "last_status" (or last-status json-kit:+json-null+))))))

(defun history-envelope (entries &key query limit cwd)
  "Return the history response for ENTRIES, a list of (SEQ INPUT STATUS)
newest first: value {\"entries\": [{seq, input, status}]}, keeping those
whose input contains QUERY and at most LIMIT of them.  A LIMIT that is not a
positive integer or a QUERY that is not a string is E_PROTOCOL."
  (cond
    ((not (or (null query) (stringp query)))
     (method-error-envelope "E_PROTOCOL" "query must be a string" cwd))
    ((not (or (null limit) (and (integerp limit) (plusp limit))))
     (method-error-envelope "E_PROTOCOL" "limit must be a positive integer" cwd))
    (t
     (let* ((matching (if query
                          (remove-if-not (lambda (entry) (search query (second entry)))
                                         entries)
                          entries))
            (kept (if limit (subseq matching 0 (min limit (length matching))) matching)))
       (%method-envelope
        (json-kit:make-json-object
         (list (cons "entries"
                     (map 'vector
                          (lambda (entry)
                            (destructuring-bind (seq input status) entry
                              (json-kit:make-json-object
                               (list (cons "seq" seq)
                                     (cons "input" input)
                                     (cons "status" status)))))
                          kept))))
        cwd)))))

(defun help-envelope (&key topic cwd)
  "Return the help response: value {topic, text}, the text help prints for
TOPIC, a builtin name, or the overview without one.  A TOPIC with no help, or
one that is not a string, is E_PROTOCOL."
  (if (not (or (null topic) (stringp topic)))
      (method-error-envelope "E_PROTOCOL" "topic must be a string" cwd)
      (multiple-value-bind (text status)
          (nshell.application::%builtin-help nil (and topic (list topic)))
        (if (eql status 0)
            (%method-envelope
             (json-kit:make-json-object
              (list (cons "topic" (or topic json-kit:+json-null+))
                    (cons "text" text)))
             cwd)
            (method-error-envelope "E_PROTOCOL" (string-right-trim '(#\Newline) text) cwd)))))

(defun query-envelope (&key cwd)
  "Return the query response until the knowledge base answers queries (P4-5)."
  (method-error-envelope "E_NOT_IMPLEMENTED"
                         "query is not implemented yet; it arrives with the knowledge base (P4-5)"
                         cwd))
