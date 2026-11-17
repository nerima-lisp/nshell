(in-package #:nshell.feature.machine)

;;; `nshell --json --command INPUT` (proposal/02, ux/U6): run INPUT once
;;; through the batch path and describe the run as one envelope.
;;;
;;; The run happens in a worker thread so the calling thread can enforce the
;;; whole-run deadline (D-72), and stop the run early when a program switches
;;; to the alternate screen (ux/U6). At either the caller parks the worker
;;; inside an interrupt, stops every process the run spawned as whole process
;;; groups while nothing can start a new one, lets the output copiers drain,
;;; and then releases the worker, which unwinds out of the batch run instead of
;;; going on to the next command.
;;;
;;; SIGINT, SIGTERM and SIGHUP stop the run the same way and give
;;; E_INTERRUPTED. The deadline, a program on the alternate screen and these
;;; signals all claim the run's NONINTERACTIVE-STOP, and only the first claim
;;; stops the run: a later one changes neither the error nor the cleanup.

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
    ;; *query-io* and *debug-io* are synonyms of it.
    *terminal-io*
    *default-pathname-defaults*
    nshell.infrastructure.acl:*exported-environment*
    nshell.presentation:*noninteractive-batch-p*
    nshell.infrastructure.acl:*detach-child-standard-input*
    nshell.infrastructure.terminal:*terminal-color-depth*)
  "Dynamic bindings of the calling thread that the worker thread keeps; a new
SBCL thread otherwise sees only global values.")

(defstruct (json-run (:constructor %make-json-run))
  (status nil)
  (condition nil)
  ;; Signalled when the worker ends and when a program switches to the
  ;; alternate screen.
  (wake (sb-thread:make-semaphore))
  (alternate-screen-p nil)
  (user-code-p nil)
  ;; (COMMAND NAME-SPAN) of the last command that was not found, NAME-SPAN
  ;; the TEXT-SPAN of its name or NIL.
  (missing-command nil)
  (timed-out-p nil)
  ;; The car is the error code of the AI gate's last refusal, if any.
  (gate-refusal (list nil))
  ;; The car is (COMMAND ARGUMENTS NAME-SPAN) of the first full-screen program
  ;; the gate refused, NAME-SPAN the TEXT-SPAN of its name or NIL, if any.
  (full-screen-program (list nil))
  ;; The worker outlived the deadline's terminate-thread: its output streams
  ;; may still be written and its locks still held.
  (worker-alive-p nil)
  ;; The car lists every process group the run created (*PROCESS-GROUP-LOG*).
  (group-log (list nil))
  (stop (nshell.infrastructure.acl:make-noninteractive-stop))
  ;; The worker thread, the tag it catches, and the processes registered
  ;; before it started.
  (worker nil)
  (tag (list :json-run))
  (before nil)
  ;; The car becomes true when the worker must be terminated: until then,
  ;; once parked, it runs no interruption but the park (SEAL-INTERRUPTIONS).
  (admit (list nil))
  ;; Makes the worker's *ERROR-OUTPUT* write elsewhere (%MAKE-SWITCHABLE-OUTPUT).
  (switch-error-output nil))

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

