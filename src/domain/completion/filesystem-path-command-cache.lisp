(in-package #:nshell.domain.completion)

(defun %path-command-directory-pathname (directory)
  (pathname (if (string= directory "")
                "./"
                directory)))

(defun %require-path-command-cache-lock-factory ()
  (or *path-command-cache-lock-factory*
      (error "PATH command cache lock factory has not been configured")))

(defun %make-path-command-cache-lock ()
  (funcall (%require-path-command-cache-lock-factory)))

(defun %require-path-command-directory-cache-lock ()
  (or *path-command-directory-cache-lock*
      (error "PATH command cache lock has not been configured")))

(defun %configure-path-command-cache-locks (factory)
  (unless (functionp factory)
    (error "PATH command cache lock factory must be a function: ~S" factory))
  (setf *path-command-cache-lock-factory* factory
        *path-command-directory-cache-lock* (funcall factory)
        *path-command-directory-key-locks* (make-hash-table :test #'equal)
        *path-command-directory-cache* (make-hash-table :test #'equal))
  (incf *path-command-directory-cache-generation*)
  nil)

(defmacro %with-path-command-directory-cache-lock (&body body)
  `(cl-boundary-kit:call-with-lock
    (%require-path-command-directory-cache-lock)
    (lambda ()
      ,@body)))

(defun %path-command-directory-key-lock (key)
  (%with-path-command-directory-cache-lock
    (let ((record (gethash key *path-command-directory-key-locks*)))
      (if record
          (progn
            (incf (cdr record))
            record)
          (setf (gethash key *path-command-directory-key-locks*)
                (cons (%make-path-command-cache-lock) 1))))))

(defun %release-path-command-directory-key-lock (key record)
  (%with-path-command-directory-cache-lock
    (when (zerop (decf (cdr record)))
      (when (eq record (gethash key *path-command-directory-key-locks*))
        (remhash key *path-command-directory-key-locks*)))))

(defmacro %with-path-command-directory-key-lock ((key) &body body)
  (let ((key-value (gensym "KEY"))
        (record (gensym "RECORD")))
    `(let* ((,key-value ,key)
            (,record (%path-command-directory-key-lock ,key-value)))
       (unwind-protect
           (cl-boundary-kit:call-with-lock
            (car ,record)
            (lambda ()
              ,@body))
         (%release-path-command-directory-key-lock ,key-value ,record)))))

(defun %invalidate-path-command-cache ()
  "Discard all cached PATH directory entries."
  (%with-path-command-directory-cache-lock
    (incf *path-command-directory-cache-generation*)
    (clrhash *path-command-directory-cache*))
  nil)

(defun %path-command-directory-cache-key (directory filesystem)
  (list (namestring directory)
        filesystem
        *path-command-directory-stamp-fn*
        *path-command-cache-clock-fn*
        *path-command-cache-wall-clock-fn*
        *path-command-cache-ttl-seconds*
        *path-command-cache-revalidate-seconds*
        *path-command-cache-max-age-seconds*
        *path-command-stamp-settle-seconds*
        *path-command-cache-limit*))

(defun %path-command-directory-stamp (directory)
  (when (functionp *path-command-directory-stamp-fn*)
    (ignore-errors (funcall *path-command-directory-stamp-fn* directory))))

(defun %path-command-stamp-settled-p (stamp entries scan-wall-time)
  "True when a later change to the directory must produce a different STAMP.
A directory without a stamp is settled only while it lists nothing, so a
missing PATH directory that appears later changes its stamp from NIL."
  (if stamp
      (and (integerp stamp)
           (integerp scan-wall-time)
           (<= (+ stamp *path-command-stamp-settle-seconds*) scan-wall-time))
      (null entries)))

(defun %path-command-directory-cache-get (key stamp-fn now)
  "Return the cache record for KEY and T when it is still valid at NOW.
A settled record checked within *PATH-COMMAND-CACHE-REVALIDATE-SECONDS* is
returned without calling STAMP-FN, so a key typed shortly after another does
no file I/O. Otherwise STAMP-FN is called outside the lock and must match."
  (let ((entry (%with-path-command-directory-cache-lock
                 (gethash key *path-command-directory-cache*))))
    (cond
      ((or (null entry)
           (>= (- now (%path-command-directory-cache-entry-scanned-at entry))
               *path-command-cache-max-age-seconds*))
       (values nil nil))
      ((and (%path-command-directory-cache-entry-settled-p entry)
            (< (- now (%path-command-directory-cache-entry-checked-at entry))
               *path-command-cache-revalidate-seconds*))
       (values entry t))
      (t
       (let ((stamp (funcall stamp-fn)))
         (if (and (equal stamp (%path-command-directory-cache-entry-stamp entry))
                  (or (%path-command-directory-cache-entry-settled-p entry)
                      (< (- now (%path-command-directory-cache-entry-scanned-at entry))
                         *path-command-cache-ttl-seconds*)))
             (let ((checked
                     (%make-path-command-directory-cache-entry
                      (%path-command-directory-cache-entry-stamp entry)
                      (%path-command-directory-cache-entry-scanned-at entry)
                      now
                      (%path-command-directory-cache-entry-settled-p entry)
                      (%path-command-directory-cache-entry-entries entry))))
               (%with-path-command-directory-cache-lock
                 (when (eq entry (gethash key *path-command-directory-cache*))
                   (setf (gethash key *path-command-directory-cache*) checked)))
               (values checked t))
             (values nil nil)))))))

(defun %path-command-directory-cache-generation ()
  (%with-path-command-directory-cache-lock
    *path-command-directory-cache-generation*))

(defun %path-command-directory-cache-put (key generation entry)
  (%with-path-command-directory-cache-lock
    (when (= generation *path-command-directory-cache-generation*)
      (when (>= (hash-table-count *path-command-directory-cache*)
                *path-command-cache-limit*)
        (clrhash *path-command-directory-cache*))
      (setf (gethash key *path-command-directory-cache*) entry)))
  entry)

(defun %path-command-relative-directory-p (directory)
  (not (and (plusp (length directory))
            (char= (char directory 0) #\/))))

(defun %path-command-directory-record (directory filesystem)
  "Return the cache record holding DIRECTORY's entries, reading the directory
only when no valid record exists. A relative PATH element (empty, \".\", ...)
names a different directory after every cd, so it is read on each call and
never cached."
  (let* ((directory-files-fn
           (and (nshell.domain.filesystem:filesystem-p filesystem)
                (nshell.domain.filesystem:filesystem-directory-files filesystem)))
         (pathname (%path-command-directory-pathname directory)))
    (if (%path-command-relative-directory-p directory)
        (let ((entries (funcall directory-files-fn pathname)))
          (%make-path-command-directory-cache-entry
           nil 0d0 0d0 nil entries))
        (let* ((resolved (merge-pathnames pathname))
               (key (%path-command-directory-cache-key resolved filesystem)))
          (labels ((now ()
                     (coerce (funcall *path-command-cache-clock-fn*) 'double-float))
                   (lookup ()
                     (%path-command-directory-cache-get
                      key
                      (lambda () (%path-command-directory-stamp resolved))
                      (now)))
                   (scan ()
                     (let* ((generation (%path-command-directory-cache-generation))
                            (wall (ignore-errors
                                   (funcall *path-command-cache-wall-clock-fn*)))
                            (stamp-before (%path-command-directory-stamp resolved))
                            (entries (funcall directory-files-fn pathname))
                            (stamp-after (%path-command-directory-stamp resolved))
                            (now (now))
                            (entry (%make-path-command-directory-cache-entry
                                    stamp-after now now
                                    (%path-command-stamp-settled-p
                                     stamp-after entries wall)
                                    (copy-list entries))))
                       (if (equal stamp-before stamp-after)
                           (%path-command-directory-cache-put key generation entry)
                           entry))))
            (multiple-value-bind (cached foundp) (lookup)
              (if foundp
                  cached
                  (%with-path-command-directory-key-lock (key)
                    (multiple-value-bind (locked-cached locked-foundp) (lookup)
                      (if locked-foundp
                          locked-cached
                          (scan)))))))))))

(defun %list-path-command-directory (directory filesystem)
  (copy-list
   (%path-command-directory-cache-entry-entries
    (%path-command-directory-record directory filesystem))))
