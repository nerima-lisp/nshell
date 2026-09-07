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
               (expect "test command" :to-equal
                       (nshell.infrastructure.persistence::history-record-text
                        (first loaded)))))
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
             (expect (list command)
                     :to-equal
                     (mapcar #'nshell.infrastructure.persistence::history-record-text
                             (nshell.infrastructure.persistence:load-history-file))))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (when (probe-file test-path) (delete-file test-path)))))

  (it "file-history-v2-load-promotes-missing-fields-to-nil"
    "A legacy v2 frame loads as a record without invented metadata."
    (let* ((test-path (format nil "/tmp/nshell-test-history-v2-~d.lisp"
                              (random 1000000)))
           (command "printf 'legacy%s' command"))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (when (probe-file test-path) (delete-file test-path))
             (with-open-file (stream test-path :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (format stream "~a~d~%~a~%"
                       nshell.infrastructure.persistence::+history-record-v2-prefix+
                       (length command)
                       command))
             (let ((record (first
                            (nshell.infrastructure.persistence:load-history-file))))
               (expect command :to-equal
                       (nshell.infrastructure.persistence::history-record-text record))
               (dolist (value (list
                               (nshell.infrastructure.persistence::history-record-timestamp
                                record)
                               (nshell.infrastructure.persistence::history-record-cwd record)
                               (nshell.infrastructure.persistence::history-record-exit-code
                                record)
                               (nshell.infrastructure.persistence::history-record-duration-ms
                                record)
                               (nshell.infrastructure.persistence::history-record-origin record)))
                 (expect value :to-be-null))))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (when (probe-file test-path) (delete-file test-path)))))

  (it "file-history-v3-round-trip-preserves-metadata"
    "A v3 frame preserves every metadata field and the multiline text."
    (let* ((test-path (format nil "/tmp/nshell-test-history-v3-~d.lisp"
                              (random 1000000)))
           (command (format nil "for item~%  echo $item~%done")))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (when (probe-file test-path) (delete-file test-path))
             (nshell.infrastructure.persistence:append-history-entry
              command
              :timestamp 123
              :cwd "/tmp/nshell-history"
              :exit-code 7
              :duration-ms 42
              :origin :agent)
             (with-open-file (stream test-path :direction :input)
               (expect nshell.infrastructure.persistence::+history-record-v3-prefix+
                       :to-equal (subseq (read-line stream)
                                         0
                                         (length nshell.infrastructure.persistence::+history-record-v3-prefix+))))
             (let ((record (first
                            (nshell.infrastructure.persistence:load-history-file))))
               (expect command :to-equal
                       (nshell.infrastructure.persistence::history-record-text record))
               (expect 123 :to-equal
                       (nshell.infrastructure.persistence::history-record-timestamp record))
               (expect "/tmp/nshell-history" :to-equal
                       (nshell.infrastructure.persistence::history-record-cwd record))
               (expect 7 :to-equal
                       (nshell.infrastructure.persistence::history-record-exit-code record))
               (expect 42 :to-equal
                       (nshell.infrastructure.persistence::history-record-duration-ms record))
               (expect :agent :to-equal
                       (nshell.infrastructure.persistence::history-record-origin record))))
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
        (when (probe-file test-path) (delete-file test-path)))))

  (it "file-history-load-order-chronological"
    "LOAD-HISTORY-FILE returns entries oldest first, matching append order.

Pre-fix, this passed already -- the loader itself was never inverted, only
the seeding call site was. This pins the loader's contract so a future
change to %READ-HISTORY-RECORDS cannot silently re-introduce the inversion
one seam over."
    (let ((test-path (format nil "/tmp/nshell-test-history-order-~d.lisp"
                             (random 1000000))))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (when (probe-file test-path) (delete-file test-path))
             (nshell.infrastructure.persistence:append-history-entry "older")
             (nshell.infrastructure.persistence:append-history-entry "newer")
             (expect (list "older" "newer")
                     :to-equal
                     (mapcar #'nshell.infrastructure.persistence::history-record-text
                             (nshell.infrastructure.persistence:load-history-file))))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (when (probe-file test-path) (delete-file test-path)))))

  (it "file-history-seed-recalls-newest-first"
    "After loading persisted history, the first Up-arrow recalls the newest
file entry, not the oldest.

Pre-fix, NSHELL.PRESENTATION::%SEED-HISTORY-FROM-FILE did not exist -- the
seeding loop in INITIALIZE-REPL-STATE called (REVERSE (LOAD-HISTORY-FILE))
before feeding entries to HISTORY-ADD. HISTORY-ADD always records its
argument as the newest entry, so reversing an already-oldest-first list fed
the newest file entry to HISTORY-ADD first, letting every older entry bury
it. HISTORY-PREVIOUS then returned \"older\" on the first call instead of
\"newer\", which is the exact inversion this test catches."
    (let ((test-path (format nil "/tmp/nshell-test-history-seed-~d.lisp"
                             (random 1000000))))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (when (probe-file test-path) (delete-file test-path))
             (nshell.infrastructure.persistence:append-history-entry "older")
             (nshell.infrastructure.persistence:append-history-entry "newer")
             (let ((history (history-kit:make-history)))
               (nshell.presentation::%seed-history-from-file history)
               (expect "newer" :to-equal
                       (history-kit:history-previous history ""))
               (expect "older" :to-equal
                       (history-kit:history-previous history ""))))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (when (probe-file test-path) (delete-file test-path)))))

  (it "file-history-seed-then-new-entry-stays-newest"
    "A command entered in-session after loading history still recalls before
every loaded entry.

Pre-fix this already held by coincidence -- HISTORY-ADD always inserts at the
logical head regardless of how the preceding seed order was wrong -- but it
is pinned here so the fix above cannot be undone by, say, seeding through
HISTORY-ADD's :UPDATE-REVISION NIL path or another shortcut that skips the
head insertion HISTORY-PREVIOUS relies on."
    (let ((test-path (format nil "/tmp/nshell-test-history-seed-new-~d.lisp"
                             (random 1000000))))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (when (probe-file test-path) (delete-file test-path))
             (nshell.infrastructure.persistence:append-history-entry "older")
             (nshell.infrastructure.persistence:append-history-entry "newer")
             (let ((history (history-kit:make-history)))
               (nshell.presentation::%seed-history-from-file history)
               (history-kit:history-add history "in-session")
               (expect "in-session" :to-equal
                       (history-kit:history-previous history ""))
               (expect "newer" :to-equal
                       (history-kit:history-previous history ""))
               (expect "older" :to-equal
                       (history-kit:history-previous history ""))))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (when (probe-file test-path) (delete-file test-path))))))
