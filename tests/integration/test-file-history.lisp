(in-package #:nshell/test)

(def-suite file-history-tests
  :description "File-based history integration tests"
  :in nshell-tests)

(in-suite file-history-tests)

(test file-history-append
  "Appending to file history works"
  (let* ((test-path (format nil "/tmp/nshell-test-history-~d.lisp" (random 1000000))))
    (unwind-protect
         (progn
           ;; Override history file path for test isolation
           (setf nshell.infrastructure.persistence:*history-file-path-override*
                 (pathname test-path))
           ;; Clean up any previous test data
           (when (probe-file test-path) (delete-file test-path))
           (nshell.infrastructure.persistence:append-history-entry "test command")
           (let ((loaded (nshell.infrastructure.persistence:load-history-file)))
             (is (consp loaded))
             (is (string= "test command" (first loaded)))))
      ;; Cleanup
      (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
      (when (probe-file test-path) (delete-file test-path)))))

(test file-history-missing-file
  "Loading a missing history file returns NIL."
  (let* ((test-path (format nil "/tmp/nshell-test-history-missing-~d.lisp"
                            (random 1000000))))
    (unwind-protect
         (progn
           (setf nshell.infrastructure.persistence:*history-file-path-override*
                 (pathname test-path))
           (when (probe-file test-path) (delete-file test-path))
           (is (null (nshell.infrastructure.persistence:load-history-file))))
      (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
      (when (probe-file test-path) (delete-file test-path)))))
