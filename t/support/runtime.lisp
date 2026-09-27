(in-package #:nshell/test)

(defparameter +nshell-runtime-dependencies+
  '(:cl-prolog-kit :cl-parser-kit :cl-dataflow-kit :cl-boundary-kit :cl-cli
    :cl-tty-kit :cl-process-kit :cl-history-kit :cl-host-kit :cl-log-kit
    :cl-concurrent-kit :cl-codec-kit :cl-date-kit :cl-json-kit)
  "ASDF systems whose source directories a fresh nshell subprocess needs.
The list includes transitive dependencies because subprocess bootstrap uses an
explicit central registry rather than inheriting the parent's registry.")

(defparameter +e2e-child-environment-names+
  '("HOME" "LANG" "LC_ALL" "LC_CTYPE" "LC_MESSAGES" "LC_MONETARY"
    "LC_NUMERIC" "LC_TIME" "LOGNAME" "PATH" "SHELL" "TERM" "TMPDIR"
    "USER")
  "Stable host values needed by real-process E2E tests.

Do not pass the test runner's ASDF/SBCL, nshell, or tool-specific environment
through a child PTY. Those values describe the runner rather than the shell
under test and can change startup, source lookup, or persistent state.")

(defun %e2e-child-environment ()
  "Return the deliberately small environment used by E2E child processes."
  (let ((allowed (make-hash-table :test #'equal))
        (temporary (namestring (host-kit:temporary-directory))))
    (dolist (name +e2e-child-environment-names+)
      (setf (gethash name allowed) t))
    (append (list (format nil "HOME=~A" temporary)
                  (format nil "XDG_CACHE_HOME=~A" temporary))
            (remove-if
             (lambda (entry)
               (let ((separator (position #\= entry)))
                 (or (and separator
                          (member (subseq entry 0 separator)
                                  '("HOME" "XDG_CACHE_HOME")
                                  :test #'string=))
                     (not (and separator
                               (gethash (subseq entry 0 separator) allowed))))))
             (nshell.infrastructure.acl:current-environment-entries)))))

(defun %e2e-pty-spawn (program args &rest keys)
  "Spawn an E2E PTY without inheriting the test runner's environment."
  (apply #'nshell.infrastructure.acl:pty-spawn
         program args :environment (%e2e-child-environment) keys))
