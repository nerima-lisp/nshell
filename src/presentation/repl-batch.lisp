;;; Batch REPL execution
(in-package #:nshell.presentation)

(defvar *noninteractive-batch-p* nil
  "True when a batch run follows ux/U6 for machine callers: --json binds it,
and so does NSHELL_AGENT=1 for every batch entry point. Its children start
from +NONINTERACTIVE-CHILD-ENVIRONMENT+ with /dev/null as standard input, and
nshell's own output has no color. The interactive shell never reads it.")

(defun %noninteractive-child-environment (environment)
  (reduce (lambda (environment entry)
            (nshell.domain.environment:env-set environment (car entry) (cdr entry) t))
          nshell.feature.machine:+noninteractive-child-environment+
          :initial-value environment))

(defun %initialize-batch-state ()
  "Reset the global shell state for a non-interactive (batch or script) run."
  (setf *repl-filesystem* (nshell.infrastructure.acl:make-host-filesystem)
        *running* t
        *last-exit-code* 0
        *pipefail* nil
        *last-command-duration-ms* nil
        *last-command-output* nil
        *last-command-text* nil
        *history* (history-kit:make-history)
        *history-persistence-enabled-p* nil
        *failure-explain-available-p* nil
        *agent-session* nil
        *assistant-session-id* nil
        *assistant-pending-transcript* nil
        nshell.application:*agent-start-handler* nil
        nshell.application:*ai-reset-handler* nil
        ;; A script inspects and sets the same shell state an interactive
        ;; session does, so the handlers the builtins reach through are
        ;; installed here too.
        nshell.application:*theme-apply-handler* (function apply-repl-theme)
        nshell.application:*bind-table-handler* (function bind-dispatch-handler)
        nshell.application:*prompt-format-apply-handler* (function apply-prompt-format)
        nshell.application:*prompt-format-query-handler* (function current-prompt-format)
        nshell.application:*prompt-preview-handler* (function preview-prompt-format)
        *prompt-rendered-terminal-width* +default-terminal-width+
        *prompt-rendered-prompt-width* 0
        *interactive-terminal-installed-p* nil
        *config* (nshell.domain.configuration:default-config)
        *kb* (seed-repl-completion-knowledge-base
              (nshell.domain.completion:make-empty-knowledge-base))
        *environment* (nshell.application:seed-shell-status-environment
                       (nshell.domain.environment:inject-os-environment
                        (nshell.domain.environment:make-default-environment)
                        (nshell.infrastructure.acl:current-environment-entries)
                        (function nshell.infrastructure.acl:current-working-directory))))
  ;; Batch and -c never issue terminal probes, but explicit configuration and
  ;; the locale fallback still apply.
  (when *noninteractive-batch-p*
    (setf *environment* (%noninteractive-child-environment *environment*)
          nshell.infrastructure.acl:*detach-child-standard-input* t
          nshell.infrastructure.terminal:*terminal-color-depth* :none))
  (%apply-east-asian-ambiguous-width :interactive-p nil)
  (nshell.feature.assistant:reset-assistant-usage)
  (nshell.feature.assistant:reset-assistant-settings)
  (%reset-repl-state-tables))

;;; RUN-REPL-BATCH-OBSERVED binds this to a function of (KIND VALUE &rest
;;; DETAILS) so a caller learns why a run ended without parsing its stderr.
(defvar *batch-outcome-observer* nil)

(defun %observe-batch-outcome (kind value &rest details)
  (when *batch-outcome-observer*
    (apply *batch-outcome-observer* kind value details)))

(defun %run-batch-source-lines (lines)
  (let ((command-not-found-command nil)
        (command-not-found-span nil))
    (call-with-crash-capture
     (lambda ()
        (multiple-value-bind (output code)
            (let ((nshell.infrastructure.acl:*command-not-found-hook*
                    (lambda (command)
                      (setf command-not-found-command command
                            command-not-found-span
                            nshell.infrastructure.acl:*external-command-span*))))
              (%with-repl-shell-context (context)
                (handler-case
                    (nshell.application:source-lines-to-stream context lines)
                  (nshell.application:command-failed (condition)
                    (%observe-batch-outcome :command-failed condition)
                    (values
                     nil
                     (or
                      (nshell.application::command-failed-pipeline-status
                       condition)
                      (nshell.application:command-failed-status
                       condition)))))))
          (declare (ignore output))
          (setf *last-exit-code* (or code 0))
          (when command-not-found-command
            (%observe-batch-outcome :missing-command command-not-found-command
                                   command-not-found-span))
          (when (and (= *last-exit-code* 127)
                     command-not-found-command)
            (let ((corrections
                    (%repl-command-corrections command-not-found-command)))
              (when corrections
                (format *error-output* "nshell: did you mean: ~{~a~^, ~}?~%" corrections))))
          *last-exit-code*))
     (lambda (crash)
       (%observe-batch-outcome
        :crash
        (nshell.infrastructure.persistence:crash-record-condition crash)
        (%crash-in-user-code-p crash))
       (format *error-output* "nshell error: ~a~%"
               (if (%crash-storage-p crash) "storage exhausted" (%crash-message crash)))
       (%record-crash-log crash *error-output*)
       (setf *last-exit-code* 1)))))

(defparameter *batch-interrupt-drain-seconds* 0.1
  "How long the output copiers of the processes a signal stopped get before
the captured output is written out.")

(defun %background-job-groups ()
  "Return (PGID . PROCESSES) for every job in *PROC-REGISTRY* whose process
group is not this shell's."
  (let ((jobs '()))
    (maphash
     (lambda (job-id entry)
       (let* ((processes (nshell.infrastructure.acl:pipeline-stage-processes entry))
              (job (nshell.domain.job-control:monitor-find-job
                    nshell.application:*job-monitor*
                    job-id))
              (pgid (and job
                         (nshell.domain.execution:job-control-pgid job))))
         (when (and pgid
                    (not (and (integerp nshell.application:*shell-pgid*)
                              (= pgid nshell.application:*shell-pgid*))))
           (push (cons pgid processes) jobs))))
     *proc-registry*)
    jobs))

(defun %call-with-batch-interruption (thunk)
  "Call THUNK, a whole batch or script run, so that SIGINT, SIGTERM and SIGHUP
end it (BUG-4), and return the exit status: THUNK's value, or 128 plus the
signal number.

On the first signal the run's processes stop as at the --json deadline,
except its background jobs: SIGHUP is passed on to those, SIGINT and SIGTERM
leave them running, as sh and bash do without a terminal. What the
interrupted command had captured is written out, before the unwinding
discards it, and one line on stderr names the signal."
  (let* ((stop (nshell.infrastructure.acl:make-noninteractive-stop))
         (before (nshell.infrastructure.acl:registered-processes))
         (log (list nil)))
    (labels ((jobs ()
               ;; Read in an interrupt of the thread that updates the table;
               ;; when that fails the jobs are stopped with the rest.
               (ignore-errors (%background-job-groups)))
             (run-processes (jobs)
               (remove-if (lambda (process)
                            (or (member process before :test #'eq)
                                (some (lambda (job)
                                        (member process (cdr job) :test #'eq))
                                      jobs)))
                          (nshell.infrastructure.acl:registered-processes)))
             (stop-run (processes jobs)
               (nshell.infrastructure.acl:stop-process-groups
                processes :groups (set-difference (car log) (mapcar #'car jobs))))
             (reap (processes)
               (dolist (process processes)
                 (ignore-errors
                   (nshell.infrastructure.acl:process-alive-p process)))))
      (let ((nshell.infrastructure.acl:*process-group-log* log))
        (nshell.infrastructure.acl:call-with-noninteractive-signals
         stop thunk
         :before-unwind
         (lambda (signal)
           ;; In the interrupted command's dynamic context: its captured
           ;; output is still reachable here and gone after the unwind.
           ;; Nothing here may wait for a process lock this thread can hold.
           (let ((jobs (jobs)))
             (when (= signal sb-unix:sighup)
               (dolist (job jobs)
                 (ignore-errors
                   (nshell.infrastructure.acl:kill-process (- (car job)) :sighup))))
             (stop-run (run-processes jobs) jobs))
           (sleep *batch-interrupt-drain-seconds*)
           (ignore-errors (nshell.application::flush-pending-captured-output)))
         :after-signal
         (lambda (signal)
           ;; Reap the stopped processes first: a group left with only
           ;; zombies still answers kill 0 and would cost another grace
           ;; period. What is left was spawned while the signal was
           ;; arriving, or was started by a cleanup of the unwinding.
           (let ((jobs (jobs)))
             (reap (run-processes jobs))
             (let ((late (run-processes jobs)))
               (stop-run late jobs)
               (reap late)))
           (ignore-errors (finish-output *standard-output*))
           (format *error-output* "nshell: interrupted by ~A~%"
                   (nshell.infrastructure.acl:stop-signal-name signal))
           (setf *last-exit-code* (+ 128 signal))))))))

(defun %run-repl-batch (line script-args errexit-p reset-state-p)
  (when reset-state-p
    (%initialize-batch-state))
  (let ((nshell.domain.expansion:*positional-args* script-args)
        (nshell.application:*errexit-p* errexit-p))
    (if line
        (%run-batch-source-lines (list line))
        (%run-batch-source-lines
         (nshell.application:collect-source-lines *standard-input*))))
  *last-exit-code*)

(defun run-repl-batch (&key line script-args (errexit-p nil) (reset-state-p t))
  "Batch mode for stdin or the nshell-specific --command option.
SCRIPT-ARGS are exposed as $argv for --command. RESET-STATE-P false runs LINE
in the shell state the previous batch run left."
  (%call-with-batch-interruption
   (lambda () (%run-repl-batch line script-args errexit-p reset-state-p))))

(defun run-repl-batch-observed (line observer &key script-args errexit-p
                                                   (reset-state-p t))
  "Run LINE as RUN-REPL-BATCH does and return its exit status. OBSERVER is
called with :MISSING-COMMAND, the last command name that was not found and its
source span (NIL when unknown),
:COMMAND-FAILED and the condition that ended the run, or :CRASH, the condition
and whether the user's own Lisp code signalled it. Signals are left to the
caller (RUN-JSON-COMMAND)."
  (let ((*batch-outcome-observer* observer))
    (%run-repl-batch line script-args errexit-p reset-state-p)))
(defun run-repl-shell-command (command arguments
                              &key (load-config-p t) config-path)
  "Load the interactive startup configuration and delegate COMMAND to /bin/sh."
  (let ((*standard-output* (make-broadcast-stream))
        (*error-output* (make-broadcast-stream)))
    (initialize-repl-state :load-config-p load-config-p
                           :config-path config-path
                           :history-p nil))
  (sync-exported-environment)
  (nshell.infrastructure.acl:run-shell-command
   command arguments (exported-environment-strings)))

(defun %read-repl-script-source-text (path)
  (with-open-file (stream path :direction :input)
    (format nil "~{~a~^~%~}"
            (nshell.application:collect-source-lines stream))))

(defun %report-repl-script-source-diagnostic (condition path)
  ;; The condition can come from another file, such as an autoloaded
  ;; function file; locate it in the text of the file it names.
  (format *error-output* "~a~%"
          (format-sexpr-source-diagnostic-for-input
           condition (%read-repl-script-source-text path)))
  (let ((span
          (and (typep condition 'nshell.domain.parsing:sexp-reader-error)
               (nshell.domain.parsing:sexp-reader-error-source-span
                condition))))
    (setf *last-exit-code*
          (if (and (consp span)
                   (consp (cdr span))
                   (integerp (first span))
                   (integerp (second span))
                   (< (first span) (second span)))
              2
              1))))

(deftype repl-script-diagnostic-condition ()
  "Source errors that RUN-REPL-SCRIPT reports with their location. They are
diagnostics of the script, not crashes, so no crash log is written for them."
  '(or nshell.domain.parsing:sexp-reader-error
       nshell.application:sexp-evaluation-syntax-error
       nshell.application:command-macro-syntax-error))

(defun run-repl-script (path &optional script-args)
  "Execute the script file at PATH (multiline blocks supported, via the same
block-aware reader as the source builtin). SCRIPT-ARGS are exposed to the
script as $argv. Returns the exit status of the last command, or 128 plus
the number of the signal that ended the script."
  (%call-with-batch-interruption
   (lambda () (%run-repl-script path script-args))))

(defun %run-repl-script (path script-args)
  (%initialize-batch-state)
  (handler-case
      (call-with-crash-capture
       (lambda ()
         (let ((nshell.domain.expansion:*positional-args* script-args))
           (multiple-value-bind (output code)
               (%with-repl-shell-context (context)
                 (call-with-crash-capture
                  (lambda ()
                    (with-open-file (stream path :direction :input)
                      (nshell.application:source-lines-to-stream
                       context
                       (nshell.application:collect-source-lines stream)
                       path)))
                  (lambda (crash)
                    (%record-crash-log crash *error-output*)
                    (values (format nil "source: ~a: ~a~%" path (%crash-message crash))
                            1))
                  :pass-through 'repl-script-diagnostic-condition))
             (when output (write-string output *standard-output*))
             (setf *last-exit-code* (or code 0)))))
       (lambda (crash)
         (format *error-output* "nshell: ~a~%" (%crash-message crash))
         (%record-crash-log crash *error-output*)
         (setf *last-exit-code* 1))
       :pass-through 'repl-script-diagnostic-condition)
    (nshell.domain.parsing:sexp-reader-error (condition)
      (%report-repl-script-source-diagnostic condition path))
    (nshell.application:sexp-evaluation-syntax-error (condition)
      (%report-repl-script-source-diagnostic condition path))
    (nshell.application:command-macro-syntax-error (condition)
      (%report-repl-script-source-diagnostic condition path)))
  *last-exit-code*)
