(in-package #:nshell.feature.machine)

;;; `nshell --json --command INPUT` (proposal/02, ux/U6): run INPUT once
;;; through the batch path and describe the run as one envelope.
;;;
;;; The run happens in a worker thread so the calling thread can enforce the
;;; whole-run deadline (D-72). At the deadline the caller parks the worker
;;; inside an interrupt, stops every process the run spawned as whole process
;;; groups while nothing can start a new one, lets the output copiers drain,
;;; and then releases the worker, which unwinds out of the batch run instead of
;;; going on to the next command.

(defconstant +default-json-timeout-seconds+ 120
  "The whole-run deadline of --json when --timeout is not given.")

(defparameter *json-park-wait-seconds* 0.5
  "How long the deadline waits for the worker to acknowledge being parked.")

(defparameter *json-drain-seconds* 0.1
  "How long killed processes' output copiers get before the worker unwinds.")

(defparameter *json-unwind-seconds* 2
  "How long the worker gets to unwind and flush before it is terminated.")

;;; Safety

(defun %classification-rank (level)
  (case level (:safe 0) (:confirm 1) (otherwise 2)))

(defun %verdict (result)
  "Return the (LEVEL RULE TEXT) of the classifier's RESULT."
  (let ((rule (nshell.feature.assistant:assistant-safety-result-rule-name result)))
    (list (nshell.feature.assistant:assistant-safety-result-classification result)
          (if rule (string-downcase (symbol-name rule)) "classify/unknown")
          (or (nshell.feature.assistant:assistant-safety-result-reason result) ""))))

(defun %unclassifiable (text)
  (list :confirm "classify/unknown" text))

(defun %classify-reader-result (reader-result)
  "Classify READER-RESULT the way the AI execution gate classifies what it
reaches: an S-expression command form is converted to its command AST first."
  (let ((form (nshell.domain.parsing:reader-result-form reader-result)))
    (cond
      ((or (nshell.domain.parsing:command-node-p form)
           (nshell.domain.parsing:pipeline-node-p form)
           (nshell.domain.parsing:sequence-node-p form))
       (%verdict (nshell.feature.assistant:classify-ast form)))
      ((consp form)
       (handler-case
           (%verdict
            (nshell.feature.assistant:classify-ast
             (nshell.domain.parsing:command-form->ast
              (nshell.domain.parsing:reader-result-source reader-result)
              form
              (nshell.domain.parsing:reader-result-form-span-map reader-result)
              (lambda (head-source)
                (declare (ignore head-source))
                :command-island))))
         (error ()
           (%unclassifiable "unclassifiable S-expression form"))))
      (t (%unclassifiable "unclassifiable form")))))

(defun %classify-input (input)
  "Return the most restrictive (LEVEL RULE TEXT) of INPUT's forms, (:SAFE)
when INPUT has none, and as a second value whether INPUT could be read."
  (handler-case
      (let ((verdicts (mapcar #'%classify-reader-result
                              (nshell.domain.parsing:read-submission input))))
        (values (if verdicts
                    (reduce (lambda (left right)
                              (if (> (%classification-rank (first right))
                                     (%classification-rank (first left)))
                                  right
                                  left))
                            verdicts)
                    (list :safe))
                t))
    (error ()
      (values (%unclassifiable "the input could not be parsed") nil))))

(defun %envelope-safety-of (verdict)
  (destructuring-bind (level &optional rule text) verdict
    (make-envelope-safety
     :level level
     :reasons (unless (eq level :safe)
                (list (make-envelope-reason :rule rule :text text))))))

;;; Running

(defparameter +json-conveyed-specials+
  '(*standard-input*
    *default-pathname-defaults*
    nshell.infrastructure.acl:*exported-environment*)
  "Dynamic bindings of the calling thread that the worker thread keeps; a new
SBCL thread otherwise sees only global values.")

(defstruct (json-run (:constructor %make-json-run))
  (status nil)
  (condition nil)
  (user-code-p nil)
  (missing-command nil)
  (timed-out-p nil))

(defun %worker-bindings (out err timeout agent-p)
  (let ((symbols (copy-list +json-conveyed-specials+))
        (values (mapcar #'symbol-value +json-conveyed-specials+)))
    (flet ((bind (symbol value)
             (push symbol symbols)
             (push value values)))
      (bind '*standard-output* out)
      (bind '*error-output* err)
      (bind 'nshell.application::*abandoned-process-output-function*
            (lambda (stdout-text stderr-text)
              (write-string stdout-text out)
              (write-string stderr-text err)))
      ;; No single wait may outlast the whole-run deadline.
      (bind 'nshell.infrastructure.acl:*external-command-timeout* timeout)
      (bind 'nshell.application::*command-substitution-timeout*
            (min timeout nshell.application::*command-substitution-timeout*))
      (when agent-p
        ;; The existing AI gate then runs :safe forms and refuses the rest.
        (bind 'nshell.application::*execution-origin* :proposal)
        (bind 'nshell.application::*execution-confirmed-p* nil)))
    (values symbols values)))

(defun %observe (run)
  (lambda (kind value &rest details)
    (ecase kind
      (:missing-command (setf (json-run-missing-command run) value))
      (:command-failed (setf (json-run-condition run) value))
      (:crash (setf (json-run-condition run) value
                    (json-run-user-code-p run) (first details))))))

(defun %park-and-stop (worker tag before)
  "Stop the run in WORKER after its deadline; see the comment at the top."
  (let ((parked (sb-thread:make-semaphore))
        (release (sb-thread:make-semaphore)))
    (handler-case
        (sb-thread:interrupt-thread
         worker
         (lambda ()
           (sb-thread:signal-semaphore parked)
           (sb-thread:wait-on-semaphore release :timeout 10)
           ;; The worker may already have left the CATCH for TAG.
           (ignore-errors (throw tag :deadline))))
      (error () nil))
    (sb-thread:wait-on-semaphore parked :timeout *json-park-wait-seconds*)
    (nshell.infrastructure.acl:stop-process-groups
     (set-difference (nshell.infrastructure.acl:registered-processes) before
                     :test #'eq))
    (sleep *json-drain-seconds*)
    (sb-thread:signal-semaphore release)
    (when (eq :unfinished
              (sb-thread:join-thread worker :default :unfinished
                                            :timeout *json-unwind-seconds*))
      (ignore-errors (sb-thread:terminate-thread worker))
      (sb-thread:join-thread worker :default nil :timeout *json-unwind-seconds*))
    ;; A process the worker spawned before the interrupt took effect.
    (let ((late (set-difference (nshell.infrastructure.acl:registered-processes)
                                before :test #'eq)))
      (nshell.infrastructure.acl:stop-process-groups late)
      ;; Reap what was killed so no zombie outlives the run.
      (dolist (process late)
        (ignore-errors (nshell.infrastructure.acl:process-alive-p process))))))

(defun %run-batch-with-deadline (input timeout agent-p script-args out err)
  (let* ((run (%make-json-run))
         (tag (list :json-run))
         (before (nshell.infrastructure.acl:registered-processes)))
    (multiple-value-bind (symbols values) (%worker-bindings out err timeout agent-p)
      (let ((worker
              (sb-thread:make-thread
               (lambda ()
                 (progv symbols values
                   (catch tag
                     (setf (json-run-status run)
                           (nshell.presentation:run-repl-batch-observed
                            input (%observe run) :script-args script-args)))))
               :name "nshell json command")))
        (when (eq :unfinished
                  (sb-thread:join-thread worker :default :unfinished
                                                :timeout timeout))
          (setf (json-run-timed-out-p run) t)
          (%park-and-stop worker tag before))))
    run))

;;; Envelope

(defun %current-directory ()
  "The working directory as the shell reports it: PWD when it names the
process's directory, the physical directory otherwise."
  (string-right-trim
   "/"
   (or (ignore-errors
        (nshell.application::%logical-current-directory
         nshell.presentation::*environment*
         (nshell.infrastructure.acl:current-working-directory)))
       (namestring (nshell.infrastructure.acl:current-working-directory)))))

(defun %state ()
  (let ((directory (%current-directory)))
    (make-envelope-state :cwd (if (zerop (length directory)) "/" directory))))

(defun %word-delimiter-p (char)
  (member char '(#\Space #\Tab #\Newline #\Return #\( #\) #\; #\| #\& #\< #\>
                 #\" #\')))

(defun %word-span (input word)
  "Return the span of the first occurrence of WORD in INPUT as a whole word:
1-based line and column, END one past its last column."
  (let ((length (length word)))
    (when (plusp length)
      (loop for start = (search word input)
              then (search word input :start2 (1+ start))
            while start
            for end = (+ start length)
            when (and (or (zerop start) (%word-delimiter-p (char input (1- start))))
                      (or (= end (length input)) (%word-delimiter-p (char input end))))
              return (let* ((line-start (let ((newline (position #\Newline input
                                                                 :end start
                                                                 :from-end t)))
                                          (if newline (1+ newline) 0)))
                            (column (1+ (- start line-start))))
                       (make-envelope-span
                        :line (1+ (count #\Newline input :end start))
                        :column column
                        :end (+ column length)))))))

(defun %first-line (text)
  (let ((line (string-trim '(#\Space #\Tab #\Return)
                           (subseq text 0 (or (position #\Newline text)
                                              (length text))))))
    (and (plusp (length line)) line)))

(defun %condition-line (condition)
  "Return CONDITION's report on one line, or NIL when it is empty."
  (let* ((report (handler-case (princ-to-string condition)
                   (error () "")))
         (words (loop with start = 0
                      for space = (position-if #'%blank-p report :start start)
                      for word = (subseq report start space)
                      when (plusp (length word)) collect word
                      while space
                      do (setf start (1+ space)))))
    (and words (format nil "~{~A~^ ~}" words))))

(defun %blank-p (char)
  (member char '(#\Space #\Tab #\Newline #\Return)))

(defun %error-code-of (condition)
  "Return CONDITION's E_ code, E_INTERNAL when it carries a code the table
does not list as an error, or NIL when it carries none."
  (when (typep condition 'nshell.domain.error-codes:nshell-error-code-mixin)
    (let ((code (nshell.domain.error-codes:condition-error-code condition)))
      (if (member code (envelope-error-codes) :test #'equal)
          code
          "E_INTERNAL"))))

(defun %failure (run input status stderr-text timeout)
  "Return the error code, the status to give ERROR-ENVELOPE, the message and
the span of a run that did not end with status 0, or NIL when it did."
  (let* ((condition (json-run-condition run))
         (code (%error-code-of condition))
         (missing (json-run-missing-command run))
         (message (%first-line stderr-text)))
    (cond
      ((json-run-timed-out-p run)
       (values "E_TIMEOUT" nil (format nil "the run exceeded its ~A s deadline" timeout)))
      ((equal code "E_PARSE")
       (values code nil "the input could not be parsed"))
      ((and code (string/= code "E_COMMAND_FAILED"))
       (values code nil (or (%condition-line condition) message)))
      ((and condition (not code))
       (values (if (json-run-user-code-p run) "E_LISP_ERROR" "E_INTERNAL")
               nil
               (or (%condition-line condition) message)))
      ((eql status 0) nil)
      ((and (eql status 127) missing)
       (values "E_COMMAND_NOT_FOUND" nil
               (format nil "~A: command not found" missing)
               (%word-span input missing)))
      ((eql status 126) (values "E_PERMISSION" nil message))
      ((eql status 130) (values "E_INTERRUPTED" nil message))
      (t
       (values "E_COMMAND_FAILED" status
               (or message (format nil "the command exited with status ~D" status)))))))

(defun %store-full-output (stdout stderr out-text err-text)
  "Save the cleaned full text of each cut output in a new output session, set
its PATH, and return the session, or NIL when nothing could be saved."
  (let ((session (ignore-errors (open-output-session)))
        (saved nil))
    (when session
      (flet ((save (output raw name)
               (when (envelope-output-truncated output)
                 (let ((path (output-session-write session name
                                                   (clean-output-text raw))))
                   (when path
                     (setf (envelope-output-path output) path
                           saved t))))))
        (save stdout out-text "1.txt")
        (save stderr err-text "1.stderr.txt"))
      (if saved
          (ignore-errors (prune-output-sessions :except session))
          (ignore-errors
           (sb-posix:rmdir (string-right-trim "/" (output-session-directory session))))))
    (and saved session)))

(defun %refusal-envelope (verdict duration-ms)
  (destructuring-bind (level rule text) verdict
    (declare (ignore rule))
    (error-envelope (if (eq level :block) "E_BLOCKED_BY_POLICY" "E_NEEDS_APPROVAL")
                    :message (format nil "~A: ~A"
                                     (if (eq level :block)
                                         "blocked by policy"
                                         "approval required")
                                     text)
                    :duration-ms duration-ms
                    :stdout (output-from-text "")
                    :stderr (output-from-text "")
                    :effects nil
                    :safety (%envelope-safety-of verdict)
                    :state (%state))))

(defun %elapsed-ms (start)
  (round (* 1000 (- (get-internal-real-time) start))
         internal-time-units-per-second))

(defun %valid-json-timeout-p (timeout)
  (and (nshell.infrastructure.acl::timeout-seconds-p timeout)
       (plusp timeout)))

(defun run-json-command (input &key (timeout +default-json-timeout-seconds+)
                                    private environment-agent-p script-args)
  "Run INPUT once as `nshell --command INPUT` does and return the envelope as
one line of JSON, the exit status, and the envelope.

TIMEOUT is the whole-run deadline in seconds. PRIVATE keeps cut output from
being saved. ENVIRONMENT-AGENT-P (NSHELL_AGENT=1) refuses forms that are not
:safe instead of only reporting their safety level."
  (check-type input string)
  (unless (%valid-json-timeout-p timeout)
    (error "The --json timeout must be a positive number of seconds, not ~S."
           timeout))
  (let ((start (get-internal-real-time)))
    (multiple-value-bind (verdict readable-p) (%classify-input input)
      (let ((level (first verdict)))
        (when (and environment-agent-p readable-p (member level '(:confirm :block)))
          (let ((envelope (%refusal-envelope verdict (%elapsed-ms start))))
            (return-from run-json-command
              (values (envelope-to-json envelope) (envelope-status envelope)
                      envelope))))
        (let* ((out (make-string-output-stream))
               (err (make-string-output-stream))
               (run (%run-batch-with-deadline input timeout environment-agent-p
                                              script-args out err))
               (out-text (get-output-stream-string out))
               (err-text (get-output-stream-string err))
               (status (or (json-run-status run) 1))
               (stdout (envelope-output-for-text out-text))
               (stderr (envelope-output-for-text err-text))
               (session (and (not private)
                             (or (envelope-output-truncated stdout)
                                 (envelope-output-truncated stderr))
                             (%store-full-output stdout stderr out-text err-text)))
               (parts (list :duration-ms (%elapsed-ms start)
                            :stdout stdout
                            :stderr stderr
                            :effects nil
                            :safety (%envelope-safety-of verdict)
                            :state (%state)
                            :session (and session (output-session-id session))
                            :seq (and session 1)))
               (envelope
                 (multiple-value-bind (code code-status message span)
                     (%failure run input status (clean-output-text err-text) timeout)
                   (if code
                       (apply #'error-envelope code :status code-status
                                                    :message message :span span parts)
                       (apply #'result-envelope :status 0 parts)))))
          (values (envelope-to-json envelope) (envelope-status envelope)
                  envelope))))))
