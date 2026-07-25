(in-package #:nshell/test)

(describe "file-config-tests"
  (it "file-config-missing-file"
    "Loading a missing config file returns NIL."
    (let* ((test-path (format nil "/tmp/nshell-test-config-missing-~d.lisp"
                              (random 1000000))))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence::*config-file-path-override*
                   (pathname test-path))
             (when (probe-file test-path)
               (delete-file test-path))
             (expect (nshell.infrastructure.persistence:load-config) :to-be-null))
        (setf nshell.infrastructure.persistence::*config-file-path-override* nil)
        (when (probe-file test-path)
          (delete-file test-path)))))

  (it "file-config-roundtrip"
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
             (expect t :to-be (nshell.infrastructure.persistence:save-config config))
             (expect config :to-equal (nshell.infrastructure.persistence:load-config)))
        (setf nshell.infrastructure.persistence::*config-file-path-override* nil)
        (when (probe-file test-path)
          (delete-file test-path))))))
