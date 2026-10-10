(require :asdf)
(require :sb-posix)
(load (merge-pathnames "asdf-runtime.lisp" *load-truename*))
(nshell-configure-writable-asdf-output)
(asdf:load-system "cl-history-kit")
(defpackage #:nshell.infrastructure.persistence (:use #:cl))
(load (merge-pathnames "../src/infrastructure/persistence/file-history.lisp"
                       *load-truename*))

(let ((arguments (uiop:command-line-arguments)))
  (when (equal "--history-child-append" (first arguments))
    (let ((nshell.infrastructure.persistence::*history-file-path-override*
            (pathname (second arguments)))
          (*error-output* (make-string-output-stream)))
      (nshell.infrastructure.persistence::append-history-entry (third arguments))
      (let ((errors (get-output-stream-string *error-output*)))
        (write-string errors)
        (uiop:quit (cond ((zerop (length errors)) 0)
                         ((search "SB-POSIX:LOCKF" errors) 3)
                         (t 4)))))))

(defun check-history-reader-lock (path check)
  (let ((script (namestring *load-truename*)))
    (labels ((child-append (label text)
               (multiple-value-bind (output errors code)
                   (uiop:run-program
                    (list (namestring sb-ext:*runtime-pathname*) "--script" script
                          "--history-child-append" (namestring path) text)
                    :output :string :error-output :string :ignore-error-status t)
                 (format t "CHILD ~a exit=~d~%" label code)
                 (unless (member code '(0 3 4))
                   (error "Unexpected child result: ~d ~a ~a" code output errors))
                 (when (= code 4)
                   (write-string output))
                 code))
             (wait-for-signal (semaphore label)
               (unless (sb-thread:wait-on-semaphore semaphore :timeout 5)
                 (error "Timed out waiting for ~a" label)))
             (reader-state (thread done)
               (let ((deadline (+ (get-internal-real-time)
                                  (* 5 internal-time-units-per-second))))
                 (loop
                   (when (eq nshell.infrastructure.persistence::*history-file-lock*
                             (sb-thread::thread-waiting-for thread))
                     (return :blocked))
                   (when (sb-thread:try-semaphore done)
                     (return :completed))
                   (when (> (get-internal-real-time) deadline)
                     (error "Reader neither completed nor waited for the history mutex"))
                   (sb-thread:thread-yield))))
             (run-case (control-p)
               (delete-file path)
               (let ((nshell.infrastructure.persistence::*history-file-path-override* path))
                 (nshell.infrastructure.persistence::append-history-entry "seed"))
               (let* ((held (sb-thread:make-semaphore))
                      (release (sb-thread:make-semaphore))
                      (started (sb-thread:make-semaphore))
                      (done (sb-thread:make-semaphore))
                      (original (symbol-function
                                 'nshell.infrastructure.persistence::%append-history-record))
                      (writer nil)
                      (reader nil)
                      (writer-result nil)
                      (reader-result nil))
                 ;; This isolated runner pauses, but still calls, the real serializer.
                 (unwind-protect
                      (progn
                        (setf (symbol-function
                               'nshell.infrastructure.persistence::%append-history-record)
                              (lambda (stream record)
                                (sb-thread:signal-semaphore held)
                                (wait-for-signal release "writer release")
                                (funcall original stream record)))
                        (setf writer
                              (sb-thread:make-thread
                               (lambda ()
                                 (let ((nshell.infrastructure.persistence::*history-file-path-override* path)
                                       (*error-output* (make-string-output-stream)))
                                   (nshell.infrastructure.persistence::append-history-entry
                                    "holding-writer")
                                   (get-output-stream-string *error-output*)))
                               :name "history holding writer"))
                        (wait-for-signal held "writer descriptor lock")
                        (funcall check
                                 (if control-p "control writer initially excludes child"
                                     "public writer initially excludes child")
                                 (= 3 (child-append "before-reader" "intruder")))
                        (setf reader
                              (sb-thread:make-thread
                               (lambda ()
                                 (let ((nshell.infrastructure.persistence::*history-file-path-override* path)
                                       (*error-output* (make-string-output-stream)))
                                   (sb-thread:signal-semaphore started)
                                   (unwind-protect
                                        (let ((records
                                                (if control-p
                                                    ;; Reproduce the pre-mutex descriptor-close hazard.
                                                    (with-open-stream
                                                        (stream (nshell.infrastructure.persistence::%open-history-stream path))
                                                      (nshell.infrastructure.persistence::%read-history-records stream))
                                                    (nshell.infrastructure.persistence::load-history-file))))
                                          (list (get-output-stream-string *error-output*)
                                                (mapcar #'nshell.infrastructure.persistence::history-record-text
                                                        records)))
                                     (sb-thread:signal-semaphore done))))
                               :name "history overlapping reader"))
                        (wait-for-signal started "reader start")
                        (let ((state (reader-state reader done)))
                          (format t "READER ~a ~a~%" (if control-p "control" "public") state)
                          (funcall check
                                   (if control-p "control reader closes while writer is held"
                                       "public reader waits on held writer mutex")
                                   (eq state (if control-p :completed :blocked))))
                        (funcall check
                                 (if control-p "control reader close releases process file lock"
                                     "public reader cannot release held writer file lock")
                                 (= (if control-p 0 3)
                                    (child-append "after-reader-start" "intruder"))))
                   (sb-thread:signal-semaphore release)
                   (unwind-protect
                        (progn
                          (when writer
                            (setf writer-result (sb-thread:join-thread writer :timeout 5)))
                          (when reader
                            (setf reader-result (sb-thread:join-thread reader :timeout 5))))
                     (setf (symbol-function
                            'nshell.infrastructure.persistence::%append-history-record)
                           original)))
                 (funcall check
                          (if control-p "control writer and reader finish without errors"
                              "public writer and reader finish with committed records")
                          (and (string= "" writer-result)
                               (equal reader-result
                                      (list "" (if control-p '("seed")
                                                    '("seed" "holding-writer")))))))
               (unless control-p
                 (funcall check "writer close permits child append"
                          (= 0 (child-append "after-writer-close" "after-release")))
                 (let ((nshell.infrastructure.persistence::*history-file-path-override* path)
                       (*error-output* (make-string-output-stream)))
                   (let ((records (nshell.infrastructure.persistence::load-history-file)))
                     (funcall check "concurrent history retains exact records without corrupt tail"
                              (and (equal '("seed" "holding-writer" "after-release")
                                          (mapcar #'nshell.infrastructure.persistence::history-record-text
                                                  records))
                                   (string= "" (get-output-stream-string *error-output*)))))))))
      (run-case t)
      (run-case nil))))

(let* ((directory (format nil "/tmp/nshell-history-storage-~d-~36r/"
                          (sb-posix:getpid) (random most-positive-fixnum)))
       (path (merge-pathnames "history" directory))
       (target (merge-pathnames "target" directory))
       (old-mask (sb-posix:umask #o022))
       (checks 0)
       (failures 0))
  (sb-posix:mkdir directory #o700)
  (labels ((check (name result)
             (incf checks)
             (unless result (incf failures))
             (format t "~a ~a~%" (if result "PASS" "FAIL") name))
           (contents (file)
             (uiop:read-file-string file))
           (append-command (command)
             (let ((*error-output* (make-string-output-stream)))
               (nshell.infrastructure.persistence::append-history-entry command)
               (get-output-stream-string *error-output*))))
    (unwind-protect
         (let ((nshell.infrastructure.persistence::*history-file-path-override* path))
           (append-command "first")
           (check "new file is owner-only"
                  (= #o600 (logand #o777 (sb-posix:stat-mode (sb-posix:stat path)))))
           (sb-posix:chmod path #o644)
           (append-command "second")
           (check "existing file is owner-only"
                  (= #o600 (logand #o777 (sb-posix:stat-mode (sb-posix:stat path)))))
           (check "valid entries round-trip"
                  (equal '("first" "second")
                         (mapcar #'nshell.infrastructure.persistence::history-record-text
                                 (nshell.infrastructure.persistence::load-history-file))))
           (rename-file path target)
           (sb-posix:symlink (namestring target) (namestring path))
           (let ((before (contents target)))
             (check "symlink append rejected with target unchanged"
                    (and (plusp (length (append-command "symlink")))
                         (string= before (contents target)))))
           (sb-posix:unlink (namestring path))
           (sb-posix:link (namestring target) (namestring path))
           (let ((before (contents target)))
             (check "hardlink append rejected with target unchanged"
                    (and (plusp (length (append-command "hardlink")))
                         (string= before (contents target)))))
           (delete-file path)
           (delete-file target)
           (append-command "retained")
           (with-open-file (stream path :direction :output :if-exists :append)
             (write-string "# nshell-history-v3 100
short" stream))
           (let ((before (contents path)))
             (check "corrupt tail rejects append without discarding bytes"
                    (and (plusp (length (append-command "hidden")))
                         (string= before (contents path)))))
           (let ((*error-output* (make-string-output-stream)))
             (check "valid prefix remains readable after corruption"
                    (equal '("retained")
                           (mapcar #'nshell.infrastructure.persistence::history-record-text
                                   (nshell.infrastructure.persistence::load-history-file)))))
           (check-history-reader-lock path #'check)
           (format t "History storage: ~d checks, ~d failures~%" checks failures))
      (sb-posix:umask old-mask)
      (when (probe-file path) (delete-file path))
      (when (probe-file target) (delete-file target))
      (sb-posix:rmdir directory)))
  (uiop:quit (if (and (plusp checks) (zerop failures)) 0 1)))
