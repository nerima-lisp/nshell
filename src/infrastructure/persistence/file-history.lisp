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
                (&key text timestamp cwd exit-code duration-ms origin host))
            (:copier nil))
  (text "" :type string :read-only t)
  (timestamp nil :type (or null integer) :read-only t)
  (cwd nil :type (or null string) :read-only t)
  (exit-code nil :type (or null integer) :read-only t)
  (duration-ms nil :type (or null integer) :read-only t)
  (origin nil :type (member nil :typed :proposal :agent) :read-only t)
  (host nil :type (or null string) :read-only t))

(defvar *history-record-tables* (make-hash-table :test #'eq))
(defvar *history-record-to-append* nil)
(defvar *history-file-mutations-enabled-p* nil
  "Whether this session may change the persisted history file.")
(defvar *history-file-lock* (sb-thread:make-mutex :name "nshell history file"))

(defun %make-history-record-from-values (&key text timestamp cwd exit-code
                                                    duration-ms origin host)
  (check-type text string)
  (check-type timestamp (or null integer))
  (check-type cwd (or null string))
  (check-type exit-code (or null integer))
  (check-type duration-ms (or null integer))
  (check-type origin (member nil :typed :proposal :agent))
  (check-type host (or null string))
  (%make-history-record :text (copy-seq text)
                        :timestamp timestamp
                        :cwd (and cwd (copy-seq cwd))
                        :exit-code exit-code
                        :duration-ms duration-ms
                        :origin origin
                        :host (and host (copy-seq host))))

  (defun %legacy-history-file-path ()
    (merge-pathnames ".nshell_history" (user-homedir-pathname)))

  (defun %xdg-data-home ()
    (let ((value
            (nshell.infrastructure.acl:current-environment-value
             "XDG_DATA_HOME")))
      (when (and value (plusp (length value)))
        (let ((path (pathname value)))
          (when (eq :absolute (first (pathname-directory path)))
            path)))))

  (defun %default-history-file-path ()
    (let ((xdg (%xdg-data-home)))
      (if xdg
          (merge-pathnames #P"nshell/history"
                           (uiop:ensure-directory-pathname xdg))
          (merge-pathnames #P".local/share/nshell/history"
                           (user-homedir-pathname)))))


  (defun %history-lock-path (path)
    (pathname (concatenate 'string (namestring path) ".lock")))

  (defun %history-file-present-p (path)
    (handler-case
        (progn
          (sb-posix:lstat (namestring path))
          t)
      (sb-posix:syscall-error (condition)
        (if (= (sb-posix:syscall-errno condition) sb-posix:enoent)
            nil
            (error condition)))))


(defun history-file-path ()
  "Return the path used to persist command history."
  (or *history-file-path-override* (%default-history-file-path)))

(defun %history-record-length-for-prefix (header prefix)
  (let ((prefix-length (length prefix)))
    (when (and (>= (length header) prefix-length)
               (string= prefix header :end1 prefix-length :end2 prefix-length))
      (let ((length-text (subseq header prefix-length)))
        (when (and (plusp (length length-text))
                   (every (lambda (character)
                            (char<= #\0 character #\9))
                          length-text))
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
      (write (append
              (list :text (history-record-text record)
                    :timestamp (history-record-timestamp record)
                    :cwd (history-record-cwd record)
                    :exit-code (history-record-exit-code record)
                    :duration-ms (history-record-duration-ms record)
                    :origin (history-record-origin record))
              (when (history-record-host record)
                (list :host (history-record-host record))))
             :stream stream))))

(defun %history-record-payload-value (payload)
  (handler-case
      (let ((*read-eval* nil)
            (*read-circle* nil))
        (multiple-value-bind (payload-value position)
            (read-from-string payload nil nil)
          (let ((keys
                  (and (listp payload-value)
                       (ignore-errors
                         (and (evenp (list-length payload-value))
                              (loop for tail on payload-value by #'cddr
                                    collect (first tail)))))))
            (when (and keys
                       (= (length keys) (length (remove-duplicates keys :test #'eq)))
                       (every (lambda (key)
                                (member key '(:text :timestamp :cwd :exit-code
                                              :duration-ms :origin :host)
                                        :test #'eq))
                              keys)
                       (member :text keys :test #'eq)
                       (every (lambda (character)
                                (find character '(#\Space #\Tab #\Newline
                                                  #\Return #\Page)))
                              (subseq payload position))
                       (stringp (getf payload-value :text))
                       (typep (getf payload-value :timestamp) '(or null integer))
                       (typep (getf payload-value :cwd) '(or null string))
                       (typep (getf payload-value :exit-code) '(or null integer))
                       (typep (getf payload-value :duration-ms) '(or null integer))
                       (member (getf payload-value :origin)
                               '(nil :typed :proposal :agent)
                               :test #'eq)
                       (typep (getf payload-value :host) '(or null string)))
              (%make-history-record-from-values
               :text (getf payload-value :text)
               :timestamp (getf payload-value :timestamp)
               :cwd (getf payload-value :cwd)
               :exit-code (getf payload-value :exit-code)
               :duration-ms (getf payload-value :duration-ms)
               :origin (getf payload-value :origin)
               :host (getf payload-value :host))))))
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

  (defun %next-history-record-position (stream damaged-position)
    (when (integerp damaged-position)
      (file-position stream damaged-position)
      (read-line stream nil nil)
      (loop for candidate-position = (file-position stream)
            for header = (read-line stream nil :eof)
            until (eq header :eof)
            when (nth-value 1 (%history-record-header header))
              return candidate-position)))

  (defun %read-history-records (stream)
    (loop with entries = nil
          with problem = nil
          do (let ((start (file-position stream)))
               (multiple-value-bind (entry status) (%read-history-record stream)
                 (case status
                   (:eof
                    (return (values (nreverse entries) problem)))
                   (:entry
                    (push entry entries))
                   ((:invalid :truncated)
                    (setf problem (or problem status))
                    (let ((next (%next-history-record-position stream start)))
                      (if next
                          (file-position stream next)
                          (return (values (nreverse entries) problem))))))))))

  (defun %dedupe-history-records (records)
    (let ((seen (make-hash-table :test #'equal)))
      (loop with unique = nil
            for record in records
            for text = (history-record-text record)
            unless (gethash text seen)
              do (setf (gethash text seen) t)
                 (push record unique)
            finally (return (nreverse unique)))))


  (defun %single-line-history-message (value)
    (let* ((text (princ-to-string value))
           (limit (min 240 (length text))))
      (with-output-to-string (stream)
        (loop for index below limit
              for character = (char text index)
              do (write-char
                  (if (or (< (char-code character) 32)
                          (= (char-code character) 127))
                      #\Space
                      character)
                  stream))
        (when (> (length text) limit)
          (write-string "..." stream)))))

  (defun %report-history-error (operation path condition)
    (format *error-output*
            "nshell: history: unable to ~a ~a: ~a~%"
            operation
            (%single-line-history-message (namestring path))
            (%single-line-history-message condition)))


(defun %append-history-record (stream record)
  (let ((payload (%history-record-payload record)))
    (when (> (length payload) +max-history-entry-length+)
      (error "History entry exceeds ~d characters."
             +max-history-entry-length+))
    (format stream "~a~d~%~a~%"
            +history-record-prefix+
            (length payload)
            payload)))

  (defun %validate-history-descriptor (fd path &key (secure-mode-p t))
    (let ((stat (sb-posix:fstat fd)))
      (unless (and (sb-posix:s-isreg (sb-posix:stat-mode stat))
                   (= (sb-posix:stat-uid stat) (sb-posix:getuid))
                   (= (sb-posix:stat-nlink stat) 1))
        (error "History path ~s must be a regular, singly-linked file owned by this user."
               (namestring path)))
      (when secure-mode-p
        (sb-posix:fchmod fd #o600))))

  (defun %open-history-descriptor (path flags &key create-p)
    (let* ((safe-flags (logior flags sb-posix:o-nofollow sb-posix:o-nonblock))
           (create-flags (logior safe-flags sb-posix:o-creat)))
      (if create-p
          (handler-case
              (sb-posix:open (namestring path)
                             (logior create-flags sb-posix:o-excl)
                             #o600)
            (sb-posix:syscall-error (condition)
              (if (= (sb-posix:syscall-errno condition) sb-posix:eexist)
                  (sb-posix:open (namestring path) create-flags #o600)
                  (error condition))))
          (sb-posix:open (namestring path) safe-flags))))

  (defun %open-history-stream (path &key append (fix-mode-p t))
  (let* ((fd
           (handler-case
               (%open-history-descriptor
                path
                (if append sb-posix:o-rdwr sb-posix:o-rdonly)
                :create-p append)
             (sb-posix:syscall-error (condition)
               (if (and (not append)
                        (= (sb-posix:syscall-errno condition)
                           sb-posix:enoent))
                   nil
                   (error condition)))))
         (stream nil))
    (when fd
      (handler-case
          (progn
            (%validate-history-descriptor fd path :secure-mode-p fix-mode-p)
            (setf stream
                  (sb-sys:make-fd-stream
                   fd :input t :output append
                   :element-type 'character
                   :external-format '(:utf-8 :replacement #\Replacement_Character)
                   :auto-close t
                   :pathname (pathname path))))
        (error (condition)
          (sb-posix:close fd)
          (error condition))))
    stream))


  (defun %open-history-lock (path)
    (let* ((lock-path (%history-lock-path path))
           (fd (%open-history-descriptor lock-path sb-posix:o-rdwr
                                         :create-p t)))
      (handler-case
          (progn
            (%validate-history-descriptor fd lock-path)
            (sb-posix:lockf fd sb-posix:f-lock 0)
            fd)
        (condition (condition)
          (sb-posix:close fd)
          (error condition)))))

  (defun %call-with-history-file-lock (path function)
    (sb-thread:with-mutex (*history-file-lock*)
      (let ((fd (%open-history-lock path)))
        (unwind-protect
             (funcall function)
          (sb-posix:close fd)))))

  (defun %create-history-temporary-file (path)
    (loop repeat 32
          for candidate =
            (pathname
             (format nil "~a.~d.~36r.tmp"
                     (namestring path) (sb-posix:getpid)
                     (random most-positive-fixnum)))
          do (handler-case
                 (return
                   (values candidate
                           (sb-posix:open
                            (namestring candidate)
                            (logior sb-posix:o-wronly sb-posix:o-creat
                                    sb-posix:o-excl sb-posix:o-nofollow
                                    sb-posix:o-nonblock)
                            #o600)))
               (sb-posix:syscall-error (condition)
                 (unless (= (sb-posix:syscall-errno condition)
                            sb-posix:eexist)
                   (error condition))))
          finally (error "Unable to allocate a temporary history file.")))

  (defun %write-history-records-atomically (path records)
    (multiple-value-bind (temporary-path fd)
        (%create-history-temporary-file path)
      (let ((published-p nil)
            (fd-open-p t))
        (unwind-protect
             (progn
               (%validate-history-descriptor fd temporary-path)
               (let ((stream
                       (sb-sys:make-fd-stream
                        fd :output t :element-type 'character
                        :external-format :utf-8 :auto-close t
                        :pathname temporary-path)))
                 (setf fd-open-p nil)
                 (unwind-protect
                      (progn
                        (dolist (record records)
                          (%append-history-record stream record))
                        (finish-output stream)
                        (sb-posix:fsync fd))
                   (close stream)))
               (sb-posix:rename (namestring temporary-path)
                                (namestring path))
               (setf published-p t))
          (when fd-open-p
            (sb-posix:close fd))
          (unless published-p
            (handler-case
                (sb-posix:unlink (namestring temporary-path))
              (sb-posix:syscall-error (condition)
                (unless (= (sb-posix:syscall-errno condition)
                           sb-posix:enoent)
                  (error condition))))))
        published-p)))


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
                                            (origin :typed) host)
  "Add TEXT to HISTORY and associate its v3 metadata with the new entry."
  (let ((record (%make-history-record-from-values
                 :text text
                 :timestamp timestamp
                 :cwd cwd
                 :exit-code exit-code
                 :duration-ms duration-ms
                 :origin origin
                 :host host)))
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

(defun history-record-matches-p (record &key (exit-code :any) cwd origin host
                                             duration-min-ms duration-max-ms)
  "Return true when RECORD satisfies the supplied metadata filters."
  (let ((duration-ms (history-record-duration-ms record)))
    (and (or (eq exit-code :any)
             (case exit-code
               (:failed (and (integerp (history-record-exit-code record))
                             (not (zerop (history-record-exit-code record)))))
               (:success (eql 0 (history-record-exit-code record)))
               (t (eql exit-code (history-record-exit-code record)))))
         (or (null cwd)
             (and (stringp (history-record-cwd record))
                  (string= cwd (history-record-cwd record))))
         (or (null origin) (eq origin (history-record-origin record)))
         (or (null host)
             (and (stringp (history-record-host record))
                  (string= host (history-record-host record))))
         (or (null duration-min-ms)
             (and (integerp duration-ms)
                  (>= duration-ms duration-min-ms)))
         (or (null duration-max-ms)
             (and (integerp duration-ms)
                  (<= duration-ms duration-max-ms))))))

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
    ((and (> (length token) 5) (string= "host:" token :end2 5))
     (list :host (subseq token 5)))
    ((and (> (length token) 13)
          (string= "duration-min:" token :end2 13))
     (let ((value (ignore-errors
                    (parse-integer token :start 13 :junk-allowed nil))))
       (when (and value (not (minusp value)))
         (list :duration-min-ms value))))
    ((and (> (length token) 13)
          (string= "duration-max:" token :end2 13))
     (let ((value (ignore-errors
                    (parse-integer token :start 13 :junk-allowed nil))))
       (when (and value (not (minusp value)))
         (list :duration-max-ms value))))
    (t nil)))

  (defun %read-history-path (path &key (fix-mode-p t))
    (let ((stream (%open-history-stream path :fix-mode-p fix-mode-p)))
      (if stream
          (with-open-stream (file stream)
            (%read-history-records file))
          (values nil nil))))

  (defun %load-history-under-lock (path legacy-path)
    (if (%history-file-present-p path)
        (%read-history-path path)
        (if (and legacy-path (%history-file-present-p legacy-path))
            (multiple-value-bind (records status)
                (%read-history-path legacy-path :fix-mode-p nil)
              (let ((records (%dedupe-history-records records)))
                (when (or records (null status))
                  (%write-history-records-atomically path records))
                (values records status)))
            (values nil nil))))

  (defun load-history-file ()
    "Return v3 records oldest first, promoting v2 records with NIL metadata."
    (let ((path (history-file-path)))
      (handler-case
          (let* ((legacy-path
                   (unless *history-file-path-override*
                     (%legacy-history-file-path)))
                 (destination-present (%history-file-present-p path))
                 (legacy-present
                   (and legacy-path
                        (%history-file-present-p legacy-path))))
            (if (not (or destination-present legacy-present))
                nil
                (progn
                  (when (and legacy-present (not destination-present))
                    (ensure-directories-exist path))
                  (multiple-value-bind (records status)
                      (%call-with-history-file-lock
                       path
                       (lambda ()
                         (%load-history-under-lock path legacy-path)))
                    (when status
                      (%report-history-error
                       "read" path
                       (format nil "~a history record" status)))
                    records))))
        (error (condition)
          (%report-history-error "read" path condition)
          nil))))

  (defun %append-history-record-under-lock (path record)
    (let ((stream (%open-history-stream path :append t))
          (closed-p nil))
      (unwind-protect
           (multiple-value-bind (records status)
               (%read-history-records stream)
             (let* ((unique (%dedupe-history-records records))
                    (repaired-p (or status
                                    (/= (length unique) (length records))))
                    (already-present
                      (find (history-record-text record) unique
                            :key #'history-record-text
                            :test #'string=)))
               (cond
                 (repaired-p
                  (close stream)
                  (setf closed-p t)
                  (%write-history-records-atomically
                   path
                   (if already-present
                       unique
                       (append unique (list record)))))
                 (already-present
                  t)
                 (t
                  (file-position stream :end)
                  (%append-history-record stream record)
                  (finish-output stream)
                  t))))
        (unless closed-p
          (close stream)))))

  (defun append-history-entry (text &key timestamp cwd exit-code duration-ms origin host)
    (let ((path (history-file-path)))
      (handler-case
          (progn
            (ensure-directories-exist path)
            (let ((record (or *history-record-to-append*
                              (%make-history-record-from-values
                               :text text
                               :timestamp timestamp
                               :cwd cwd
                               :exit-code exit-code
                               :duration-ms duration-ms
                               :origin origin
                               :host host))))
              (unless (string= text (history-record-text record))
                (error "History record text does not match the appended command."))
              (%call-with-history-file-lock
               path
               (lambda ()
                 (%append-history-record-under-lock path record)))
              t))
        (error (condition)
          (%report-history-error "append to" path condition)
          nil))))
  (defun %mutate-history-file (operation rewrite)
  (if (not *history-file-mutations-enabled-p*)
      t
      (let ((path (history-file-path)))
        (handler-case
            (progn
              (ensure-directories-exist path)
              (%call-with-history-file-lock
               path
               (lambda ()
                 (multiple-value-bind (records status)
                     (%load-history-under-lock
                      path
                      (unless *history-file-path-override*
                        (%legacy-history-file-path)))
                   (when status
                     (error "Unable to read history records: ~a." status))
                   (multiple-value-bind (updated-records changed-p)
                       (funcall rewrite records)
                     (when changed-p
                       (%write-history-records-atomically
                        path updated-records))))))
              t)
          (error (condition)
            (%report-history-error operation path condition)
            nil)))))
  (defun clear-history-file ()
  (%mutate-history-file
   "clear"
   (lambda (records)
     (declare (ignore records))
     (values nil t))))
  (defun delete-history-entry (text)
  (check-type text string)
  (%mutate-history-file
   "delete from"
   (lambda (records)
     (let ((remaining (remove text records
                             :key #'history-record-text
                             :test #'string=)))
       (values remaining (/= (length remaining) (length records)))))))



