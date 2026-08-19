(in-package #:nshell/test)

(describe "file-history-tests"
  (it "file-history-append"
    "Appending to file history works"
    (host-kit:with-temporary-directory (directory)
      (let ((test-path (merge-pathnames "history.lisp" directory)))
        (unwind-protect
             (progn
               ;; Override history file path for test isolation
               (setf nshell.infrastructure.persistence:*history-file-path-override*
                     test-path)
               ;; Clean up any previous test data
               (when (probe-file test-path) (delete-file test-path))
               (nshell.infrastructure.persistence:append-history-entry "test command")
               (let ((loaded (nshell.infrastructure.persistence:load-history-file)))
                 (expect (consp loaded) :to-be-truthy)
                 (expect "test command" :to-equal (first loaded))))
          ;; Cleanup
          (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
          (when (probe-file test-path) (delete-file test-path))))))

  (it "file-history-multiline-round-trip"
    "Multiline command history survives persistence."
    (host-kit:with-temporary-directory (directory)
      (let ((test-path (merge-pathnames "history-multiline.lisp" directory))
            (command (format nil "for item in one two~%  echo $item~%done")))
        (unwind-protect
             (progn
               (setf nshell.infrastructure.persistence:*history-file-path-override*
                     test-path)
               (when (probe-file test-path) (delete-file test-path))
               (nshell.infrastructure.persistence:append-history-entry command)
               (expect (list command) :to-equal
                       (nshell.infrastructure.persistence:load-history-file)))
          (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
          (when (probe-file test-path) (delete-file test-path))))))

  (it "file-history-unframed-lines"
    "Unframed history records are not loaded."
    (host-kit:with-temporary-directory (directory)
      (let ((test-path (merge-pathnames "history-unframed.lisp" directory)))
        (unwind-protect
             (progn
               (setf nshell.infrastructure.persistence:*history-file-path-override*
                     test-path)
               (when (probe-file test-path) (delete-file test-path))
               (with-open-file (stream test-path :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
                 (format stream "unframed one~%unframed two~%"))
               (expect (nshell.infrastructure.persistence:load-history-file) :to-be-null))
          (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
          (when (probe-file test-path) (delete-file test-path))))))

  (it "file-history-missing-file"
    "Loading a missing history file returns NIL."
    (host-kit:with-temporary-directory (directory)
      (let ((test-path (merge-pathnames "history-missing.lisp" directory)))
        (unwind-protect
             (progn
               (setf nshell.infrastructure.persistence:*history-file-path-override*
                     test-path)
               (when (probe-file test-path) (delete-file test-path))
               (expect (nshell.infrastructure.persistence:load-history-file) :to-be-null))
          (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
          (when (probe-file test-path) (delete-file test-path)))))))
