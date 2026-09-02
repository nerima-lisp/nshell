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
        *path-command-cache-ttl-seconds*
        *path-command-cache-limit*))

(defun %path-command-directory-stamp (directory)
  (when (functionp *path-command-directory-stamp-fn*)
    (ignore-errors (funcall *path-command-directory-stamp-fn* directory))))

(defun %path-command-directory-cache-valid-p (entry stamp now)
  (and entry
       (equal stamp (%path-command-directory-cache-entry-stamp entry))
       (< (- now (%path-command-directory-cache-entry-checked-at entry))
          *path-command-cache-ttl-seconds*)))

(defun %path-command-directory-cache-get (key stamp now)
  (%with-path-command-directory-cache-lock
    (let ((entry (gethash key *path-command-directory-cache*)))
      (if (%path-command-directory-cache-valid-p entry stamp now)
          (values (copy-list
                   (%path-command-directory-cache-entry-entries entry))
                  t)
          (values nil nil)))))

(defun %path-command-directory-cache-generation ()
  (%with-path-command-directory-cache-lock
    *path-command-directory-cache-generation*))

(defun %path-command-directory-cache-put (key generation stamp now entries)
  (%with-path-command-directory-cache-lock
    (when (= generation *path-command-directory-cache-generation*)
      (when (>= (hash-table-count *path-command-directory-cache*)
                *path-command-cache-limit*)
        (clrhash *path-command-directory-cache*))
      (setf (gethash key *path-command-directory-cache*)
            (%make-path-command-directory-cache-entry
             stamp now (copy-list entries)))))
  entries)

(defun %list-path-command-directory (directory filesystem)
  (let* ((directory-files-fn
           (and (nshell.domain.filesystem:filesystem-p filesystem)
                (nshell.domain.filesystem:filesystem-directory-files filesystem)))
         (pathname (%path-command-directory-pathname directory))
         (resolved (merge-pathnames pathname))
         (key (%path-command-directory-cache-key resolved filesystem)))
    (labels ((lookup ()
               (let ((now (coerce (funcall *path-command-cache-clock-fn*)
                                   'double-float))
                     (stamp (%path-command-directory-stamp resolved)))
                 (%path-command-directory-cache-get key stamp now)))
             (scan ()
               (let* ((generation (%path-command-directory-cache-generation))
                      (stamp-before (%path-command-directory-stamp resolved))
                      (entries (funcall directory-files-fn pathname))
                      (stamp-after (%path-command-directory-stamp resolved))
                      (now (coerce (funcall *path-command-cache-clock-fn*)
                                   'double-float)))
                 (when (equal stamp-before stamp-after)
                   (%path-command-directory-cache-put
                    key generation stamp-after now entries))
                 entries)))
      (multiple-value-bind (cached foundp) (lookup)
        (if foundp
            cached
            (%with-path-command-directory-key-lock (key)
              (multiple-value-bind (locked-cached locked-foundp) (lookup)
                (if locked-foundp
                    locked-cached
                    (scan)))))))))
