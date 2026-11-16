(in-package #:nshell.application)

(defvar *output-captures* nil
  "Every in-process holder of output that has not reached its destination
yet, innermost first, as (STREAM . DESTINATION): a string stream bound as a
command's standard stream, or a collector of the output commands return as
values (WITH-OUTPUT-COLLECTOR). DESTINATION is the standard stream in effect
when the holder was made. :SUBSHELL marks where a subshell-like context
starts (CALL-WITH-SUBSHELL-EXIT); what is held inside it belongs to that
context.")

(defmacro with-output-collector ((stream) &body body)
  "Run BODY with STREAM bound to a new string stream that is registered on
*OUTPUT-CAPTURES*, with *STANDARD-OUTPUT* as its destination, while BODY runs."
  `(let* ((,stream (make-string-output-stream))
          (*output-captures* (acons ,stream *standard-output* *output-captures*)))
     ,@body))

(defun %deliver-captures (captures)
  "Empty CAPTURES, a run of *OUTPUT-CAPTURES* entries innermost first, along
the path their output takes when each holder's consumer passes it on: into
the next enclosing holder when that one was made under the same standard
stream (a value returned to the collector around it), and otherwise to the
holder's own DESTINATION (a value a redirection writes out, or the context's
standard stream). Going innermost first keeps every byte in the order the
normal return path would give it."
  (loop for (capture . outer) on captures
        for next = (first outer)
        do (write-string (get-output-stream-string (car capture))
                         (if (and (consp next) (eq (cdr next) (cdr capture)))
                             (car next)
                             (cdr capture)))))

(defun flush-pending-captured-output ()
  "Deliver what the holders outside every subshell-like context hold (see
%DELIVER-CAPTURES). Only a caller about to unwind past them calls this: the
--json deadline."
  (let* ((captures *output-captures*)
         (barrier (position :subshell captures :from-end t)))
    (%deliver-captures (if barrier (nthcdr (1+ barrier) captures) captures))))

(defun run-delivering-captured-output (program)
  "Call PROGRAM, a function of no arguments, between two deliveries of what
the current context's holders hold (the entries above its :SUBSHELL mark, or
every entry outside all subshell-like contexts), and return its value. exec
calls it right before it leaves the context, which unwinds the holders: the
output the context's commands produced reaches its destination ahead of the
exec'd program's, and the program's own output does not stay in a holder."
  (let ((captures (ldiff *output-captures* (member :subshell *output-captures*))))
    (%deliver-captures captures)
    (prog1 (funcall program)
      (%deliver-captures captures))))

(defun %call-capturing-standard-output (thunk)
  "Call THUNK with *STANDARD-OUTPUT* bound to a string stream and return what
it wrote, as WITH-OUTPUT-TO-STRING does, keeping the stream on
*OUTPUT-CAPTURES* while THUNK runs."
  (with-output-collector (stream)
    (let ((*standard-output* stream))
      (funcall thunk))
    (get-output-stream-string stream)))

(defun %finish-external-pipeline-process
    (process stdout-buffer stderr-buffer redirect-plan command pgid)
  (let ((*output-captures*
          (let ((captures (acons stdout-buffer *standard-output* *output-captures*)))
            (if stderr-buffer (acons stderr-buffer *error-output* captures) captures)))
        (copiers
          (%start-external-process-copiers
           process stdout-buffer stderr-buffer))
        (timeout
          (nshell.infrastructure.acl:%foreground-external-command-timeout)))
    (flet ((collect-output (status)
             (%finish-external-process-output
              stdout-buffer stderr-buffer redirect-plan status))
           (continue-stopped-process ()
             (%continue-stopped-external-process pgid))
           (report-timeout ()
             (format *error-output*
                     "nshell: ~a: timed out after ~a seconds~%"
                     command timeout)))
      (unwind-protect
           (if (null timeout)
               (nshell.infrastructure.acl:%wait-process-with-copiers-or-stop
                process copiers
                (lambda ()
                  (collect-output
                   (nshell.infrastructure.acl:process-exit-status-code
                    process)))
                #'continue-stopped-process)
               (nshell.infrastructure.acl:%wait-process-with-copiers
                process copiers timeout
                (lambda ()
                  (collect-output
                   (nshell.infrastructure.acl:process-exit-status-code
                    process)))
                (lambda ()
                  (report-timeout)
                  (collect-output 124))))
        (when (and process
                   (nshell.infrastructure.acl:process-alive-p process)
                   (not (eq (nshell.infrastructure.acl:process-status process) :stopped)))
          (ignore-errors (nshell.infrastructure.acl:process-wait process)))))))