(defun %worker-bindings (run tag out err timeout approval)
  (let ((symbols (copy-list +json-conveyed-specials+))
        (values (mapcar #'symbol-value +json-conveyed-specials+)))
    (flet ((bind (symbol value)
             (push symbol symbols)
             (push value values)))
      (bind '*standard-output* out)
      (multiple-value-bind (error-output switch)
          (nshell.presentation::%make-switchable-output err)
        (setf (json-run-switch-error-output run) switch)
        (bind '*error-output* error-output))
      (bind 'nshell.application::*exec-exit-function* (%exec-exit-function run tag))
      ;; Every process group the run creates, so the deadline can stop a
      ;; group whose leader was already reaped.
      (bind 'nshell.infrastructure.acl:*process-group-log* (json-run-group-log run))
      ;; No single external command wait may outlast the whole-run deadline.
      (bind 'nshell.infrastructure.acl:*external-command-timeout* timeout)
      ;; Every gate refusal of the run, nested ones and pipeline stages too.
      (bind 'nshell.application::*execution-gate-refusal* (json-run-gate-refusal run))
      (bind 'nshell.application::*full-screen-program-guard* (%full-screen-program-guard run))
      (bind 'nshell.infrastructure.acl:*process-output-watch* (%alternate-screen-watch run))
      (when approval
        ;; As after Enter on an AI proposal: with :SAFE the gate runs what
        ;; classifies :safe where it runs and refuses the rest, since no one
        ;; can approve; with :CONFIRM a person approved the input (--mcp).
        (bind 'nshell.application:*execution-origin* :proposal)
        (bind 'nshell.application:*execution-approval* approval)))
    (values symbols values)))

(defun %full-screen-program-guard (run)
  (let ((refused (json-run-full-screen-program run)))
    (lambda (command arguments name-span)
      (when (full-screen-program-kind command arguments)
        (unless (car refused)
          (setf (car refused) (list command arguments name-span)))
        t))))

(defun %alternate-screen-watch (run)
  (lambda ()
    (let ((scan (make-alternate-screen-scanner)))
      (lambda (buffer end)
        (when (and (not (json-run-alternate-screen-p run))
                   (null (nshell.infrastructure.acl:noninteractive-stop-reason
                          (json-run-stop run)))
                   (funcall scan buffer end)
                   (nshell.infrastructure.acl:claim-noninteractive-stop
                    (json-run-stop run) :interactive-program))
          (setf (json-run-alternate-screen-p run) t)
          (sb-thread:signal-semaphore (json-run-wake run)))))))

(defun %observe (run)
  (lambda (kind value &rest details)
    (ecase kind
      (:missing-command (setf (json-run-missing-command run)
                              (list value (first details))))
      (:command-failed (setf (json-run-condition run) value))
      (:crash (setf (json-run-condition run) value
                    (json-run-user-code-p run) (first details))))))

(defun %finish-worker (worker admit)
  "Join WORKER, terminating it when it does not finish in time, and return
true when it has exited. ADMIT lets the termination through the seal."
  (sb-thread:join-thread worker :default nil :timeout *json-unwind-seconds*)
  (when (sb-thread:thread-alive-p worker)
    (setf (car admit) t)
    (ignore-errors (sb-thread:terminate-thread worker))
    (sb-thread:join-thread worker :default nil :timeout *json-unwind-seconds*))
  (not (sb-thread:thread-alive-p worker)))

(defun %park-and-stop (worker tag before log admit switch-error-output)
  "Stop the run in WORKER after its deadline; see the comment at the top.
Return true when the worker has exited.

From the park on the worker runs no other interruption until it has left the
batch run (SEAL-INTERRUPTIONS, unless the car of ADMIT is set), and nothing
the unwinding writes to its *ERROR-OUTPUT* reaches the envelope
(SWITCH-ERROR-OUTPUT): a command substitution's timer could otherwise take the
unwind over, and SBCL's summary of an aborted compilation unit would join
stderr."
  (let ((parked (sb-thread:make-semaphore))
        (release (sb-thread:make-semaphore)))
    (handler-case
        (sb-thread:interrupt-thread
         worker
         (lambda ()
           (nshell.infrastructure.acl:seal-interruptions admit)
           (sb-thread:signal-semaphore parked)
           (sb-thread:wait-on-semaphore release :timeout 10)
           ;; Output the stopped command had captured but not yet passed on.
           (nshell.application::flush-pending-captured-output)
           (funcall switch-error-output (make-broadcast-stream))
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
    (let ((exited-p (%finish-worker worker admit)))
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

(defun %stop-run (run)
  "Stop RUN's worker and every process group of the run (%PARK-AND-STOP)."
  (setf (json-run-worker-alive-p run)
        (not (%park-and-stop (json-run-worker run) (json-run-tag run)
                             (json-run-before run) (json-run-group-log run)
                             (json-run-admit run)
                             (json-run-switch-error-output run)))))

(defun %run-batch-with-deadline (run input timeout approval errexit-p script-args out err
                                 reset-state-p)
  (let ((tag (json-run-tag run))
        (stop (json-run-stop run)))
    (setf (json-run-before run) (nshell.infrastructure.acl:registered-processes))
    (multiple-value-bind (symbols values)
        (%worker-bindings run tag out err timeout approval)
      ;; A signal that unwinds this thread finds the worker in RUN to stop.
      (sb-sys:without-interrupts
        (setf (json-run-worker run)
              (sb-thread:make-thread
               (lambda ()
                 (unwind-protect
                      (progv symbols values
                        (nshell.infrastructure.acl:call-with-sealable-interruptions
                         (lambda ()
                           (catch tag
                             (setf (json-run-status run)
                                   (nshell.presentation:run-repl-batch-observed
                                    input (%observe run)
                                    :script-args script-args
                                    :errexit-p errexit-p
                                    :reset-state-p reset-state-p))))))
                   (sb-thread:signal-semaphore (json-run-wake run))))
               :name "nshell json command")))
      (let ((woken-p (sb-thread:wait-on-semaphore (json-run-wake run) :timeout timeout)))
        (cond
          ((json-run-alternate-screen-p run) (%stop-run run))
          (woken-p (sb-thread:join-thread (json-run-worker run) :default nil))
          ((nshell.infrastructure.acl:claim-noninteractive-stop stop :timeout)
           (setf (json-run-timed-out-p run) t)
           (%stop-run run))
          (t
           ;; A signal or the alternate screen was claimed first.
           (nshell.infrastructure.acl:unwind-to-noninteractive-signal stop)
           (%stop-run run)))))
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

(defun %input-span (input start length)
  "Return the span of the LENGTH characters at START in INPUT: 1-based line and
column, END one past its last column."
  (let* ((line-start (let ((newline (position #\Newline input :end start :from-end t)))
                       (if newline (1+ newline) 0)))
         (column (1+ (- start line-start))))
    (make-envelope-span
     :line (1+ (count #\Newline input :end start))
     :column column
     :end (+ column length))))

(defun %input-name-span (input name-span)
  "Return the start and end in INPUT of NAME-SPAN, the TEXT-SPAN of a command
name, or NIL when NAME-SPAN is a position in another text: a sourced file, a
command substitution or a function body is read from a string of its own, so
only a span into INPUT itself, the string the batch run reads, is one."
  (when (and name-span
             (eq (nshell.domain.parsing:text-span-text name-span) input))
    (values (nshell.domain.parsing:text-span-start name-span)
            (nshell.domain.parsing:text-span-end name-span))))

(defun %input-fix-range (input name-span)
  "Return the start and end in INPUT of the command name NAME-SPAN covers
when a fix may replace it there: NAME-SPAN is a position in INPUT (see
%INPUT-NAME-SPAN) and not an alias word, whose expansion is not in INPUT, so
no rewrite of INPUT runs another command in its place.  A ^ marker the parser
read in front of the name stays out of the range, so the fix still skips
builtins, functions and aliases."
  (multiple-value-bind (start end) (%input-name-span input name-span)
    (when (and start
               (not (nshell.domain.parsing:text-span-alias-word-p name-span)))
      (values (if (nshell.domain.parsing:text-span-forced-external-p name-span)
                  (1+ start)
                  start)
              end))))

(defun %full-screen-program-fixes (input program start end)
  "The fixes for the full-screen PROGRAM, (COMMAND ARGUMENTS NAME-SPAN), refused
in INPUT with its name written between START and END: INPUT with the name
replaced by the noninteractive form."
  (destructuring-bind (command arguments name-span) program
    (declare (ignore name-span))
    (multiple-value-bind (replacement why)
        (full-screen-program-replacement command arguments)
      (when replacement
        (list (make-envelope-fix
               :input (concatenate 'string (subseq input 0 start) replacement
                                   (subseq input end))
               :why why))))))

(defun %missing-command-fixes (input status start end)
  "Return the fixes diagnose/typo gives for the command name written between
START and END in INPUT that could not be found: INPUT with the name replaced
by a name the shell can run now, builtins, functions, aliases and PATH
included."
  (knowledge-base-fixes
   (nshell.feature.kb:diagnose-typo
    :input input :status status :command-start start :command-end end
    :known-commands (nshell.presentation::%repl-known-command-names))))

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
  "Return the error code, the status to give ERROR-ENVELOPE, the message, the
span and the fixes of a run that did not end with status 0, or NIL when it
did."
  (let* ((condition (json-run-condition run))
         (code (%error-code-of condition))
         (missing (json-run-missing-command run))
         (refusal (car (json-run-gate-refusal run)))
         (full-screen (car (json-run-full-screen-program run)))
         (message (%first-line stderr-text)))
    (cond
      ((nshell.infrastructure.acl:noninteractive-stop-signal (json-run-stop run))
       (values "E_INTERRUPTED" nil
               (format nil "the run was interrupted by ~A"
                       (nshell.infrastructure.acl:stop-signal-name
                        (nshell.infrastructure.acl:noninteractive-stop-signal
                         (json-run-stop run))))))
      ((json-run-timed-out-p run)
       (values "E_TIMEOUT" nil (format nil "the run exceeded its ~A s deadline"
                                       (%seconds-text timeout))))
      ((json-run-alternate-screen-p run)
       (values "E_INTERACTIVE_PROGRAM" nil
               "a program switched the terminal to its alternate screen; the run was stopped"))
      (full-screen
       (destructuring-bind (command arguments name-span) full-screen
         (declare (ignore arguments))
         (multiple-value-bind (start end) (%input-name-span input name-span)
           (values "E_INTERACTIVE_PROGRAM" nil
                   (format nil "~A is a full-screen program; it was not started" command)
                   (and start (%input-span input start (- end start)))
                   (multiple-value-bind (start end) (%input-fix-range input name-span)
                     (and start
                          (%full-screen-program-fixes input full-screen start end)))))))
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
       (destructuring-bind (command name-span) missing
         (multiple-value-bind (start end) (%input-name-span input name-span)
           (values "E_COMMAND_NOT_FOUND" nil
                   (format nil "~A: command not found" command)
                   (and start (%input-span input start (- end start)))
                   (multiple-value-bind (start end) (%input-fix-range input name-span)
                     (and start
                          (%missing-command-fixes input status start end)))))))
      ((eql status 126) (values "E_PERMISSION" nil message))
      ((eql status 130) (values "E_INTERRUPTED" nil message))
      (t
       (values "E_COMMAND_FAILED" status
               (or message (format nil "the command exited with status ~D" status)))))))

(defun %store-full-output (stdout stderr out-text err-text &key session (seq 1))
  "Save the cleaned full text of each cut output as the files of run SEQ in
SESSION, a new output session by default, set its PATH, and return the
session, or NIL when nothing could be saved."
  (let* ((new-p (null session))
         ;; A kept session's directory may have been pruned meanwhile.
         (session (if new-p
                      (ignore-errors (open-output-session))
                      (reopen-output-session session)))
         (saved nil))
    (when session
      (flet ((save (output raw name)
               (when (envelope-output-truncated output)
                 (let ((path (output-session-write session name
                                                   (clean-output-text raw))))
                   (when path
                     (setf (envelope-output-path output) path
                           saved t))))))
        (save stdout out-text (format nil "~D.txt" seq))
        (save stderr err-text (format nil "~D.stderr.txt" seq)))
      (cond (saved (ignore-errors (prune-output-sessions :except session)))
            (new-p
             (ignore-errors
              (sb-posix:rmdir (string-right-trim "/" (output-session-directory session)))))))
    (and saved session)))

(defun %refusal-envelope (verdict effects duration-ms &key session seq)
  "The envelope of input refused at the Enter step: :BLOCK is never run, and
:CONFIRM needs an approval no one gave."
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
                    :state (%state)
                    :session session :seq seq)))

(defun %elapsed-ms (start)
  (round (* 1000 (- (get-internal-real-time) start))
         internal-time-units-per-second))

(defun %valid-json-timeout-p (timeout)
  (and (nshell.infrastructure.acl::timeout-seconds-p timeout)
       (plusp timeout)))

(defun run-json-command (input &key (timeout +json-default-timeout-seconds+)
                                    private environment-agent-p errexit-p
                                    script-args approved-verdict (reset-state-p t)
                                    session output-session (seq 1))
  "Run INPUT once as `nshell --command INPUT` does and return the envelope as
one line of JSON, the exit status, the envelope, and whether the run's worker
outlived the deadline and may still be running.

TIMEOUT is the whole-run deadline in seconds. PRIVATE keeps cut output from
being saved. ENVIRONMENT-AGENT-P (NSHELL_AGENT=1) refuses forms that are not
:safe instead of only reporting their safety level; APPROVED-VERDICT is the
verdict a person approved INPUT under, and when INPUT still classifies exactly
so only :block is refused. ERREXIT-P stops at the first
failing command, as -e does.

The --mcp server runs every call in one session: RESET-STATE-P false keeps
the shell state of the previous run instead of starting from a fresh batch
state, SESSION is the session id every envelope then carries with SEQ, and
OUTPUT-SESSION, when not NIL, is where cut output is saved as the files of
run SEQ."
  (check-type input string)
  (unless (%valid-json-timeout-p timeout)
    (error "The --json timeout must be a positive number of seconds, not ~S."
           timeout))
  (let ((start (get-internal-real-time))
        ;; Bound, not assigned: the batch state below sets the last two for
        ;; this run only, and a caller in the same image keeps its own.
        (nshell.presentation:*noninteractive-batch-p* t)
        (nshell.infrastructure.acl:*detach-child-standard-input* nil)
        (nshell.infrastructure.terminal:*terminal-color-depth* nil)
        (run (%make-json-run))
        (out (make-string-output-stream))
        (err (make-string-output-stream))
        (verdict nil)
        (readable-p nil)
        (effects nil)
        (approved-p nil)
        (out-text nil)
        (err-text nil))
    (flet ((run-envelope ()
             (let* (;; A worker that survived the deadline may still write them.
                    ;; Taken once: a signal after the envelope of a finished
                    ;; run was begun makes it again from the same output.
                    (out-text (or out-text
                                  (setf out-text (if (json-run-worker-alive-p run)
                                                     ""
                                                     (get-output-stream-string out)))))
                    (err-text (or err-text
                                  (setf err-text (if (json-run-worker-alive-p run)
                                                     ""
                                                     (get-output-stream-string err)))))
                    (status (or (json-run-status run) 1))
                    (stdout (envelope-output-for-text out-text))
                    (stderr (envelope-output-for-text err-text))
                    (saved (and (not private)
                                (or (envelope-output-truncated stdout)
                                    (envelope-output-truncated stderr))
                                (or (not session) output-session)
                                (%store-full-output stdout stderr out-text err-text
                                                    :session output-session :seq seq)))
                    (parts (list :duration-ms (%elapsed-ms start)
                                 :stdout stdout
                                 :stderr stderr
                                 :effects effects
                                 :safety (%envelope-safety-of verdict)
                                 :state (%state)
                                 :session (or session (and saved (output-session-id saved)))
                                 :seq (cond (session seq) (saved 1))))
                    (envelope
                      (multiple-value-bind (code code-status message span fixes)
                          (%failure run input status (clean-output-text err-text) timeout)
                        (if code
                            (apply #'error-envelope code :status code-status
                                                         :message message :span span
                                                         :fixes fixes parts)
                            (apply #'result-envelope :status 0 parts)))))
               (values (envelope-to-json envelope) (envelope-status envelope)
                       envelope (json-run-worker-alive-p run)))))
      (nshell.infrastructure.acl:call-with-noninteractive-signals
       (json-run-stop run)
       (lambda ()
         ;; A signal takes effect once the verdict every envelope reports is
         ;; known; nothing here waits on another process.
         (sb-sys:without-interrupts
           ;; The classifier resolves names in the batch shell state the run
           ;; uses.
           (if reset-state-p
               (nshell.presentation::%initialize-batch-state)
               ;; The kept state is a batch state already; only the two
               ;; settings bound above for this run are set as
               ;; %initialize-batch-state sets them.
               (setf nshell.infrastructure.acl:*detach-child-standard-input* t
                     nshell.infrastructure.terminal:*terminal-color-depth* :none))
           (multiple-value-setq (verdict readable-p) (%classify-input input))
           ;; Judged before the run, as the verdict is: the run may change
           ;; what the names resolve to.
           (setf effects (and readable-p (%input-effects input))
                 ;; Approval holds only for the verdict the person saw.
                 approved-p (and approved-verdict (equal approved-verdict verdict))))
         (if (and environment-agent-p readable-p
                  (member (first verdict) (if approved-p '(:block) '(:confirm :block))))
             (let ((envelope (%refusal-envelope verdict effects (%elapsed-ms start)
                                                :session session :seq (and session seq))))
               (values (envelope-to-json envelope) (envelope-status envelope)
                       envelope))
             (progn
               (%run-batch-with-deadline run input timeout
                                         (and environment-agent-p
                                              (if approved-p :confirm :safe))
                                         errexit-p script-args out err
                                         reset-state-p)
               (run-envelope))))
       :after-signal
       (lambda (signal)
         (declare (ignore signal))
         (when (json-run-worker run)
           (%stop-run run))
         (run-envelope))))))
