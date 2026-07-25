(in-package #:nshell/test)

(describe "file-history-tests"
  (it "file-history-append"
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
               (expect (consp loaded) :to-be-truthy)
               (expect "test command" :to-equal (first loaded))))
        ;; Cleanup
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (when (probe-file test-path) (delete-file test-path)))))

  (it "file-history-missing-file"
    "Loading a missing history file returns NIL."
    (let* ((test-path (format nil "/tmp/nshell-test-history-missing-~d.lisp"
                              (random 1000000))))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (when (probe-file test-path) (delete-file test-path))
             (expect (nshell.infrastructure.persistence:load-history-file) :to-be-null))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (when (probe-file test-path) (delete-file test-path))))))
