(in-package #:nshell.infrastructure.acl)
(eval-when (:compile-toplevel :load-toplevel :execute) (require :sb-posix))

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

(defun %directory-listing-stamp (directory)
  (ignore-errors
    (let ((path (sb-posix::filename
                 (host-kit:ensure-directory-pathname directory))))
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
              (namestring (host-kit:ensure-directory-pathname directory)))))

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
                     (concatenate 'string directory "/"))
                 (namestring (host-kit:ensure-directory-pathname directory))))
           (files nil)
           (subdirectories nil)
           (symlink-target-kinds nil))
      (labels ((entry-path (name)
                 (concatenate 'string directory-path name))
               (entry-value (path directory-p)
                 (let ((pathname (ignore-errors (pathname path))))
                   (if (and pathname
                            (not (wild-pathname-p pathname))
                            (string= path (namestring pathname)))
                       (if directory-p
                           (host-kit:ensure-directory-pathname pathname)
                           pathname)
                       (if directory-p
                           (concatenate 'string path "/")
                           path))))
               (entry-kind (path)
                 (let ((mode (sb-posix:stat-mode (sb-posix:lstat path))))
                   (cond
                     ((sb-posix:s-isreg mode) :regular-file)
                     ((sb-posix:s-isdir mode) :directory)
                     ((sb-posix:s-islnk mode) :symbolic-link)
                     (t :other))))
               (visit-entries ()
                 (let ((stream (sb-posix:opendir directory-path)))
                   (unwind-protect
                        (let ((names
                                (sort
                                 (loop for entry = (sb-posix:readdir stream)
                                       while (and entry
                                                  (not (sb-alien:null-alien entry)))
                                       for name = (sb-posix:dirent-name entry)
                                       unless (member name '("." "..") :test #'string=)
                                         collect name)
                                 #'string<)))
                          (dolist (name names)
                            (let* ((entry (entry-path name))
                                   (kind (entry-kind entry)))
                              (case kind
                                (:regular-file
                                 (push (entry-value entry nil) files))
                                (:directory
                                 (push (entry-value entry t) subdirectories))
                                (:symbolic-link
                                 (let ((target-kind
                                         (%filesystem-completion-symlink-target-kind
                                          entry)))
                                   (push (cons entry target-kind) symlink-target-kinds)
                                   (case target-kind
                                     (:directory
                                      (push (entry-value entry t) subdirectories))
                                     ((:regular-file :missing)
                                      (push (entry-value entry nil) files))))))))
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
     :executable-p #'executable-file-p
     :directory-map #'map-path-command-directories)))
