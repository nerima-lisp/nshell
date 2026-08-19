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

  (it "file-history-multiline-round-trip"
    "Multiline command history survives persistence."
    (let* ((test-path (format nil "/tmp/nshell-test-history-multiline-~d.lisp"
                              (random 1000000)))
           (command (format nil "for item in one two~%  echo $item~%done")))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (when (probe-file test-path) (delete-file test-path))
             (nshell.infrastructure.persistence:append-history-entry command)
             (expect (list command) :to-equal
                     (nshell.infrastructure.persistence:load-history-file)))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (when (probe-file test-path) (delete-file test-path)))))

  (it "file-history-unframed-lines"
    "Unframed history records are not loaded."
    (let ((test-path (format nil "/tmp/nshell-test-history-unframed-~d.lisp"
                             (random 1000000))))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (when (probe-file test-path) (delete-file test-path))
             (with-open-file (stream test-path :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (format stream "unframed one~%unframed two~%"))
             (expect (nshell.infrastructure.persistence:load-history-file) :to-be-null))
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
