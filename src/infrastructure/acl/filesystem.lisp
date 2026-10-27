(in-package #:nshell.infrastructure.acl)
(declaim (ftype function cached-completion-entries))
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

;;; Completion lists a directory on every keystroke, so a directory with
;;; thousands of entries (a busy /tmp) costs a full listing per character. The
;;; cache below keys on the directory's identity and subsecond mtime and ctime.
;;; Completion entries also recheck symlink target kinds because changing a
;;; target elsewhere does not update the containing directory's timestamps.
;;; An unavailable precise stamp bypasses the cache.

(defparameter *directory-listing-cache-ttl-seconds* 5)

(defparameter *directory-listing-cache-limit* 128
  "Entries kept before the cache is dropped whole; walking a deep tree must not
grow it without bound.")

(defvar *directory-listing-cache* (make-hash-table :test #'equal))

(defun clear-directory-listing-cache ()
  (clrhash *directory-listing-cache*))

(defun %directory-listing-path-string (directory)
  (if (stringp directory)
      (cond
        ((string= directory "") "./")
        ((char= (char directory (1- (length directory))) (code-char 47)) directory)
        (t (concatenate (quote string) directory "/")))
      (namestring (host-kit:ensure-directory-pathname directory))))

(defun %directory-listing-stamp (directory)
  (ignore-errors
    (let ((path (sb-posix::filename
                 (%directory-listing-path-string directory))))
      ;; On 64-bit Linux and Darwin, the long after each st_mtime/st_ctime
      ;; seconds field is the corresponding tv_nsec value.
      #+(and 64-bit (or darwin linux))
      (sb-alien:with-alien
          ((stat-function
            (function sb-alien:int
                      (sb-alien:c-string :not-null t)
                      (* sb-posix::alien-stat))
            :extern #+inode64 "stat$INODE64" #-inode64 "stat")
           (stat sb-posix::alien-stat))
        (when (zerop (sb-alien:alien-funcall
                      stat-function path (sb-alien:addr stat)))
          (flet ((nanoseconds (field)
                   (let ((value
                           (sb-alien:deref
                            (sb-alien:cast
                             (sb-alien:addr (sb-alien:slot stat field))
                             (* sb-posix::time-t))
                            1)))
                     (when (and (<= 0 value) (< value 1000000000))
                       value))))
            (let ((mtime-nanoseconds (nanoseconds 'sb-posix::mtime))
                  (ctime-nanoseconds (nanoseconds 'sb-posix::ctime)))
              (when (and mtime-nanoseconds ctime-nanoseconds)
                (list (sb-alien:slot stat 'sb-posix::dev)
                      (sb-alien:slot stat 'sb-posix::ino)
                      (sb-alien:slot stat 'sb-posix::mtime)
                      mtime-nanoseconds
                      (sb-alien:slot stat 'sb-posix::ctime)
                      ctime-nanoseconds)))))
      #-(and 64-bit (or darwin linux))
      nil))))
(defun %directory-listing-cache-key (kind directory)
  (cons kind (ignore-errors
              (%directory-listing-path-string directory))))

(defun %cached-directory-listing (kind directory reader &optional entry-valid-p)
  (let ((key (%directory-listing-cache-key kind directory)))
    (if (null (cdr key))
        (funcall reader directory)
        (let ((stamp (%directory-listing-stamp directory))
              (now (get-universal-time))
              (entry (gethash key *directory-listing-cache*)))
          (if (and stamp
                   entry
                   (equal stamp (first entry))
                   (< (- now (second entry)) *directory-listing-cache-ttl-seconds*)
                   (or (null entry-valid-p)
                       (funcall entry-valid-p (third entry))))
              (third entry)
              (let ((value (funcall reader directory)))
                (if stamp
                    (progn
                      (when (> (hash-table-count *directory-listing-cache*)
                               *directory-listing-cache-limit*)
                        (clear-directory-listing-cache))
                      (setf (gethash key *directory-listing-cache*)
                            (list stamp now value)))
                    (remhash key *directory-listing-cache*))
                value))))))

(defun cached-directory-files (directory)
  (%cached-directory-listing :files directory #'host-kit:directory-files))

(defun cached-subdirectories (directory)
  (%cached-directory-listing :subdirectories directory #'host-kit:subdirectories))
(defun %filesystem-completion-dirent-type-hint (dirent)
  ;; Both supported 64-bit ABIs place d_type before d_name.
  #+(and 64-bit (or darwin linux))
  (sb-sys:sap-ref-8
   (sb-alien:alien-sap dirent)
   (1- sb-posix::offset-of-dirent-name))
  #-(and 64-bit (or darwin linux))
  (let ((ignored dirent))
    (declare (ignore ignored))
    nil))
(defun read-regular-file-bytes (pathname byte-limit)
  (when (and (integerp byte-limit) (plusp byte-limit))
    (let ((fd nil)
          (stream nil))
      (unwind-protect
           (handler-case
               (let ((path (namestring (pathname pathname))))
                 (when (sb-posix:s-isreg
                        (sb-posix:stat-mode (sb-posix:lstat path)))
                   (setf fd
                         (sb-posix:open
                          path
                          (logior sb-posix:o-rdonly
                                  sb-posix:o-nofollow
                                  sb-posix:o-nonblock)))
                   (let ((stat (sb-posix:fstat fd)))
                     (when (sb-posix:s-isreg (sb-posix:stat-mode stat))
                       (setf stream
                             (sb-sys:make-fd-stream
                              fd :input t
                              :element-type (quote (unsigned-byte 8))
                              :auto-close t))
                       (setf fd nil)
                       (let* ((limit (min byte-limit 4096))
                              (bytes
                                (make-array limit
                                            :element-type
                                            (quote (unsigned-byte 8)))))
                         (let ((count (read-sequence bytes stream))) (subseq bytes 0 count)))))))
             (sb-posix:syscall-error () nil)
             (stream-error () nil))
        (when stream
          (ignore-errors (close stream)))
        (when fd
          (ignore-errors (sb-posix:close fd)))))))

(progn
  (defun %filesystem-completion-symlink-target-kind (entry)
    (handler-case
        (let ((mode (sb-posix:stat-mode (sb-posix:stat (namestring entry)))))
          (cond
            ((sb-posix:s-isdir mode) :directory)
            ((sb-posix:s-isreg mode) :regular-file)
            (t :other)))
      (sb-posix:syscall-error (condition)
        (if (member (sb-posix:syscall-errno condition)
                    (list sb-posix:enoent sb-posix:enotdir))
            :missing
            (error condition)))))

  (defun %filesystem-completion-entry-lists-valid-p (entry-lists)
    (every (lambda (target)
             (eq (cdr target)
                 (%filesystem-completion-symlink-target-kind (car target))))
           (getf entry-lists :symlink-target-kinds)))

  (defun %filesystem-completion-entry-lists (directory)
    (let* ((directory-path
             (if (stringp directory)
                 (if (and (plusp (length directory))
                          (char= (char directory (1- (length directory))) #\/))
                     directory
                     (concatenate (quote string) directory "/"))
                 (namestring (host-kit:ensure-directory-pathname directory))))
           (files nil)
           (subdirectories nil)
           (symlink-target-kinds nil))
      ;; On 64-bit Darwin d_type is the byte before the generated d_name offset.
      ;; Keep unknown types and symlinks on the lstat path below.
      (labels ((entry-path (name)
                 (concatenate (quote string) directory-path name))
               (entry-value (path directory-p)
                 (let ((pathname (ignore-errors (pathname path))))
                   (if (and pathname
                            (not (wild-pathname-p pathname))
                            (string= path (namestring pathname)))
                       (if directory-p
                           (host-kit:ensure-directory-pathname pathname)
                           pathname)
                       (if directory-p
                           (concatenate (quote string) path "/")
                           path))))
               (dirent-type-hint (dirent)
                 #+(and darwin 64-bit)
                 (sb-sys:sap-ref-8
                  (sb-alien:alien-sap dirent)
                  (1- sb-posix::offset-of-dirent-name))
                 #-(and darwin 64-bit)
                 (let ((ignored dirent))
                   (declare (ignore ignored))
                   nil))
               (entry-kind (path type-hint)
                 ;; Darwin DT_DIR and DT_REG are 4 and 8; other values fall back.
                 (case type-hint
                   (4 :directory)
                   (8 :regular-file)
                   (otherwise
                    (let ((mode (sb-posix:stat-mode (sb-posix:lstat path))))
                      (cond
                        ((sb-posix:s-isreg mode) :regular-file)
                        ((sb-posix:s-isdir mode) :directory)
                        ((sb-posix:s-islnk mode) :symbolic-link)
                        (t :other))))))
               (visit-entries ()
                 (let ((stream (sb-posix:opendir directory-path)))
                   (unwind-protect
                        (let ((entries
                                (sort
                                 (loop for dirent = (sb-posix:readdir stream)
                                       while (and dirent
                                                  (not (sb-alien:null-alien dirent)))
                                       for type-hint = (dirent-type-hint dirent)
                                       for name = (sb-posix:dirent-name dirent)
                                       unless (member name (list "." "..")
                                                      :test (function string=))
                                         collect (cons name type-hint))
                                 (function string<)
                                 :key (function car))))
                          (dolist (record entries)
                            (let* ((name (car record))
                                   (path (entry-path name))
                                   (kind (entry-kind path (cdr record))))
                              (case kind
                                (:regular-file
                                 (push (entry-value path nil) files))
                                (:directory
                                 (push (entry-value path t) subdirectories))
                                (:symbolic-link
                                 (let ((target-kind
                                         (%filesystem-completion-symlink-target-kind
                                          path)))
                                   (push (cons path target-kind) symlink-target-kinds)
                                   (case target-kind
                                     (:directory
                                      (push (entry-value path t) subdirectories))
                                     ((:regular-file :missing)
                                      (push (entry-value path nil) files))))))))
                     (sb-posix:closedir stream))))))
        (visit-entries)
        (list :files (nreverse files)
              :subdirectories (nreverse subdirectories)
              :symlink-target-kinds (nreverse symlink-target-kinds)))))

  (defun %cached-filesystem-completion-entry-lists (directory)
    (%cached-directory-listing :filesystem-completion-entries
                               directory
                               #'%filesystem-completion-entry-lists
                               #'%filesystem-completion-entry-lists-valid-p))

  (defun cached-completion-directory-files (directory)
    (getf (%cached-filesystem-completion-entry-lists directory) :files))

  (defun cached-completion-subdirectories (directory)
    (getf (%cached-filesystem-completion-entry-lists directory) :subdirectories))

  (defun make-host-filesystem ()
  (nshell.domain.filesystem:make-filesystem
   :directory-files #'cached-completion-directory-files
   :subdirectories #'cached-completion-subdirectories
   :completion-entries #'cached-completion-entries
   :executable-p #'executable-file-p
   :directory-map #'map-path-command-directories)))
(progn
  (defun %filesystem-completion-entry-batch-valid-p (entry-batch)
    (every (lambda (target)
             (eq (cdr target)
                 (%filesystem-completion-symlink-target-kind (car target))))
           (getf entry-batch :symlink-target-kinds)))

  (defun %filesystem-completion-entry-batch (directory)
    (let* ((directory-path (%directory-listing-path-string directory))
           (directories nil)
           (files nil)
           (unknown nil)
           (symlink-target-kinds nil))
      (labels ((entry-path (name)
                 (concatenate 'string directory-path name))
               (entry-kind (name type-hint)
                 (case type-hint
                   (4 (values :directory nil))
                   (8 (values :regular-file nil))
                   (otherwise
                    (let* ((path (entry-path name))
                           (mode (sb-posix:stat-mode (sb-posix:lstat path))))
                      (values
                       (cond
                         ((sb-posix:s-isreg mode) :regular-file)
                         ((sb-posix:s-isdir mode) :directory)
                         ((sb-posix:s-islnk mode) :symbolic-link)
                         (t :unknown))
                       path)))))
               (record-entry (name kind path)
                 (case kind
                   (:directory
                    (push
                     (nshell.domain.filesystem:make-filesystem-completion-entry
                      :name name :kind :directory)
                     directories))
                   (:regular-file
                    (push
                     (nshell.domain.filesystem:make-filesystem-completion-entry
                      :name name :kind :regular-file)
                     files))
                   (:symbolic-link
                    (let* ((target-kind
                             (%filesystem-completion-symlink-target-kind path))
                           (entry
                             (nshell.domain.filesystem:make-filesystem-completion-entry
                              :name name :kind :symbolic-link
                              :target-kind (if (eq target-kind :other)
                                               :unknown
                                               target-kind))))
                      (push (cons path target-kind) symlink-target-kinds)
                      (cond
                        ((eq target-kind :directory)
                         (push entry directories))
                        ((member target-kind '(:regular-file :missing))
                         (push entry files))
                        (t
                         (push entry unknown)))))
                   (otherwise
                    (push
                     (nshell.domain.filesystem:make-filesystem-completion-entry
                      :name name :kind :unknown)
                     unknown))))
               (visit-entries ()
                 (let ((stream (sb-posix:opendir directory-path)))
                   (unwind-protect
                        (let ((entries
                                (sort
                                 (loop for dirent = (sb-posix:readdir stream)
                                       while (and dirent
                                                  (not (sb-alien:null-alien dirent)))
                                       for type-hint = (%filesystem-completion-dirent-type-hint dirent)
                                       for name = (sb-posix:dirent-name dirent)
                                       unless (member name '("." "..")
                                                      :test #'string=)
                                         collect (cons name type-hint))
                                 #'string<
                                 :key #'car)))
                          (dolist (record entries)
                            (let ((name (car record)))
                              (multiple-value-bind (kind path)
                                  (entry-kind name (cdr record))
                                (record-entry name kind path)))))
                     (sb-posix:closedir stream)))))
        (visit-entries)
        (list :entries (append (nreverse directories)
                               (nreverse files)
                               (nreverse unknown))
              :symlink-target-kinds (nreverse symlink-target-kinds)))))

  (defun %cached-filesystem-completion-entry-batch (directory)
    (%cached-directory-listing :filesystem-completion-entry-batch
                               directory
                               #'%filesystem-completion-entry-batch
                               #'%filesystem-completion-entry-batch-valid-p))

  (defun cached-completion-entries (directory)
    (getf (%cached-filesystem-completion-entry-batch directory) :entries)))
