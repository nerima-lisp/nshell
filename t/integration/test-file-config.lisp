(in-package #:nshell/test)

(describe "file-config-tests"
  (it "file-config-missing-file"
    "Loading a missing config file returns NIL."
    (host-kit:with-temporary-directory (directory)
      (let ((test-path (merge-pathnames "config-missing.lisp" directory)))
        (unwind-protect
             (progn
               (setf nshell.infrastructure.persistence::*config-file-path-override*
                     test-path)
               (when (probe-file test-path)
                 (delete-file test-path))
               (expect (nshell.infrastructure.persistence:load-config) :to-be-null))
          (setf nshell.infrastructure.persistence::*config-file-path-override* nil)
          (when (probe-file test-path)
            (delete-file test-path))))))

  (it "file-config-roundtrip"
    "Saving and loading config preserves the stored lines."
    (host-kit:with-temporary-directory (directory)
      (let ((test-path (merge-pathnames "config.lisp" directory))
            (config '("set -g prompt nshell"
                      "export PATH=/usr/local/bin:$PATH"
                      "")))
        (unwind-protect
             (progn
               (setf nshell.infrastructure.persistence::*config-file-path-override*
                     test-path)
               (when (probe-file test-path)
                 (delete-file test-path))
               (expect t :to-be (nshell.infrastructure.persistence:save-config config))
               (expect config :to-equal (nshell.infrastructure.persistence:load-config)))
          (setf nshell.infrastructure.persistence::*config-file-path-override* nil)
          (when (probe-file test-path)
            (delete-file test-path))))))

  (it "interactive-startup-sources-config"
    "Interactive initialization applies .nshellrc through the normal source boundary."
    (host-kit:with-temporary-directory (directory)
      (let ((config-path (merge-pathnames "startup-config.lisp" directory))
            (history-path (merge-pathnames "startup-history" directory)))
        (unwind-protect
             (progn
               (with-open-file (stream config-path
                                        :direction :output
                                        :if-exists :supersede
                                        :if-does-not-exist :create)
                 (write-line "set -x NSHELL_CONFIG_LOADED yes" stream))
               (setf nshell.infrastructure.persistence::*config-file-path-override*
                     config-path
                     nshell.infrastructure.persistence::*history-file-path-override*
                     history-path)
               (nshell.presentation::initialize-repl-state)
               (expect "yes" :to-equal (repl-test-env "NSHELL_CONFIG_LOADED")))
          (setf nshell.infrastructure.persistence::*config-file-path-override* nil
                nshell.infrastructure.persistence::*history-file-path-override* nil)
          (when (probe-file config-path)
            (delete-file config-path))
          (when (probe-file history-path)
            (delete-file history-path))))))
  (it "interactive-config-reports-nonzero-status"
    "A nonzero sourced config status is reported on standard error."
    (with-temporary-functions
        (((quote nshell.infrastructure.persistence:load-config)
          (lambda () (list "ignored")))
         ((quote nshell.presentation::%execute-with-repl-shell-context)
          (lambda (thunk)
            (declare (ignore thunk))
            (values nil 7))))
      (let ((message
              (with-output-to-string (*error-output*)
                (nshell.presentation::%load-interactive-config))))
        (expect (format nil "nshell: .nshellrc exited with status 7~%") :to-equal message))))
  (it "interactive-config-reports-loading-errors"
    "An error while loading .nshellrc is reported on standard error."
    (with-temporary-function
        ((quote nshell.infrastructure.persistence:load-config)
         (lambda () (error "broken config")))
      (let ((message
              (with-output-to-string (*error-output*)
                (nshell.presentation::%load-interactive-config))))
        (expect (format nil "nshell: .nshellrc: broken config~%") :to-equal message)))))
