(in-package #:nshell/test)

;;; History navigation and Ctrl-R work on the in-memory history. The history
;;; file is merged in at a new prompt (and before a command runs), never on a
;;; key. File reads are counted by wrapping the persistence reader, not the
;;; handlers under test.

(defun %history-refresh-texts ()
  (mapcar #'history-kit:history-entry-text
          (history-kit:history-entries nshell.presentation::*history*)))

(defun %history-refresh-new-prompt ()
  (setf nshell.presentation::*input-state*
        (nshell.presentation::make-repl-input-state))
  (let ((nshell.presentation::*prompt-hook-pending-p* t)
        (*standard-output* (make-broadcast-stream)))
    (nshell.presentation::render-prompt-cont)))

(defun %history-refresh-prev-key ()
  (let ((*standard-output* (make-broadcast-stream)))
    (nshell.presentation::%process-history-prev-output-event))
  (nshell.presentation:input-state-buffer nshell.presentation::*input-state*))

(defun %history-refresh-search-key (query)
  (setf nshell.presentation::*input-state*
        (nshell.presentation:make-input-state :mode :search :search-query query))
  (let ((*standard-output* (make-broadcast-stream)))
    (nshell.presentation::%process-history-search-output-event)))

(defun %history-refresh-rewrite-file (path texts)
  (when (probe-file path)
    (delete-file path))
  (dolist (text texts)
    (nshell.infrastructure.persistence:append-history-entry text)))

(defmacro with-history-refresh-session ((reads) &body body)
  "Run BODY in a REPL test state whose history file is a fresh temporary file
and whose history-file reads are counted in READS."
  (let ((path (gensym "PATH"))
        (original (gensym "ORIGINAL")))
    `(with-temporary-output-file (,path :prefix "nshell-history-refresh")
       (let ((,reads 0)
             (,original (symbol-function
                         'nshell.infrastructure.persistence:load-history-file)))
         (with-repl-test-state
           (let ((nshell.infrastructure.persistence:*history-file-path-override*
                   (pathname ,path))
                 (nshell.presentation::*history-loading-enabled-p* t)
                 (nshell.presentation::*history-seen-command-texts*
                   (make-hash-table :test #'equal))
                 (nshell.presentation::*history-file-stamp* nil))
             (with-temporary-functions
                 (('nshell.infrastructure.persistence:load-history-file
                   (lambda ()
                     (incf ,reads)
                     (funcall ,original))))
               (unwind-protect
                    (flet ((rewrite (texts)
                             (%history-refresh-rewrite-file ,path texts)))
                      (declare (ignorable #'rewrite))
                      ,@body)
                 (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path
                                   ,path)))
                   (when (probe-file lock-path)
                     (delete-file lock-path)))))))))))

(describe "repl-history-refresh-tests"
  (it "history-prev-and-ctrl-r-keys-do-not-read-the-history-file"
    "Repeated history-prev and Ctrl-R keys use the in-memory history only."
    (with-history-refresh-session (reads)
      (rewrite '("echo first" "echo second"))
      (%history-refresh-new-prompt)
      (expect 1 :to-equal reads)
      (expect "echo second" :to-equal (%history-refresh-prev-key))
      (expect "echo first" :to-equal (%history-refresh-prev-key))
      (%history-refresh-search-key "")
      (%history-refresh-search-key "sec")
      (%history-refresh-search-key "fir")
      (let ((*standard-output* (make-broadcast-stream)))
        (nshell.presentation::%process-history-next-output-event))
      (expect 1 :to-equal reads)))

  (it "an-unchanged-history-file-is-not-read-again-at-a-new-prompt"
    (with-history-refresh-session (reads)
      (rewrite '("echo only"))
      (%history-refresh-new-prompt)
      (%history-refresh-new-prompt)
      (%history-refresh-new-prompt)
      (expect 1 :to-equal reads)))

  (it "an-external-append-is-visible-from-the-next-prompt"
    "Another process's append is not seen by keys of the current prompt and is
merged when the next prompt is drawn."
    (with-history-refresh-session (reads)
      (rewrite '("echo before"))
      (%history-refresh-new-prompt)
      ;; Another nshell process appends while this one edits a line.
      (nshell.infrastructure.persistence:append-history-entry "echo external")
      (expect "echo before" :to-equal (%history-refresh-prev-key))
      (expect '("echo before") :to-equal (%history-refresh-texts))
      (%history-refresh-new-prompt)
      (expect '("echo external" "echo before") :to-equal (%history-refresh-texts))
      (expect 2 :to-equal reads)))

  (it "an-own-execution-is-visible-to-the-next-history-prev-key"
    (with-history-refresh-session (reads)
      (rewrite '("echo older"))
      (%history-refresh-new-prompt)
      (let ((nshell.presentation::*history-persistence-enabled-p* t)
            (*standard-output* (make-broadcast-stream)))
        (with-temporary-functions
            (('nshell.presentation::render-prompt-cont (lambda () nil)))
          (nshell.presentation::%execute-complete-command
           nil "echo own-run" (lambda () 0))))
      (let ((reads-after-execution reads))
        (setf nshell.presentation::*input-state*
              (nshell.presentation::make-repl-input-state))
        (expect "echo own-run" :to-equal (%history-refresh-prev-key))
        (expect reads-after-execution :to-equal reads))))

  (it "a-rewritten-history-file-adds-new-records-and-keeps-loaded-ones"
    "Truncation, rewrite, or rotation never removes entries already loaded in
this session; records that are new in the replaced file are merged."
    (with-history-refresh-session (reads)
      (rewrite '("echo kept-a" "echo kept-b"))
      (%history-refresh-new-prompt)
      (rewrite '("echo rewritten"))
      (%history-refresh-new-prompt)
      (expect '("echo rewritten" "echo kept-b" "echo kept-a")
              :to-equal (%history-refresh-texts))
      (expect 2 :to-equal reads)))

  (it "a-failed-history-read-is-retried-at-the-next-prompt"
    "A read that fails because the lock cannot be opened does not mark the
unchanged file as merged: once the lock opens, the next prompt brings the
records in."
    (with-history-refresh-session (reads)
      (rewrite '("echo recover"))
      (let* ((path nshell.infrastructure.persistence:*history-file-path-override*)
             (lock (namestring
                    (nshell.infrastructure.persistence::%history-lock-path path)))
             (contents (uiop:read-file-string path)))
        ;; A directory in place of the lock fails the lock open for root too.
        (delete-file lock)
        (sb-posix:mkdir lock #o700)
        (unwind-protect
             (let ((*error-output* (make-broadcast-stream)))
               (%history-refresh-new-prompt)
               (expect "" :to-equal (%history-refresh-prev-key)))
          (sb-posix:rmdir lock))
        (%history-refresh-new-prompt)
        (expect "echo recover" :to-equal (%history-refresh-prev-key))
        (expect contents :to-equal (uiop:read-file-string path))))))
