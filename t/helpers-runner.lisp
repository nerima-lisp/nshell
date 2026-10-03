;;; Test-harness helpers: environment probes, skip macros, and the entry point.
;;;
;;; This file holds no tests.  It is loaded before every suite so the skip
;;; macros below are available while the suites are being read, which is why it
;;; sits third in the nshell/test :components list, right after the package and
;;; the shared assertions.  Tests for src/main.lisp live in t/main-test.lisp.

(in-package #:nshell/test)

(cl-weave:around-each (next)
  "Keep subprocess exports from one test from changing the next test's PATH."
  (let ((nshell.infrastructure.acl:*exported-environment* nil))
    (funcall next)))

(defun in-hermetic-sandbox-p ()
  "True in hermetic Nix builds, not in impure nix develop shells.
Real OS process and PTY integration tests are skipped only when the surrounding
environment is expected to hide facilities such as /bin/sh, /bin/cat, or PTYs."
  (and (not (string= (or (host-kit:getenv "NSHELL_TEST_PTY") "") "1"))
       (host-kit:getenv "NIX_BUILD_TOP")
       (not (string= (or (host-kit:getenv "IN_NIX_SHELL") "")
                     "impure"))))

(defmacro skip-in-sandbox (reason &body body)
  "Run BODY only when not in a hermetic sandbox; otherwise skip with REASON."
  `(if (in-hermetic-sandbox-p)
       (skip (format nil "~a (skipped in hermetic sandbox)" ,reason))
       (progn ,@body)))

(defparameter *pty-availability* :unknown
  "Cached result of the process-local PTY availability probe.")

(defun pty-available-p ()
  "Return true when this process can open and close a PTY pair."
  (case *pty-availability*
    (:available t)
    (:unavailable nil)
    (otherwise
     (multiple-value-bind (master slave slave-name)
         (handler-case (nshell.infrastructure.acl:open-pty)
           (sb-posix:syscall-error (condition)
             (if (member (sb-posix:syscall-errno condition)
                         (list sb-posix:eacces sb-posix:eperm sb-posix:enoent
                               sb-posix:enodev sb-posix:enxio sb-posix:enosys))
                 (progn
                   (setf *pty-availability* :unavailable)
                   (return-from pty-available-p nil))
                 (error condition))))
       (declare (ignore slave-name))
       (nshell.infrastructure.acl:pty-close master slave)
       (setf *pty-availability* :available)
       t))))

(defmacro skip-when-pty-unavailable (reason &body body)
  "Run BODY only when a usable PTY is available outside a hermetic sandbox."
  `(if (or (in-hermetic-sandbox-p)
           (not (pty-available-p)))
       (skip (format nil "~a (skipped in sandbox/unavailable PTY)" ,reason))
       (progn ,@body)))

(defmacro skip-when-pty-round-trip-unreliable (reason &body body)
  "Run BODY only where raw PTY master/slave round-trip I/O is reliable.

Reading bytes straight back through a PTY depends on the terminal line
discipline. The hermetic Nix sandbox cannot provide this integration
facility, but the non-sandboxed CI job is required to exercise it."
  `(cond
     ((in-hermetic-sandbox-p)
      (skip (format nil "~a (skipped in hermetic sandbox)" ,reason)))
     ((not (pty-available-p))
      (if (host-kit:getenv "CI")
          (error "~a (PTY unavailable in CI)" ,reason)
          (skip (format nil "~a (unavailable PTY)" ,reason))))
     (t
      (progn ,@body))))

(defun run-tests ()
  "Run all nshell tests through cl-weave.

Runs single-threaded: many suites share process-global state (mock command
tables, abbreviation/alias/history registries, shared mutable registries), so
concurrent execution would race.  This mirrors how the FiveAM suite ran.
Each test has a bounded execution time so a hung subprocess is reported as a
test failure instead of blocking the entire verification indefinitely."
  (let ((discovery-stream (make-string-output-stream)))
    (let* ((plan (cl-weave:list-tests :reporter :sexp
                                      :stream discovery-stream))
           (selected-count (length plan)))
      (unless (plusp selected-count)
        (error "nshell test discovery selected no tests"))
      (let* ((events (cl-weave:run (cl-weave:root-suite)
                                   :reporter :spec
                                   :max-workers 1
                                   :timeout-ms 120000))
             (passed-p (cl-weave:results-status events)))
        (format t "~&NSHELL_TESTS selected=~D passed=~A~%"
                selected-count
                passed-p)
        (finish-output)
        (values passed-p selected-count)))))
