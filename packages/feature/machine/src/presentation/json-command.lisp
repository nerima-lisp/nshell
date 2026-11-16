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

(defparameter *json-park-wait-seconds* 0.5
  "How long the deadline waits for the worker to acknowledge being parked.")

(defparameter *json-drain-seconds* 0.1
  "How long killed processes' output copiers get before the worker unwinds.")

(defparameter *json-unwind-seconds* 2
  "How long the worker gets to unwind and flush before it is terminated.")

;;; Safety

(defun %classify-input (input)
  "Return the verdict Enter gives INPUT as an AI proposal (D-P1-5 3.1), as
(LEVEL . REASONS) with REASONS a list of (RULE . TEXT), and as a second value
whether INPUT could be read. Unreadable input is :BLOCK, as at Enter; blank
input runs nothing and is :SAFE."
  (if (nshell.presentation::%blank-command-text-p input)
      (values (list :safe) t)
      (multiple-value-bind (status result)
          (nshell.presentation::%assistant-proposal-assessment input)
        (if (eq status :classified)
            (values (cons (nshell.feature.assistant:assistant-safety-result-classification
                           result)
                          (nshell.feature.assistant:assistant-safety-result-reasons
                           result))
                    t)
            (values (list :block (cons "classify/unparsable"
                                       "the input could not be read"))
                    nil)))))

(defun %envelope-safety-of (verdict)
  (destructuring-bind (level . reasons) verdict
    (make-envelope-safety
     :level level
     :reasons (unless (eq level :safe)
                (loop for (rule . text) in reasons
                      collect (make-envelope-reason :rule rule :text text))))))

(defun %input-effects (input)
  "Return the envelope effects of the commands INPUT runs, as explain reports
them, in the context the run starts in.  INPUT is input %CLASSIFY-INPUT could
read; the Enter assessment it uses returns only its verdict, so INPUT is read
again here, with the same reader context."
  (reader-results-effects
   (nshell.presentation::%make-repl-shell-context)
   (nshell.domain.parsing:read-submission
    input
    :reader-context (nshell.domain.parsing:submission-reader-context input))))

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
  (timed-out-p nil)
  ;; The car is the error code of the AI gate's last refusal, if any.
  (gate-refusal (list nil))
  ;; The worker outlived the deadline's terminate-thread: its output streams
  ;; may still be written and its locks still held.
  (worker-alive-p nil)
  ;; The car lists every process group the run created (*PROCESS-GROUP-LOG*).
  (group-log (list nil)))

(defun %exec-exit-function (run tag)
  "Return the *EXEC-EXIT-FUNCTION* of RUN, which gives exec under --json the
meaning it has in a POSIX shell.

exec inside a subshell-like context (a pipeline stage, a process
substitution, or a command substitution) ends only that context, with the
exec'd program's status as the context's status, and the run goes on: a
pipeline still joins and closes all its stages and has its normal status (the
last stage's, or under pipefail the first nonzero one), and a command
substitution yields what its commands wrote before exec followed by the
exec'd program's output.

exec anywhere else (at top level, in a function called there, or in a file
sourced from there) ends the run with the program's status: no later command
runs. It records the status and throws to TAG; the unwinding runs every
cleanup of the commands it leaves, so their process substitutions are still
waited for and closed before the envelope is made.

Either way the output that commands before exec produced and that is still
held in the process reaches its destination before the program's output (see
RUN-DELIVERING-CAPTURED-OUTPUT)."
  (lambda (program)
    (if nshell.application::*subshell-exit-function*
        (funcall nshell.application::*subshell-exit-function* program)
        (progn
          (setf (json-run-status run)
                (nshell.application::run-delivering-captured-output program))
          (throw tag :exec)))))

