;;; Test-harness helpers: environment probes, skip macros, and the entry point.
;;;
;;; This file holds no tests.  It is loaded before every suite so the skip
;;; macros below are available while the suites are being read, which is why it
;;; sits third in the nshell/test :components list, right after the package and
;;; the shared assertions.  Tests for src/main.lisp live in t/main-test.lisp.

(in-package #:nshell/test)

(defun in-hermetic-sandbox-p ()
  "True in hermetic Nix builds, not in impure nix develop shells.
Real OS process and PTY integration tests are skipped only when the surrounding
environment is expected to hide facilities such as /bin/sh, /bin/cat, or PTYs."
  (and (uiop:getenv "NIX_BUILD_TOP")
       (not (string= (or (uiop:getenv "IN_NIX_SHELL") "")
                     "impure"))))

(defmacro skip-in-sandbox (reason &body body)
  "Run BODY only when not in a hermetic sandbox; otherwise skip with REASON."
  `(if (in-hermetic-sandbox-p)
       (skip (format nil "~a (skipped in hermetic sandbox)" ,reason))
       (progn ,@body)))

(defmacro skip-when-pty-round-trip-unreliable (reason &body body)
  "Run BODY only where raw PTY master/slave round-trip I/O is reliable.

Reading bytes straight back through a PTY depends on the terminal line
discipline, which differs across platforms and is not honored by hosted CI
runners, so skip both the hermetic sandbox and CI."
  `(if (or (in-hermetic-sandbox-p) (uiop:getenv "CI"))
       (skip (format nil "~a (skipped in sandbox/CI)" ,reason))
       (progn ,@body)))

(defun run-tests ()
  "Run all nshell tests through cl-weave.

Runs single-threaded: many suites share process-global state (mock command
tables, abbreviation/alias/history registries, dynamic completion hooks), so
concurrent execution would race.  This mirrors how the FiveAM suite ran."
  (run-all :reporter :spec :max-workers 1 :pass-with-no-tests nil))
