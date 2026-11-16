(in-package #:nshell.feature.machine)

;;; The response envelope of ux/U6. --json, --serve and MCP build every
;;; response through RESULT-ENVELOPE, ERROR-ENVELOPE or EXPLAIN-ENVELOPE and
;;; write it with ENVELOPE-TO-JSON; docs/design/conformance/envelope.schema.json
;;; describes the JSON these produce.

(defconstant +nshell-api-version+ 1)

(define-condition invalid-envelope (simple-error) ()
  (:documentation "A builder or the JSON conversion got a part outside the
envelope's types."))

(defun %invalid (format-control &rest arguments)
  (error 'invalid-envelope :format-control format-control
                           :format-arguments arguments))

(defparameter +effect-kinds+ '(:reads :writes :deletes :network :privilege))

(defparameter +safety-levels+ '(:safe :confirm :block))

(defun %codes-of-kind (kind)
  (loop for entry in nshell.domain.error-codes:+error-codes+
        when (eq kind (nshell.domain.error-codes:error-code-kind entry))
          collect (nshell.domain.error-codes:error-code-name entry)))

(defun envelope-error-codes ()
  "Return the E_ codes error.code may carry, in table order."
  (%codes-of-kind :error))

(defun envelope-warning-codes ()
  "Return the W_ codes warnings[].code may carry, in table order."
  (%codes-of-kind :warning))

;;; Parts

(defstruct (envelope-output
            (:constructor make-envelope-output
                (&key text bytes lines (truncated nil) path)))
  "TEXT is what the response carries; BYTES and LINES count the whole output,
which PATH holds when TRUNCATED."
  text bytes lines truncated path)

(defun %line-count (text)
  (+ (count #\Newline text)
     (if (and (plusp (length text))
              (char/= #\Newline (char text (1- (length text)))))
         1
         0)))

(defun output-from-text (text)
  "Return an untruncated ENVELOPE-OUTPUT holding all of TEXT."
  (make-envelope-output
   :text text
   :bytes (length (sb-ext:string-to-octets text :external-format :utf-8))
   :lines (%line-count text)))

(defstruct (envelope-effect (:constructor make-envelope-effect (&key kind path size)))
  "KIND is one of +EFFECT-KINDS+. SIZE is a byte count or a display string."
  kind path size)

(defstruct (envelope-reason (:constructor make-envelope-reason (&key rule text)))
  rule text)

(defstruct (envelope-safety (:constructor make-envelope-safety (&key level reasons)))
  "LEVEL is one of +SAFETY-LEVELS+; REASONS is a list of ENVELOPE-REASON."
  level reasons)

(defstruct (envelope-state
            (:constructor make-envelope-state
                (&key cwd env-changed jobs last-status)))
  "ENV-CHANGED is a list of variable names. JOBS is a list of alists with
string keys, one per job."
  cwd env-changed jobs last-status)

(defstruct (envelope-span (:constructor make-envelope-span (&key line column end)))
  line column end)

(defstruct (envelope-fix (:constructor make-envelope-fix (&key input why rule)))
  input why rule)

(defstruct (envelope-error-object
            (:conc-name envelope-error-)
            (:constructor make-envelope-error (&key code message span fixes)))
  "CODE is an E_ name from the error-code table."
  code message span fixes)

(defstruct (envelope-warning
            (:constructor make-envelope-warning (&key code message span fixes)))
  "CODE is a W_ name from the error-code table."
  code message span fixes)

(defstruct (envelope-form (:constructor make-envelope-form (&key text kind rule path)))
  "KIND is the classification of language/L2 2.1. RULE stays NIL until P2-2
fills in the rule number; it is still written, as null."
  text kind rule path)

;;; Envelope

(defstruct (envelope (:constructor %make-envelope))
  (status 0)
  (duration-ms 0)
  stdout stderr
  (value '%absent)
  error warnings forms effects safety state session seq)

(defun envelope-value-present-p (envelope)
  (not (eq (envelope-value envelope) '%absent)))

(defun envelope-ok-p (envelope)
  "U6: ok when status is 0 and there is no error."
  (and (eql 0 (envelope-status envelope))
       (null (envelope-error envelope))))

(defun %required (value name)
  (when (null value)
    (%invalid "An envelope needs ~A." name))
  value)

(defun result-envelope (&key (status 0) duration-ms stdout stderr effects
                             safety state (value '%absent) warnings session seq)
  "Build the envelope of a run that raised no nshell error. STATUS is the exit
status; a non-zero status alone makes ok false."
  (%make-envelope :status status
                  :duration-ms (%required duration-ms "duration-ms")
                  :stdout (%required stdout "stdout")
                  :stderr (%required stderr "stderr")
                  :value value :warnings warnings
                  :effects effects
                  :safety (%required safety "safety")
                  :state (%required state "state")
                  :session session :seq seq))

(defun %error-status (code status)
  (let ((entry (nshell.domain.error-codes:find-error-code code)))
    (unless (and entry
                 (eq :error (nshell.domain.error-codes:error-code-kind entry)))
      (%invalid "~S is not an E_ code in the error-code table." code))
    (let ((table-status (nshell.domain.error-codes:error-code-exit-code entry)))
      (cond ((eq table-status :child)
             ;; E_COMMAND_FAILED reports the child's own failing status.
             (unless (and (integerp status) (/= status 0))
               (%invalid "~A needs the child's non-zero exit status, not ~S."
                      code status))
             status)
            ((or (null status) (eql status table-status))
             table-status)
            (t
             (%invalid "~A exits with ~D, not ~S." code table-status status))))))

(defun error-envelope (code &key status message span fixes duration-ms stdout
                                 stderr effects safety state warnings session seq)
  "Build the envelope of a failure with error CODE. The status is the code's
exit status from the error-code table; STATUS is only accepted for a code whose
status is the child's."
  (%make-envelope :status (%error-status code status)
                  :duration-ms (%required duration-ms "duration-ms")
                  :stdout (%required stdout "stdout")
                  :stderr (%required stderr "stderr")
                  :error (make-envelope-error :code code :message message
                                              :span span :fixes fixes)
                  :warnings warnings
                  :effects effects
                  :safety (%required safety "safety")
                  :state (%required state "state")
                  :session session :seq seq))

(defun explain-envelope (&key forms duration-ms effects safety state warnings
                              session seq)
  "Build the envelope of explain, which runs nothing: status 0 and empty
output, with the classification of each form in FORMS."
  (%make-envelope :status 0
                  :duration-ms (%required duration-ms "duration-ms")
                  :stdout (output-from-text "")
                  :stderr (output-from-text "")
                  :forms (%required forms "forms")
                  :warnings warnings
                  :effects effects
                  :safety (%required safety "safety")
                  :state (%required state "state")
                  :session session :seq seq))

(defparameter +envelope-response-kinds+
  '((:result . result-envelope)
    (:error . error-envelope)
    (:explain . explain-envelope))
  "The closed set of response kinds and their builders. The envelope test
holds one schema sample per kind, so a kind added here without a sample fails.")

(defun build-envelope-response (kind &rest arguments)
  "Build an envelope of response KIND from +ENVELOPE-RESPONSE-KINDS+."
  (let ((entry (assoc kind +envelope-response-kinds+)))
    (unless entry
      (%invalid "~S is not a response kind in +ENVELOPE-RESPONSE-KINDS+." kind))
    (apply (cdr entry) arguments)))

;;; JSON conversion. Each part is checked here, at the point it leaves nshell,
;;; so a malformed part signals instead of producing JSON the schema rejects.

(defun %check (ok-p format-control &rest arguments)
  (unless ok-p
    (apply #'%invalid format-control arguments)))

(defun %object (&rest pairs)
  "Return an ordered JSON object of PAIRS, dropping the pairs whose value is
the keyword :OMIT."
  ;; MAKE-JSON-OBJECT, not ALIST->JSON-OBJECT: the latter returns a hash
  ;; table, and json-kit documents its member order as arbitrary.
  (json-kit:make-json-object
   (loop for (key value) on pairs by #'cddr
         unless (eq value :omit)
           collect (cons key value))))

(defun %optional (value converter)
  (if (null value) :omit (funcall converter value)))

(defun %string (value what)
  (%check (stringp value) "~A must be a string, not ~S." what value)
  value)

(defun %integer (value what)
  (%check (integerp value) "~A must be an integer, not ~S." what value)
  value)

(defun %boolean (value)
  (if value t json-kit:+json-false+))

(defun %array (items converter)
  (coerce (mapcar converter items) 'vector))

(defun %enum-string (keyword allowed what)
  (%check (member keyword allowed) "~A must be one of ~S, not ~S."
          what allowed keyword)
  (string-downcase (symbol-name keyword)))

(defun %output-json (output what)
  (%check (envelope-output-p output) "~A must be an ENVELOPE-OUTPUT, not ~S."
          what output)
  (%object "text" (%string (envelope-output-text output) "output text")
           "bytes" (%integer (envelope-output-bytes output) "output bytes")
           "lines" (%optional (envelope-output-lines output)
                              (lambda (lines) (%integer lines "output lines")))
           "truncated" (%boolean (envelope-output-truncated output))
           "path" (%optional (envelope-output-path output)
                             (lambda (path) (%string path "output path")))))

(defun %span-json (span)
  (%object "line" (%integer (envelope-span-line span) "span line")
           "column" (%integer (envelope-span-column span) "span column")
           "end" (%integer (envelope-span-end span) "span end")))

(defun %fix-json (fix)
  (%object "input" (%string (envelope-fix-input fix) "fix input")
           "why" (%optional (envelope-fix-why fix)
                            (lambda (why) (%string why "fix why")))
           "rule" (%optional (envelope-fix-rule fix)
                             (lambda (rule) (%string rule "fix rule")))))

(defun %coded-json (code allowed message span fixes what)
  (%check (member code allowed :test #'equal)
          "~A ~S is not in the error-code table." what code)
  (%object "code" code
           "message" (%optional message (lambda (text) (%string text "message")))
           "span" (%optional span #'%span-json)
           "fixes" (%optional fixes (lambda (items) (%array items #'%fix-json)))))

(defun %error-json (error-object)
  (%coded-json (envelope-error-code error-object) (envelope-error-codes)
               (envelope-error-message error-object)
               (envelope-error-span error-object)
               (envelope-error-fixes error-object)
               "error.code"))

(defun %warning-json (warning)
  (%coded-json (envelope-warning-code warning) (envelope-warning-codes)
               (envelope-warning-message warning)
               (envelope-warning-span warning)
               (envelope-warning-fixes warning)
               "warnings[].code"))

(defun %form-json (form)
  (%object "text" (%string (envelope-form-text form) "form text")
           "kind" (%string (envelope-form-kind form) "form kind")
           "rule" (if (envelope-form-rule form)
                      (%string (envelope-form-rule form) "form rule")
                      json-kit:+json-null+)
           "path" (%optional (envelope-form-path form)
                             (lambda (path) (%string path "form path")))))

(defun %effect-json (effect)
  (let ((size (envelope-effect-size effect)))
    (%check (or (null size) (integerp size) (stringp size))
            "effect size must be an integer or a string, not ~S." size)
    (%object "kind" (%enum-string (envelope-effect-kind effect) +effect-kinds+
                                  "effect kind")
             "path" (%optional (envelope-effect-path effect)
                               (lambda (path) (%string path "effect path")))
             "size" (if (null size) :omit size))))

(defun %safety-json (safety)
  (%object "level" (%enum-string (envelope-safety-level safety) +safety-levels+
                                 "safety level")
           "reasons" (%array (envelope-safety-reasons safety)
                             (lambda (reason)
                               (%object "rule" (%string (envelope-reason-rule reason)
                                                        "reason rule")
                                        "text" (%string (envelope-reason-text reason)
                                                        "reason text"))))))

(defun %job-json (job)
  (%check (and (listp job)
               (every (lambda (pair) (and (consp pair) (stringp (car pair)))) job))
          "A job must be an alist with string keys, not ~S." job)
  (json-kit:alist->json-object job))

(defun %state-json (state)
  (%object "cwd" (%string (envelope-state-cwd state) "state cwd")
           "env_changed" (%array (envelope-state-env-changed state)
                                 (lambda (name) (%string name "env_changed name")))
           "jobs" (%array (envelope-state-jobs state) #'%job-json)
           "last_status" (%optional (envelope-state-last-status state)
                                    (lambda (status) (%integer status "last_status")))))

(defun envelope-json-object (envelope)
  "Return ENVELOPE as an ordered json-kit object, in the key order of the ux/U6
examples. Signal an error when a part is outside the envelope's types."
  (%object "nshell_api" +nshell-api-version+
           "ok" (%boolean (envelope-ok-p envelope))
           "status" (%integer (envelope-status envelope) "status")
           "duration_ms" (%integer (envelope-duration-ms envelope) "duration_ms")
           "stdout" (%output-json (envelope-stdout envelope) "stdout")
           "stderr" (%output-json (envelope-stderr envelope) "stderr")
           "value" (if (envelope-value-present-p envelope)
                       (envelope-value envelope)
                       :omit)
           "error" (%optional (envelope-error envelope) #'%error-json)
           "warnings" (%optional (envelope-warnings envelope)
                                 (lambda (items) (%array items #'%warning-json)))
           "forms" (%optional (envelope-forms envelope)
                              (lambda (items) (%array items #'%form-json)))
           "effects" (%array (envelope-effects envelope) #'%effect-json)
           "safety" (%safety-json (envelope-safety envelope))
           "state" (%state-json (envelope-state envelope))
           "session" (%optional (envelope-session envelope)
                                (lambda (session) (%string session "session")))
           "seq" (%optional (envelope-seq envelope)
                            (lambda (seq) (%integer seq "seq")))))

(defun envelope-to-json (envelope)
  "Return ENVELOPE as one line of JSON text."
  (json-kit:stringify (envelope-json-object envelope)))
