;;; Explicit OS boundaries for the REPL edge.
;;;
;;; nshell's domain and application layers are pure, but the presentation edge
;;; still reaches the outside world for a handful of effects: the prompt reads
;;; the hostname and working directory, command timing reads a monotonic clock,
;;; and completion lists the filesystem.  cl-boundary-kit makes each of those an
;;; explicit, swappable boundary.
;;;
;;; A single boundary-context is created at session start (`make-real-boundary-
;;; context`) and bound to `*boundaries*`.  It defaults to the real host
;;; implementations, so behavior is unchanged; tests bind `*boundaries*` to a
;;; context of fakes (`make-test-host-info`, `make-test-working-directory`,
;;; `make-fake-clock`, ...) to make the prompt and timing deterministic without
;;; touching the machine.
(in-package #:nshell.presentation)

(defvar *boundaries* nil
  "The active cl-boundary-kit boundary-context for this REPL session, or NIL to
fall back to freshly-constructed real boundaries.")

(defun make-real-boundary-context ()
  "Construct a boundary-context wired to the real host: filesystem, host info,
working directory, monotonic clock, environment, and process execution."
  (cl-boundary-kit:make-boundary-context
   :filesystem (cl-boundary-kit:make-filesystem)
   :host-info (cl-boundary-kit:make-host-info)
   :working-dir (cl-boundary-kit:make-working-directory
                 :get-fn #'host-kit:getcwd :set-fn #'host-kit:chdir)
   :clock (cl-boundary-kit:make-clock)
   :environment (cl-boundary-kit:make-environment)
   :process (cl-boundary-kit:make-process-boundary)))

(defun %boundary (key default-thunk)
  "Return the boundary registered under KEY, or a fresh real one from
DEFAULT-THUNK when no context (or no such boundary) is present.  Reading through
this keeps callers safe even before `*boundaries*` is initialized."
  (if *boundaries*
      (cl-boundary-kit:boundary-context-get *boundaries* key (funcall default-thunk))
      (funcall default-thunk)))

(defun boundary-host-info ()
  (%boundary :host-info #'cl-boundary-kit:make-host-info))

(defun boundary-working-directory ()
  (%boundary :working-dir #'cl-boundary-kit:make-working-directory))

(defun boundary-clock ()
  (%boundary :clock #'cl-boundary-kit:make-clock))

(defun boundary-hostname ()
  "Current hostname via the host-info boundary, defaulting to \"localhost\"."
  (or (cl-boundary-kit:host-info-hostname (boundary-host-info)) "localhost"))

(defun boundary-current-directory ()
  "Current working directory namestring via the working-directory boundary."
  (namestring (cl-boundary-kit:working-directory-get (boundary-working-directory))))

(defun boundary-monotonic ()
  "Monotonic tick from the clock boundary (internal-time-units for the real
clock), used to measure command duration."
  (cl-boundary-kit:clock-monotonic (boundary-clock)))