(defun %worker-bindings (run tag out err timeout agent-p)
  (let ((symbols (copy-list +json-conveyed-specials+))
        (values (mapcar #'symbol-value +json-conveyed-specials+)))
    (flet ((bind (symbol value)
             (push symbol symbols)
             (push value values)))
      (bind '*standard-output* out)
      (bind '*error-output* err)
      (bind 'nshell.application::*exec-exit-function* (%exec-exit-function run tag))
      ;; Every process group the run creates, so the deadline can stop a
      ;; group whose leader was already reaped.
      (bind 'nshell.infrastructure.acl:*process-group-log* (json-run-group-log run))
      ;; No single external command wait may outlast the whole-run deadline.
      (bind 'nshell.infrastructure.acl:*external-command-timeout* timeout)
      ;; Every gate refusal of the run, nested ones and pipeline stages too.
      (bind 'nshell.application::*execution-gate-refusal* (json-run-gate-refusal run))
      (when agent-p
        ;; As after Enter on a safe AI proposal: the gate runs what classifies
        ;; :safe where it runs and refuses the rest, since no one can approve.
        (bind 'nshell.application:*execution-origin* :proposal)
        (bind 'nshell.application:*execution-approval* :safe)))
    (values symbols values)))

(defun %observe (run)
  (lambda (kind value &rest details)
    (ecase kind
      (:missing-command (setf (json-run-missing-command run) value))
      (:command-failed (setf (json-run-condition run) value))
      (:crash (setf (json-run-condition run) value
                    (json-run-user-code-p run) (first details))))))

(defun %finish-worker (worker)
  "Join WORKER, terminating it when it does not finish in time, and return
true when it has exited."
  (sb-thread:join-thread worker :default nil :timeout *json-unwind-seconds*)
  (when (sb-thread:thread-alive-p worker)
    (ignore-errors (sb-thread:terminate-thread worker))
    (sb-thread:join-thread worker :default nil :timeout *json-unwind-seconds*))
  (not (sb-thread:thread-alive-p worker)))

(defun %park-and-stop (worker tag before log)
  "Stop the run in WORKER after its deadline; see the comment at the top.
Return true when the worker has exited."
  (let ((parked (sb-thread:make-semaphore))
        (release (sb-thread:make-semaphore)))
    (handler-case
        (sb-thread:interrupt-thread
         worker
         (lambda ()
           (sb-thread:signal-semaphore parked)
           (sb-thread:wait-on-semaphore release :timeout 10)
           ;; Output the stopped command had captured but not yet passed on.
           (nshell.application::flush-pending-captured-output)
           ;; The worker may already have left the CATCH for TAG.
           (ignore-errors (throw tag :deadline))))
      (error () nil))
    (sb-thread:wait-on-semaphore parked :timeout *json-park-wait-seconds*)
    (nshell.infrastructure.acl:stop-process-groups
     (set-difference (nshell.infrastructure.acl:registered-processes) before
                     :test #'eq)
     :groups (car log))
    (sleep *json-drain-seconds*)
    (sb-thread:signal-semaphore release)
    (let ((exited-p (%finish-worker worker)))
      (flet ((run-processes ()
               (set-difference (nshell.infrastructure.acl:registered-processes)
                               before :test #'eq))
             (reap (processes)
               ;; Not while a live worker may hold the waitpid lock.
               (when exited-p
                 (dolist (process processes)
                   (ignore-errors
                     (nshell.infrastructure.acl:process-alive-p process))))))
        ;; Reap the killed processes first: a group left with only zombies
        ;; still answers kill 0 and would cost another grace period.
        (reap (run-processes))
        ;; What is left: a process spawned before the interrupt took effect.
        (let ((late (run-processes)))
          (nshell.infrastructure.acl:stop-process-groups late :groups (car log))
          (reap late))
        exited-p))))

(defun %run-batch-with-deadline (input timeout agent-p errexit-p script-args out err)
  (let* ((run (%make-json-run))
         (tag (list :json-run))
         (before (nshell.infrastructure.acl:registered-processes)))
    (multiple-value-bind (symbols values)
        (%worker-bindings run tag out err timeout agent-p)
      (let ((worker
              (sb-thread:make-thread
               (lambda ()
                 (progv symbols values
                   (catch tag
                     (setf (json-run-status run)
                           (nshell.presentation:run-repl-batch-observed
                            input (%observe run)
                            :script-args script-args :errexit-p errexit-p)))))
               :name "nshell json command")))
        (sb-thread:join-thread worker :default nil :timeout timeout)
        (when (sb-thread:thread-alive-p worker)
          (setf (json-run-timed-out-p run) t
                (json-run-worker-alive-p run)
                (not (%park-and-stop worker tag before (json-run-group-log run)))))))
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

(defun %seconds-text (seconds)
  "SECONDS as a decimal: 120, 1.5."
  (if (integerp seconds)
      (format nil "~D" seconds)
      (string-right-trim "." (string-right-trim "0" (format nil "~,6F" seconds)))))

(defun %failure (run input status stderr-text timeout)
  "Return the error code, the status to give ERROR-ENVELOPE, the message and
the span of a run that did not end with status 0, or NIL when it did."
  (let* ((condition (json-run-condition run))
         (code (%error-code-of condition))
         (missing (json-run-missing-command run))
         (refusal (car (json-run-gate-refusal run)))
         (message (%first-line stderr-text)))
    (cond
      ((json-run-timed-out-p run)
       (values "E_TIMEOUT" nil (format nil "the run exceeded its ~A s deadline"
                                       (%seconds-text timeout))))
      ;; The input did not run as given once the AI gate refused part of it,
      ;; whatever the status of the commands after that part.
      (refusal (values refusal nil message))
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

(defun %refusal-envelope (verdict effects duration-ms)
  "The envelope of input refused at the Enter step: :BLOCK is never run, and
:CONFIRM needs an approval no one can give under --json."
  (destructuring-bind (level . reasons) verdict
    (error-envelope (if (eq level :block) "E_BLOCKED_BY_POLICY" "E_NEEDS_APPROVAL")
                    :message (format nil "~A: ~A"
                                     (if (eq level :block)
                                         "blocked by policy"
                                         "approval required")
                                     (cdr (first reasons)))
                    :duration-ms duration-ms
                    :stdout (output-from-text "")
                    :stderr (output-from-text "")
                    :effects effects
                    :safety (%envelope-safety-of verdict)
                    :state (%state))))

(defun %elapsed-ms (start)
  (round (* 1000 (- (get-internal-real-time) start))
         internal-time-units-per-second))

(defun %valid-json-timeout-p (timeout)
  (and (nshell.infrastructure.acl::timeout-seconds-p timeout)
       (plusp timeout)))

(defun run-json-command (input &key (timeout +json-default-timeout-seconds+)
                                    private environment-agent-p errexit-p
                                    script-args)
  "Run INPUT once as `nshell --command INPUT` does and return the envelope as
one line of JSON, the exit status, and the envelope.

TIMEOUT is the whole-run deadline in seconds. PRIVATE keeps cut output from
being saved. ENVIRONMENT-AGENT-P (NSHELL_AGENT=1) refuses forms that are not
:safe instead of only reporting their safety level. ERREXIT-P stops at the
first failing command, as -e does."
  (check-type input string)
  (unless (%valid-json-timeout-p timeout)
    (error "The --json timeout must be a positive number of seconds, not ~S."
           timeout))
  (let ((start (get-internal-real-time)))
    ;; The classifier resolves names in the batch shell state the run uses.
    (nshell.presentation::%initialize-batch-state)
    (multiple-value-bind (verdict readable-p) (%classify-input input)
      ;; Judged before the run, as the verdict is: the run may change what
      ;; the names resolve to.
      (let ((level (first verdict))
            (effects (and readable-p (%input-effects input))))
        (when (and environment-agent-p readable-p (member level '(:confirm :block)))
          (let ((envelope (%refusal-envelope verdict effects (%elapsed-ms start))))
            (return-from run-json-command
              (values (envelope-to-json envelope) (envelope-status envelope)
                      envelope))))
        (let* ((out (make-string-output-stream))
               (err (make-string-output-stream))
               (run (%run-batch-with-deadline input timeout environment-agent-p
                                              errexit-p script-args out err))
               ;; A worker that survived the deadline may still write them.
               (out-text (if (json-run-worker-alive-p run)
                             ""
                             (get-output-stream-string out)))
               (err-text (if (json-run-worker-alive-p run)
                             ""
                             (get-output-stream-string err)))
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
                            :effects effects
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
