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
             (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
             (nshell.infrastructure.persistence:append-history-entry "test command")
             (let ((loaded (nshell.infrastructure.persistence:load-history-file)))
               (expect (consp loaded) :to-be-truthy)
               (expect "test command" :to-equal
                       (nshell.infrastructure.persistence:history-record-text
                        (first loaded)))))
        ;; Cleanup
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))

  (it "file-history-path-designators-round-trip"
    (with-temporary-output-file (test-path :prefix "nshell-history-designators")
      (dolist (designator (list (pathname test-path) test-path))
        (let ((nshell.infrastructure.persistence:*history-file-path-override*
                designator))
          (nshell.infrastructure.persistence:append-history-entry "older")
          (nshell.infrastructure.persistence:append-history-entry "newer")
          (expect '("older" "newer")
                  :to-equal
                  (mapcar #'nshell.infrastructure.persistence:history-record-text
                          (nshell.infrastructure.persistence:load-history-file)))
          (expect #o600 :to-equal
                  (logand #o777 (sb-posix:stat-mode (sb-posix:stat test-path))))
          (progn (delete-file test-path) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))))))

  (it "file-history-multiline-round-trip"
    "Multiline command history survives persistence."
    (let* ((test-path (format nil "/tmp/nshell-test-history-multiline-~d.lisp"
                              (random 1000000)))
           (command (format nil "for item in one two~%  echo $item~%done")))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
             (nshell.infrastructure.persistence:append-history-entry command)
             (expect (list command)
                     :to-equal
                     (mapcar #'nshell.infrastructure.persistence:history-record-text
                             (nshell.infrastructure.persistence:load-history-file))))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))

  (it "file-history-v2-load-promotes-missing-fields-to-nil"
    "A legacy v2 frame loads as a record without invented metadata."
    (let* ((test-path (format nil "/tmp/nshell-test-history-v2-~d.lisp"
                              (random 1000000)))
           (command "printf 'legacy%s' command"))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
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
                       (nshell.infrastructure.persistence:history-record-text record))
               (dolist (value (list
                               (nshell.infrastructure.persistence:history-record-timestamp
                                record)
                               (nshell.infrastructure.persistence:history-record-cwd record)
                               (nshell.infrastructure.persistence:history-record-exit-code
                                record)
                               (nshell.infrastructure.persistence:history-record-duration-ms
                                record)
                               (nshell.infrastructure.persistence:history-record-origin record)))
                 (expect value :to-be-null))))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))

  (it "file-history-v3-round-trip-preserves-metadata"
    "A v3 frame round-trips optional host metadata and multiline text."
    (let* ((test-path (format nil "/tmp/nshell-test-history-v3-~d.lisp"
                              (random 1000000)))
           (command (format nil "for item~%  echo $item~%done")))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
             (nshell.infrastructure.persistence:append-history-entry
              command
              :timestamp 123
              :cwd "/tmp/nshell-history"
              :exit-code 7
              :duration-ms 42
              :origin :agent
              :host "alpha")
             (with-open-file (stream test-path :direction :input)
               (expect nshell.infrastructure.persistence::+history-record-v3-prefix+
                       :to-equal (subseq (read-line stream)
                                         0
                                         (length nshell.infrastructure.persistence::+history-record-v3-prefix+))))
             (let ((record (first
                            (nshell.infrastructure.persistence:load-history-file))))
               (expect command :to-equal
                       (nshell.infrastructure.persistence:history-record-text record))
               (expect 123 :to-equal
                       (nshell.infrastructure.persistence:history-record-timestamp record))
               (expect "/tmp/nshell-history" :to-equal
                       (nshell.infrastructure.persistence:history-record-cwd record))
               (expect 7 :to-equal
                       (nshell.infrastructure.persistence:history-record-exit-code record))
               (expect 42 :to-equal
                       (nshell.infrastructure.persistence:history-record-duration-ms record))
               (expect :agent :to-equal
                       (nshell.infrastructure.persistence:history-record-origin record))
               (expect "alpha" :to-equal
                       (nshell.infrastructure.persistence:history-record-host record))))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))
  (it "file-history-v3-missing-host-remains-readable"
    "A v3 frame written before host metadata remains readable."
    (let* ((test-path (format nil "/tmp/nshell-test-history-v3-legacy-~d.lisp"
                              (random 1000000)))
           (payload
             (nshell.infrastructure.persistence::%history-record-payload
              (nshell.infrastructure.persistence::%make-history-record-from-values
               :text "legacy v3 command"))))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (with-open-file (stream test-path :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (format stream "~a~d~%~a~%"
                       nshell.infrastructure.persistence::+history-record-v3-prefix+
                       (length payload)
                       payload))
             (let ((record (first
                            (nshell.infrastructure.persistence:load-history-file))))
               (expect "legacy v3 command" :to-equal
                       (nshell.infrastructure.persistence:history-record-text record))
               (expect (nshell.infrastructure.persistence:history-record-host record) :to-be-null)))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))
  (it "file-history-delete-and-clear-persist-current-records"
    "The delete and clear operations update the saved history file."
    (let ((test-path (format nil "/tmp/nshell-test-history-mutate-~d.lisp" (random 1000000))))
      (unwind-protect
           (let ((nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
                 (nshell.infrastructure.persistence:*history-file-mutations-enabled-p*
                   t))
             (nshell.infrastructure.persistence:append-history-entry "delete target"
                                                                     :timestamp 10)
             (nshell.infrastructure.persistence:append-history-entry "keep existing"
                                                                     :timestamp 20)
             (let ((stale-snapshot
                     (nshell.infrastructure.persistence:load-history-file)))
               (nshell.infrastructure.persistence:append-history-entry
                "newer session record" :timestamp 30)
               (expect (nshell.infrastructure.persistence:delete-history-entry "delete target") :to-be-truthy)
               (expect (list "keep existing" "newer session record")
                       :to-equal
                       (mapcar (function nshell.infrastructure.persistence:history-record-text)
                               (nshell.infrastructure.persistence:load-history-file)))
               (expect 2 :to-equal (length stale-snapshot)))
             (expect (nshell.infrastructure.persistence:clear-history-file) :to-be-truthy)
             (expect (nshell.infrastructure.persistence:load-history-file) :to-be-null))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (setf nshell.infrastructure.persistence:*history-file-mutations-enabled-p* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))
  (it "file-history-delete-and-clear-respect-session-gate"
    "Disabled file mutations leave saved history bytes unchanged."
    (let ((test-path (format nil "/tmp/nshell-test-history-gate-~d.lisp" (random 1000000))))
      (unwind-protect
           (let ((nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
                 (nshell.infrastructure.persistence:*history-file-mutations-enabled-p*
                   t))
             (nshell.infrastructure.persistence:append-history-entry "gate delete target")
             (nshell.infrastructure.persistence:append-history-entry "gate keep record")
             (let ((before (uiop:read-file-string test-path)))
               (let ((nshell.infrastructure.persistence:*history-file-mutations-enabled-p*
                       nil))
                 (expect (nshell.infrastructure.persistence:delete-history-entry "gate delete target") :to-be-truthy)
                 (expect (nshell.infrastructure.persistence:clear-history-file) :to-be-truthy))
               (expect before :to-equal (uiop:read-file-string test-path))
               (expect (list "gate delete target" "gate keep record")
                       :to-equal
                       (mapcar (function nshell.infrastructure.persistence:history-record-text)
                               (nshell.infrastructure.persistence:load-history-file)))))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (setf nshell.infrastructure.persistence:*history-file-mutations-enabled-p* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))

  (it "file-history-unframed-lines"
    "Unframed history records are not loaded."
    (let ((test-path (format nil "/tmp/nshell-test-history-unframed-~d.lisp"
                             (random 1000000))))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
             (with-open-file (stream test-path :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (format stream "unframed one~%unframed two~%"))
             (expect (nshell.infrastructure.persistence:load-history-file) :to-be-null))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))

  (it "file-history-malformed-record-does-not-abort-load"
    "A malformed framed record is reported and does not escape the loader."
    (let ((test-path (format nil "/tmp/nshell-test-history-malformed-~d.lisp"
                             (random 1000000))))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
             (with-open-file (stream test-path :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (format stream "~a-not-a-length~%"
                       nshell.infrastructure.persistence::+history-record-v3-prefix+))
             (expect (nshell.infrastructure.persistence:load-history-file)
                     :to-be-null))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))

  (it "file-history-truncated-record-does-not-abort-load"
    "A truncated framed record is reported and does not escape the loader."
    (let ((test-path (format nil "/tmp/nshell-test-history-truncated-~d.lisp"
                             (random 1000000))))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
             (with-open-file (stream test-path :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (format stream "~a~d~%short~%"
                       nshell.infrastructure.persistence::+history-record-v3-prefix+
                       100))
             (expect (nshell.infrastructure.persistence:load-history-file)
                     :to-be-null))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))

  (it "file-history-missing-file"
    "Loading a missing history file returns NIL."
    (let* ((test-path (format nil "/tmp/nshell-test-history-missing-~d.lisp"
                              (random 1000000))))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname test-path))
             (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
             (expect (nshell.infrastructure.persistence:load-history-file) :to-be-null))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))

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
             (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
             (nshell.infrastructure.persistence:append-history-entry "older")
             (nshell.infrastructure.persistence:append-history-entry "newer")
             (expect (list "older" "newer")
                     :to-equal
                     (mapcar #'nshell.infrastructure.persistence:history-record-text
                             (nshell.infrastructure.persistence:load-history-file))))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))

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
             (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
             (nshell.infrastructure.persistence:append-history-entry "older")
             (nshell.infrastructure.persistence:append-history-entry "newer")
             (let ((history (history-kit:make-history)))
               (nshell.presentation::%seed-history-from-file history)
               (expect "newer" :to-equal
                       (history-kit:history-previous history ""))
               (expect "older" :to-equal
                       (history-kit:history-previous history ""))))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))

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
             (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
             (nshell.infrastructure.persistence:append-history-entry "older")
             (nshell.infrastructure.persistence:append-history-entry "newer")
             (let* ((history (history-kit:make-history))
                    (nshell.presentation::*history-seen-command-texts*
                     (make-hash-table :test (function equal)))
                    (seeded-records
                     (nshell.infrastructure.persistence:load-history-file))
                    (newer-timestamp
                     (1+ (reduce (function max)
                                 seeded-records
                                 :key (lambda (record)
                                        (or (nshell.infrastructure.persistence:history-record-timestamp record)
                                            0))
                                 :initial-value 0))))
               (nshell.presentation::%seed-history-from-file history)
               (nshell.infrastructure.persistence:history-record-add
                history "in-session" :timestamp newer-timestamp)
               (expect "in-session" :to-equal
                       (history-kit:history-previous history ""))
               (expect "newer" :to-equal
                       (history-kit:history-previous history ""))
               (expect "older" :to-equal
                       (history-kit:history-previous history ""))))
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path)))))))
  (it "file-history-xdg-path-and-empty-load"
    "History path selection uses absolute XDG_DATA_HOME and avoids empty-store writes."
    (let* ((old-home
             (nshell.infrastructure.acl:current-environment-value "HOME"))
           (old-xdg
             (nshell.infrastructure.acl:current-environment-value "XDG_DATA_HOME"))
           (home (format nil "/tmp/nshell-history-home-~d/" (random 1000000)))
           (xdg (format nil "/tmp/nshell-history-xdg-~d/" (random 1000000)))
           (nshell.infrastructure.persistence:*history-file-path-override* nil))
      (unwind-protect
           (progn
             (sb-posix:setenv "HOME" home 1)
             (sb-posix:setenv "XDG_DATA_HOME" xdg 1)
             (let ((path (nshell.infrastructure.persistence:history-file-path)))
               (expect (merge-pathnames #P"nshell/history"
                                        (uiop:ensure-directory-pathname xdg))
                       :to-equal path)
               (expect (nshell.infrastructure.persistence:load-history-file) :to-be-null)
               (expect (probe-file path) :to-be-null)
               (expect (probe-file
                        (nshell.infrastructure.persistence::%history-lock-path
                         path)) :to-be-null))
             (sb-posix:setenv "XDG_DATA_HOME" "" 1)
             (expect (merge-pathnames #P".local/share/nshell/history"
                                      (user-homedir-pathname))
                     :to-equal
                     (nshell.infrastructure.persistence:history-file-path))
             (sb-posix:setenv "XDG_DATA_HOME" "relative/data" 1)
             (expect (merge-pathnames #P".local/share/nshell/history"
                                      (user-homedir-pathname))
                     :to-equal
                     (nshell.infrastructure.persistence:history-file-path))
             (sb-posix:unsetenv "XDG_DATA_HOME")
             (expect (merge-pathnames #P".local/share/nshell/history"
                                      (user-homedir-pathname))
                     :to-equal
                     (nshell.infrastructure.persistence:history-file-path)))
        (if old-home
            (sb-posix:setenv "HOME" old-home 1)
            (sb-posix:unsetenv "HOME"))
        (if old-xdg
            (sb-posix:setenv "XDG_DATA_HOME" old-xdg 1)
            (sb-posix:unsetenv "XDG_DATA_HOME")))))
  (it "file-history-legacy-import-preserves-source-and-is-idempotent"
    "The first load imports a v2 source without changing its bytes."
    (let* ((old-home
             (nshell.infrastructure.acl:current-environment-value "HOME"))
           (old-xdg
             (nshell.infrastructure.acl:current-environment-value "XDG_DATA_HOME"))
           (home (format nil "/tmp/nshell-history-migrate-home-~d/"
                         (random 1000000)))
           (xdg (format nil "/tmp/nshell-history-migrate-data-~d/"
                        (random 1000000)))
           (legacy (merge-pathnames ".nshell_history" (pathname home)))
           (destination (merge-pathnames #P"nshell/history"
                                         (uiop:ensure-directory-pathname xdg)))
           (command "legacy command")
           (legacy-text
             (format nil "~a~d~%~a~%"
                     nshell.infrastructure.persistence::+history-record-v2-prefix+
                     (length command)
                     command))
           (legacy-bytes (sb-ext:string-to-octets legacy-text
                                                  :external-format :utf-8)))
      (flet ((file-bytes (path)
               (with-open-file (stream path :direction :input
                                       :element-type '(unsigned-byte 8))
                 (let ((bytes (make-array (file-length stream)
                                          :element-type '(unsigned-byte 8))))
                   (read-sequence bytes stream)
                   bytes))))
        (unwind-protect
             (progn
               (sb-posix:setenv "HOME" home 1)
               (sb-posix:setenv "XDG_DATA_HOME" xdg 1)
               (ensure-directories-exist legacy)
               (with-open-file (stream legacy :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create
                                       :element-type '(unsigned-byte 8))
                 (write-sequence legacy-bytes stream))
               (let* ((nshell.infrastructure.persistence:*history-file-path-override*
                        nil)
                      (capture (make-string-output-stream))
                      (records (let ((*error-output* capture)
                                     )
                                 (nshell.infrastructure.persistence:load-history-file)))
                      (reloaded (let ((*error-output* capture))
                                  (nshell.infrastructure.persistence:load-history-file))))
                 (expect '("legacy command")
                         :to-equal
                         (mapcar #'nshell.infrastructure.persistence:history-record-text
                                 records))
                 (expect '("legacy command")
                         :to-equal
                         (mapcar #'nshell.infrastructure.persistence:history-record-text
                                 reloaded))
                 (expect "" :to-equal (get-output-stream-string capture)))
               (expect (equalp legacy-bytes (file-bytes legacy)) :to-be-truthy)
               (expect #o600 :to-equal
                       (logand #o777
                               (sb-posix:stat-mode (sb-posix:stat destination))))
               (with-open-file (stream destination :direction :input)
                 (let* ((header (read-line stream))
                        (prefix nshell.infrastructure.persistence::+history-record-v3-prefix+))
                   (expect prefix :to-equal (subseq header 0 (length prefix)))))
               (expect (probe-file
                        (nshell.infrastructure.persistence::%history-lock-path
                         destination)) :to-be-truthy))
          (if old-home
              (sb-posix:setenv "HOME" old-home 1)
              (sb-posix:unsetenv "HOME"))
          (if old-xdg
              (sb-posix:setenv "XDG_DATA_HOME" old-xdg 1)
              (sb-posix:unsetenv "XDG_DATA_HOME"))
          (when (probe-file destination)
            (delete-file destination))
          (when (probe-file
                 (nshell.infrastructure.persistence::%history-lock-path destination))
            (delete-file
             (nshell.infrastructure.persistence::%history-lock-path destination)))
          (when (probe-file legacy)
            (delete-file legacy))
          (ignore-errors
            (sb-posix:rmdir
             (namestring
              (merge-pathnames #P"nshell/"
                               (uiop:ensure-directory-pathname xdg)))))
          (ignore-errors
            (sb-posix:rmdir (namestring (uiop:ensure-directory-pathname xdg))))
          (ignore-errors
            (sb-posix:rmdir (namestring (uiop:ensure-directory-pathname home))))))))
  (it "file-history-recovers-after-invalid-bytes-and-repairs-duplicates"
    "Invalid bytes between frames do not hide the suffix or block a later append."
    (let* ((test-path (format nil "/tmp/nshell-test-history-invalid-utf8-~d"
                              (random 1000000)))
           (lock-path
             (nshell.infrastructure.persistence::%history-lock-path test-path)))
      (flet ((frame (text)
               (with-output-to-string (stream)
                 (nshell.infrastructure.persistence::%append-history-record
                  stream
                  (nshell.infrastructure.persistence::%make-history-record-from-values
                   :text text))))
             (file-bytes (path)
               (with-open-file (stream path :direction :input
                                       :element-type '(unsigned-byte 8))
                 (let ((bytes (make-array (file-length stream)
                                          :element-type '(unsigned-byte 8))))
                   (read-sequence bytes stream)
                   bytes))))
        (unwind-protect
             (progn
               (with-open-file (stream test-path :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create
                                       :element-type '(unsigned-byte 8))
                 (let ((before (sb-ext:string-to-octets (frame "repeat")
                                                       :external-format :utf-8))
                       (after (sb-ext:string-to-octets (frame "suffix")
                                                      :external-format :utf-8)))
                   (write-sequence before stream)
                   (write-sequence before stream)
                   (write-byte 255 stream)
                   (write-byte 10 stream)
                   (write-sequence after stream)))
               (let* ((nshell.infrastructure.persistence:*history-file-path-override*
                        (pathname test-path))
                      (capture (make-string-output-stream))
                      (records (let ((*error-output* capture))
                                 (nshell.infrastructure.persistence:load-history-file)))
                      (notice (get-output-stream-string capture)))
                 (expect '("repeat" "repeat" "suffix")
                         :to-equal
                         (mapcar #'nshell.infrastructure.persistence:history-record-text
                                 records))
                 (expect 1 :to-equal (count (code-char 10) notice)))
               (let* ((nshell.infrastructure.persistence:*history-file-path-override*
                        (pathname test-path))
                      (capture (make-string-output-stream)))
                 (let ((*error-output* capture))
                   (expect t :to-be
                           (nshell.infrastructure.persistence:append-history-entry
                            "after repair")))
                 (expect "" :to-equal (get-output-stream-string capture))
                 (let ((*error-output* capture))
                   (expect '("repeat" "suffix" "after repair")
                           :to-equal
                           (mapcar
                            #'nshell.infrastructure.persistence:history-record-text
                            (nshell.infrastructure.persistence:load-history-file))))
                 (expect "" :to-equal (get-output-stream-string capture)))
               (expect nil :to-be (find 255 (file-bytes test-path))))
          (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
          (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
          (when (probe-file lock-path)
            (delete-file lock-path))))
))
  (it "file-history-rejects-trailing-plist-junk"
    "A v3 payload with non-whitespace after its plist is skipped."
    (let ((test-path (format nil "/tmp/nshell-test-history-trailing-junk-~d"
                             (random 1000000))))
      (flet ((frame (text)
               (with-output-to-string (stream)
                 (nshell.infrastructure.persistence::%append-history-record
                  stream
                  (nshell.infrastructure.persistence::%make-history-record-from-values
                   :text text)))))
        (unwind-protect
             (progn
               (let* ((bad-payload
                        (concatenate
                         'string
                         (nshell.infrastructure.persistence::%history-record-payload
                          (nshell.infrastructure.persistence::%make-history-record-from-values
                           :text "invalid"))
                         " junk"))
                      (bad-frame
                        (format nil "~a~d~%~a~%"
                                nshell.infrastructure.persistence::+history-record-v3-prefix+
                                (length bad-payload)
                                bad-payload)))
                 (with-open-file (stream test-path :direction :output
                                         :if-exists :supersede
                                         :if-does-not-exist :create)
                   (write-string bad-frame stream)
                   (write-string (frame "suffix") stream)))
               (let* ((nshell.infrastructure.persistence:*history-file-path-override*
                        (pathname test-path))
                      (capture (make-string-output-stream))
                      (records (let ((*error-output* capture))
                                 (nshell.infrastructure.persistence:load-history-file)))
                      (notice (get-output-stream-string capture)))
                 (expect '("suffix")
                         :to-equal
                         (mapcar #'nshell.infrastructure.persistence:history-record-text
                                 records))
                 (expect 1 :to-equal (count (code-char 10) notice)))
               (let* ((nshell.infrastructure.persistence:*history-file-path-override*
                        (pathname test-path))
                      (capture (make-string-output-stream)))
                 (let ((*error-output* capture))
                   (nshell.infrastructure.persistence:append-history-entry "after repair"))
                 (expect "" :to-equal (get-output-stream-string capture))
                 (let ((*error-output* capture))
                   (expect '("suffix" "after repair")
                           :to-equal
                           (mapcar
                            #'nshell.infrastructure.persistence:history-record-text
                            (nshell.infrastructure.persistence:load-history-file))))
                 (expect "" :to-equal (get-output-stream-string capture))))
          (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
          (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
          (when (probe-file
                 (nshell.infrastructure.persistence::%history-lock-path test-path))
            (delete-file
             (nshell.infrastructure.persistence::%history-lock-path test-path))))))
)
  (it "file-history-lock-failure-keeps-existing-file-unchanged"
    "A destination that cannot obtain its lock remains readable by startup."
    (let* ((directory
             (format nil "/tmp/nshell-history-readonly-~d/" (random 1000000)))
           (test-path (merge-pathnames "history" (pathname directory)))
           (lock-path
             (nshell.infrastructure.persistence::%history-lock-path test-path))
           (contents nil))
      (sb-posix:mkdir directory #o700)
      (unwind-protect
           (let ((nshell.infrastructure.persistence:*history-file-path-override*
                   test-path))
             (nshell.infrastructure.persistence:append-history-entry "preserve me")
             (setf contents (uiop:read-file-string test-path))
             (delete-file lock-path)
             (if (zerop (sb-posix:getuid))
                 (sb-posix:symlink (namestring test-path) (namestring lock-path))
                 (sb-posix:chmod directory #o500))
             (let* ((capture (make-string-output-stream))
                    (records (let ((*error-output* capture))
                               (nshell.infrastructure.persistence:load-history-file)))
                    (notice (get-output-stream-string capture)))
               (expect records :to-be-null)
               (expect 1 :to-equal (count (code-char 10) notice))
               (expect contents :to-equal (uiop:read-file-string test-path))))
        (sb-posix:chmod directory #o700)
        (setf nshell.infrastructure.persistence:*history-file-path-override* nil)
        (progn (when (probe-file test-path) (delete-file test-path)) (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path test-path))) (when (probe-file lock-path) (delete-file lock-path))))
        (when (probe-file lock-path)
          (delete-file lock-path))
        (sb-posix:rmdir directory))))
  (it "file-history-append-failure-is-reported-and-recoverable"
    "A failed append reports its error and later appends still work."
    (with-temporary-output-file (blocker :prefix "nshell-history-blocker")
      (with-temporary-output-file (recovery-path :prefix "nshell-history-recovery")
        (with-open-file (stream blocker :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (write-string "blocker" stream))
        (let ((diagnostics (make-string-output-stream)))
          (let ((nshell.infrastructure.persistence:*history-file-path-override*
                  (pathname (format nil "~a/child/history.lisp" blocker)))
                (*error-output* diagnostics))
            (expect nil :to-equal
                    (nshell.infrastructure.persistence:append-history-entry
                     "before failure"))
            (let ((message (get-output-stream-string diagnostics)))
              (expect (search "nshell: history: unable to append to" message) :to-be-truthy)
              (expect nil :to-equal (search "#S(" message)))
            (setf nshell.infrastructure.persistence:*history-file-path-override*
                  (pathname recovery-path))
            (nshell.infrastructure.persistence:append-history-entry "after failure")
            (expect (list "after failure")
                    :to-equal
                    (mapcar
                     (function nshell.infrastructure.persistence:history-record-text)
                     (nshell.infrastructure.persistence:load-history-file))))))))




)
