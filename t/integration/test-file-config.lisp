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
          (delete-file test-path)))))

  (it "interactive-startup-sources-config"
    "Interactive initialization applies .nshellrc through the normal source boundary."
    (let* ((config-path (format nil "/tmp/nshell-test-startup-config-~d.lisp"
                                (random 1000000)))
           (history-path (format nil "/tmp/nshell-test-startup-history-~d"
                                 (random 1000000))))
      (unwind-protect
           (progn
             (with-open-file (stream config-path
                                      :direction :output
                                      :if-exists :supersede
                                      :if-does-not-exist :create)
               (write-line "set -x NSHELL_CONFIG_LOADED yes" stream))
             (setf nshell.infrastructure.persistence::*config-file-path-override*
                   (pathname config-path)
                   nshell.infrastructure.persistence::*history-file-path-override*
                   (pathname history-path))
             (nshell.presentation::initialize-repl-state)
             (expect "yes" :to-equal (repl-test-env "NSHELL_CONFIG_LOADED")))
        (setf nshell.infrastructure.persistence::*config-file-path-override* nil
              nshell.infrastructure.persistence::*history-file-path-override* nil)
        (when (probe-file config-path)
          (delete-file config-path))
        (when (probe-file history-path)
          (delete-file history-path))))))
