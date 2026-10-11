(in-package #:nshell.infrastructure.persistence)

(defvar *history-file-path-override* nil
  "When non-nil, overrides the default history file path. Used for testing.")

(defparameter +history-record-v2-prefix+ "# nshell-history-v2 "
  "Prefix for legacy length-framed history records.")
(defparameter +history-record-v3-prefix+ "# nshell-history-v3 "
  "Prefix for metadata-bearing length-framed history records.")
(defparameter +history-record-prefix+ +history-record-v3-prefix+
  "Prefix used when appending new history records.")
(defparameter +max-history-entry-length+ (* 1024 1024)
  "Maximum number of characters stored in one history entry.")

(defstruct (history-record
            (:constructor %make-history-record
                (&key text timestamp cwd exit-code duration-ms origin))
            (:copier nil))
  (text "" :type string :read-only t)
  (timestamp nil :type (or null integer) :read-only t)
  (cwd nil :type (or null string) :read-only t)
  (exit-code nil :type (or null integer) :read-only t)
  (duration-ms nil :type (or null integer) :read-only t)
  (origin nil :type (member nil :typed :proposal :agent) :read-only t))

(defvar *history-record-tables* (make-hash-table :test #'eq))
(defvar *history-record-to-append* nil)
(defvar *history-file-lock* (sb-thread:make-mutex :name "nshell history file"))

(defun %make-history-record-from-values (&key text timestamp cwd exit-code duration-ms origin)
  (check-type text string)
  (check-type timestamp (or null integer))
  (check-type cwd (or null string))
  (check-type exit-code (or null integer))
  (check-type duration-ms (or null integer))
  (check-type origin (member nil :typed :proposal :agent))
  (%make-history-record :text (copy-seq text)
                        :timestamp timestamp
                        :cwd (and cwd (copy-seq cwd))
                        :exit-code exit-code
                        :duration-ms duration-ms
                        :origin origin))

(defun %default-history-file-path ()
  (merge-pathnames ".nshell_history" (user-homedir-pathname)))

(defun history-file-path ()
  "Return the path used to persist command history."
  (or *history-file-path-override* (%default-history-file-path)))

(defun %history-record-length-for-prefix (header prefix)
  (let ((prefix-length (length prefix)))
    (when (and (>= (length header) prefix-length)
               (string= prefix header :end1 prefix-length :end2 prefix-length))
      (let ((length-text (subseq header prefix-length)))
        (when (and (plusp (length length-text))
                   (every #'digit-char-p length-text))
          (handler-case
              (let ((length (parse-integer length-text :junk-allowed nil)))
                (when (<= length +max-history-entry-length+)
                  length))
            (error () nil)))))))

(defun %history-record-header (header)
  (let ((v3-length (%history-record-length-for-prefix
                    header +history-record-v3-prefix+)))
    (if v3-length
        (values :v3 v3-length)
        (let ((v2-length (%history-record-length-for-prefix
                          header +history-record-v2-prefix+)))
          (when v2-length
            (values :v2 v2-length))))))

(defun %history-record-payload (record)
  (with-output-to-string (stream)
    (let ((*print-readably* t))
      (write (list :text (history-record-text record)
                   :timestamp (history-record-timestamp record)
                   :cwd (history-record-cwd record)
                   :exit-code (history-record-exit-code record)
                   :duration-ms (history-record-duration-ms record)
                   :origin (history-record-origin record))
             :stream stream))))

(defun %history-record-payload-value (payload)
  (handler-case
      (let ((*read-eval* nil))
        (multiple-value-bind (value position)
            (read-from-string payload nil nil)
          (declare (ignore position))
          (when (and (listp value)
                     (stringp (getf value :text))
                     (typep (getf value :timestamp) '(or null integer))
                     (typep (getf value :cwd) '(or null string))
                     (typep (getf value :exit-code) '(or null integer))
                     (typep (getf value :duration-ms) '(or null integer))
                     (member (getf value :origin)
                             '(nil :typed :proposal :agent)
                             :test #'eq))
            (%make-history-record-from-values
             :text (getf value :text)
             :timestamp (getf value :timestamp)
             :cwd (getf value :cwd)
             :exit-code (getf value :exit-code)
             :duration-ms (getf value :duration-ms)
             :origin (getf value :origin)))))
    (error () nil)))

(defun %read-history-record (stream)
  (let ((header (read-line stream nil :eof)))
    (if (eq header :eof)
        (values nil :eof)
        (multiple-value-bind (version length) (%history-record-header header)
          (if length
              (let ((payload (make-string length)))
                (if (= length (read-sequence payload stream))
                    (let ((separator (read-char stream nil nil)))
                      (if (eql separator #\Newline)
                          (case version
                            (:v2 (values
                                  (%make-history-record-from-values :text payload)
                                  :entry))
                            (:v3 (let ((record (%history-record-payload-value payload)))
                                   (if record
                                       (values record :entry)
                                       (values nil :invalid)))))
                          (values nil :truncated)))
                    (values nil :truncated)))
              (values nil :invalid))))))

(defun %read-history-records (stream)
  (loop with entries = nil
        do (multiple-value-bind (entry status) (%read-history-record stream)
             (case status
               (:eof (return (values (nreverse entries) nil)))
               (:entry (push entry entries))
               (:invalid (return (values (nreverse entries) :invalid)))
               (:truncated (return (values (nreverse entries) :truncated)))))))

(defun %report-history-error (operation path condition)
  (format *error-output*
          "nshell: history: unable to ~a ~a: ~a~%"
          operation path condition))

(defun %append-history-record (stream record)
  (let ((payload (%history-record-payload record)))
    (when (> (length payload) +max-history-entry-length+)
      (error "History entry exceeds ~d characters."
             +max-history-entry-length+))
    (format stream "~a~d~%~a~%"
            +history-record-prefix+
            (length payload)
            payload)))

(defun %open-history-stream (path &key append)
  (let ((fd (handler-case
                (if append
                    (handler-case
                        (sb-posix:open (namestring path)
                                       (logior sb-posix:o-rdwr sb-posix:o-creat
                                               sb-posix:o-excl sb-posix:o-nofollow
                                               sb-posix:o-nonblock)
                                       #o600)
                      (sb-posix:syscall-error (condition)
                        (if (= (sb-posix:syscall-errno condition) sb-posix:eexist)
                            (sb-posix:open (namestring path)
                                           (logior sb-posix:o-rdwr sb-posix:o-nofollow
                                                   sb-posix:o-nonblock))
                            (error condition))))
                    (sb-posix:open (namestring path)
                                   (logior sb-posix:o-rdonly sb-posix:o-nofollow
                                           sb-posix:o-nonblock)))
              (sb-posix:syscall-error (condition)
                (if (and (not append)
                         (= (sb-posix:syscall-errno condition) sb-posix:enoent))
                    nil
                    (error condition))))))
    (when fd
      (handler-case
          (let ((stat (sb-posix:fstat fd)))
            (unless (and (sb-posix:s-isreg (sb-posix:stat-mode stat))
                         (= (sb-posix:stat-uid stat) (sb-posix:getuid))
                         (= (sb-posix:stat-nlink stat) 1))
              (error "History must be a regular, singly-linked file owned by this user."))
            (sb-posix:fchmod fd #o600)
            ;; Never wait on another shell while handling interactive input.
            ;; The descriptor starts at zero, so a zero-length lock covers the file.
            (when append (sb-posix:lockf fd sb-posix:f-tlock 0))
            (sb-sys:make-fd-stream fd :input t :output append
                                     :element-type 'character
                                     :external-format :utf-8 :auto-close t
                                     :pathname (pathname path)))
        (error (condition)
          (sb-posix:close fd)
          (error condition))))))

(defun %history-record-table (history)
  (or (gethash history *history-record-tables*)
      (setf (gethash history *history-record-tables*)
            (make-hash-table :test #'eq))))

(defun %prune-history-record-table (history)
  (let ((table (%history-record-table history))
        (entries (history-kit:history-entries history)))
    (maphash (lambda (entry record)
               (declare (ignore record))
               (unless (find entry entries :test #'eq)
                 (remhash entry table)))
             table)))

(defun history-record-add (history text &key timestamp cwd exit-code duration-ms
                                            (origin :typed))
  "Add TEXT to HISTORY and associate its v3 metadata with the new entry."
  (let ((record (%make-history-record-from-values
                 :text text
                 :timestamp timestamp
                 :cwd cwd
                 :exit-code exit-code
                 :duration-ms duration-ms
                 :origin origin)))
    (multiple-value-bind (history entry)
        (if (integerp timestamp)
            (history-kit:history-add history text
                                     :timestamp timestamp
                                     :exit-code exit-code)
            (history-kit:history-add history text
                                     :timestamp 0
                                     :exit-code exit-code))
      (setf (gethash entry (%history-record-table history)) record)
      (%prune-history-record-table history)
      (values history record))))

(defun history-record-for-entry (history entry)
  "Return nshell metadata for ENTRY, including a safe history-kit fallback."
  (or (gethash entry (%history-record-table history))
      (%make-history-record-from-values
       :text (history-kit:history-entry-text entry)
       :timestamp (history-kit:history-entry-timestamp entry)
       :exit-code (history-kit:history-entry-exit-code entry))))

(defun history-record-matches-p (record &key (exit-code :any) cwd origin)
  "Return true when RECORD satisfies the supplied metadata filters."
  (and (or (eq exit-code :any)
           (case exit-code
             (:failed (and (integerp (history-record-exit-code record))
                           (not (zerop (history-record-exit-code record)))))
             (:success (eql 0 (history-record-exit-code record)))
             (t (eql exit-code (history-record-exit-code record)))))
       (or (null cwd)
           (and (stringp (history-record-cwd record))
                (string= cwd (history-record-cwd record))))
       (or (null origin) (eq origin (history-record-origin record)))))

(defun history-record-filter-token (token)
  "Parse a Ctrl-R metadata token, returning a filter plist or NIL."
  (cond
    ((string= token "status:failed") '(:exit-code :failed))
    ((string= token "status:success") '(:exit-code :success))
    ((string= token "status:ok") '(:exit-code :success))
    ((and (> (length token) 5) (string= "exit:" token :end2 5))
     (let ((value (ignore-errors
                    (parse-integer token :start 5 :junk-allowed nil))))
       (when value (list :exit-code value))))
    ((and (> (length token) 4) (string= "cwd:" token :end2 4))
     (list :cwd (subseq token 4)))
    ((and (> (length token) 7) (string= "origin:" token :end2 7))
     (let ((value (subseq token 7)))
       (when (member value '("typed" "proposal" "agent") :test #'string=)
         (list :origin (intern (string-upcase value) :keyword)))))
    (t nil)))

(defun load-history-file ()
  "Return v3 records oldest first, promoting v2 records with NIL metadata."
  (let ((path (history-file-path)))
    (handler-case
        ;; Closing any descriptor releases this process's POSIX file locks.
        (sb-thread:with-mutex (*history-file-lock*)
          (let ((stream (%open-history-stream path)))
            (when stream
              (with-open-stream (f stream)
                (multiple-value-bind (records status) (%read-history-records f)
                  (when status
                    (%report-history-error "read" path
                                           (format nil "~a history record" status)))
                  records)))))
      (condition (condition)
        (%report-history-error "read" path condition)
        nil))))

(defun append-history-entry (text &key timestamp cwd exit-code duration-ms origin)
  (let ((path (history-file-path)))
    (handler-case
        (sb-thread:with-mutex (*history-file-lock*)
          (ensure-directories-exist path)
          (let ((record (or *history-record-to-append*
                            (%make-history-record-from-values
                             :text text
                             :timestamp timestamp
                             :cwd cwd
                             :exit-code exit-code
                             :duration-ms duration-ms
                             :origin origin))))
            (unless (string= text (history-record-text record))
              (error "History record text does not match the appended command."))
            (with-open-stream (f (%open-history-stream path :append t))
              (multiple-value-bind (records status) (%read-history-records f)
                (declare (ignore records))
                (when status
                  (error "~a history record; existing bytes were preserved." status)))
              (file-position f :end)
              (%append-history-record f record)
              (finish-output f))))
      (condition (condition)
        (%report-history-error "append to" path condition)
        nil))))
