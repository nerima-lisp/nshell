(in-package #:nshell/test)

(def-suite file-config-tests
  :description "File-based config integration tests"
  :in nshell-tests)

(in-suite file-config-tests)

(test file-config-missing-file
  "Loading a missing config file returns NIL."
  (let* ((test-path (format nil "/tmp/nshell-test-config-missing-~d.lisp"
                            (random 1000000))))
    (unwind-protect
         (progn
           (setf nshell.infrastructure.persistence::*config-file-path-override*
                 (pathname test-path))
           (when (probe-file test-path)
             (delete-file test-path))
           (is (null (nshell.infrastructure.persistence:load-config))))
      (setf nshell.infrastructure.persistence::*config-file-path-override* nil)
      (when (probe-file test-path)
        (delete-file test-path)))))

(test file-config-roundtrip
  "Saving and loading config preserves the stored lines."
  (let* ((test-path (format nil "/tmp/nshell-test-config-~d.lisp"
                            (random 1000000)))
         (config '("set -g prompt nshell"
                   "export PATH=/usr/local/bin:$PATH"
                   "")))
    (unwind-protect
         (progn
           (setf nshell.infrastructure.persistence::*config-file-path-override*
                 (pathname test-path))
           (when (probe-file test-path)
             (delete-file test-path))
           (is (eq t (nshell.infrastructure.persistence:save-config config)))
           (is (equal config (nshell.infrastructure.persistence:load-config))))
      (setf nshell.infrastructure.persistence::*config-file-path-override* nil)
      (when (probe-file test-path)
        (delete-file test-path)))))
