(in-package #:nshell.domain.completion)

(defun %command-prefix-has-directory-p (prefix)
  (position-if #'%path-separator-p prefix))

(defun %split-path (path)
  (let ((start 0)
        (parts nil))
    (loop for pos = (position #\: path :start start)
          do (push (subseq path start pos) parts)
          while pos
          do (setf start (1+ pos)))
    (nreverse parts)))

(defun %join-directory-command (directory command &key (empty-directory directory))
  (let ((dir (if (string= directory "") empty-directory directory)))
    (cond
      ((string= dir "") command)
      ((%path-separator-p (char dir (1- (length dir))))
       (concatenate 'string dir command))
      (t (concatenate 'string dir "/" command)))))

(defun command-path-candidates (command path executable-p &key (empty-directory ""))
  "Return executable path candidates for COMMAND projected through PATH."
  (if (%command-prefix-has-directory-p command)
      (when (funcall executable-p command)
        (list command))
      (loop for directory in (%split-path (or path ""))
            for candidate = (%join-directory-command
                             directory command :empty-directory empty-directory)
            when (funcall executable-p candidate)
            collect candidate)))

(defun %first-command-path-candidate (command path executable-p
                                      &key (empty-directory ""))
  (if (%command-prefix-has-directory-p command)
      (when (funcall executable-p command)
        command)
      (loop for directory in (%split-path (or path ""))
            for candidate = (%join-directory-command
                             directory command :empty-directory empty-directory)
            when (funcall executable-p candidate)
              do (return candidate))))

(defun %entry-command-name (entry)
  (let ((name (if (pathnamep entry)
                  (file-namestring entry)
                  (let* ((text (princ-to-string entry))
                         (slash (position-if #'%path-separator-p text :from-end t)))
                    (if slash (subseq text (1+ slash)) text)))))
    (and (< 0 (length name)) name)))

(defvar *path-command-directory-files-fn* nil
  "Function called with a PATH directory pathname to list command candidates.")

(defvar *path-command-executable-p-fn* nil
  "Function called with a candidate pathname to decide whether it is executable.")

(defvar *path-command-directory-map-fn* #'mapcar
  "Function called with a directory reader and PATH directories to map over.")

(defun %executable-candidate-p (entry)
  (ignore-errors
      (or (null *path-command-executable-p-fn*)
          (funcall *path-command-executable-p-fn* entry))))

(defstruct (%path-command-query
            (:constructor %make-path-command-query (path prefix))
            (:conc-name %path-command-query-))
  (path nil :type (or null string) :read-only t)
  (prefix "" :type string :read-only t))

(defun %path-command-query-active-p (query)
  (and *path-command-directory-files-fn*
       (%path-command-query-path query)
       (not (%command-prefix-has-directory-p
             (%path-command-query-prefix query)))))

(defun %path-command-directory-pathname (directory)
  (pathname (if (string= directory "")
                "./"
                directory)))

(defparameter *path-command-cache-ttl-seconds* 0.25d0
  "Maximum age of cached PATH directory entries.")

(defparameter *path-command-cache-limit* 128
  "Maximum number of PATH directory entry cache records.")

(defvar *path-command-directory-stamp-fn* #'file-write-date
  "Function called with a resolved PATH directory to obtain its change stamp.")

(defvar *path-command-cache-clock-fn*
  (lambda ()
    (/ (get-internal-real-time)
       (coerce internal-time-units-per-second 'double-float)))
  "Monotonic clock used to expire PATH directory cache records.")

(defstruct (%path-command-directory-cache-entry
            (:constructor %make-path-command-directory-cache-entry
                (stamp checked-at entries))
            (:conc-name %path-command-directory-cache-entry-))
  stamp
  (checked-at 0d0 :type double-float :read-only t)
  (entries nil :type list :read-only t))

(defvar *path-command-directory-cache* (make-hash-table :test #'equal))
(defvar *path-command-directory-cache-generation* 0)

(defvar *path-command-cache-lock-factory* nil)
(defvar *path-command-directory-cache-lock* nil)
(defvar *path-command-directory-key-locks* (make-hash-table :test #'equal))

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

(defun %path-command-directory-cache-key (directory)
  (list (namestring directory)
        *path-command-directory-files-fn*
        *path-command-directory-stamp-fn*
        *path-command-cache-clock-fn*
        *path-command-cache-ttl-seconds*
        *path-command-cache-limit*))

(defun %path-command-directory-stamp (directory)
  (ignore-errors (funcall *path-command-directory-stamp-fn* directory)))

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

(defun %list-path-command-directory (directory)
  (let* ((pathname (%path-command-directory-pathname directory))
         (resolved (merge-pathnames pathname))
         (key (%path-command-directory-cache-key resolved)))
    (labels ((lookup ()
               (let ((now (coerce (funcall *path-command-cache-clock-fn*)
                                   'double-float))
                     (stamp (%path-command-directory-stamp resolved)))
                 (%path-command-directory-cache-get key stamp now)))
             (scan ()
               (let* ((generation (%path-command-directory-cache-generation))
                      (stamp-before (%path-command-directory-stamp resolved))
                      (entries (funcall *path-command-directory-files-fn* pathname))
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

(defun %path-command-entry-candidate (entry prefix executable-p)
  (let ((name (%entry-command-name entry)))
    (when (and name
               (%starts-with-p prefix name)
               (funcall executable-p entry))
      (make-candidate name :kind :command))))

(defun %path-command-candidates-from-entries
    (entries-by-directory prefix executable-p)
  "Reduce ordered PATH entries to deterministic executable candidates.

The caller owns directory enumeration, caching, and concurrency.  This
function only performs filtering, deduplication, error isolation, and
ordering, so those semantics can be tested without a filesystem."
  (let ((candidates (%make-empty-filesystem-candidate-set)))
    (dolist (entries entries-by-directory)
      (handler-case
          (dolist (entry entries)
            (%filesystem-candidate-set-add
             candidates
             (%path-command-entry-candidate entry prefix executable-p)))
        (error () candidates)))
    (sort (%filesystem-candidate-set-candidates candidates)
          #'string<
          :key #'candidate-text)))

(defun %make-path-command-directory-reader ()
  "Return a reader that carries request-local filesystem adapters into workers."
  (let ((directory-files-fn *path-command-directory-files-fn*)
        (directory-stamp-fn *path-command-directory-stamp-fn*)
        (cache-clock-fn *path-command-cache-clock-fn*)
        (cache-ttl-seconds *path-command-cache-ttl-seconds*)
        (cache-limit *path-command-cache-limit*))
    (lambda (directory)
      (let ((*path-command-directory-files-fn* directory-files-fn)
            (*path-command-directory-stamp-fn* directory-stamp-fn)
            (*path-command-cache-clock-fn* cache-clock-fn)
            (*path-command-cache-ttl-seconds* cache-ttl-seconds)
            (*path-command-cache-limit* cache-limit))
        (handler-case
            (%list-path-command-directory directory)
          (error () nil))))))

(defun %command-candidates-from-path (path prefix)
  "Return executable command candidates from PATH that start with PREFIX."
  (let ((query (%make-path-command-query path prefix)))
    (if (not (%path-command-query-active-p query))
        nil
        (let* ((query-prefix (%path-command-query-prefix query))
               (directories (%split-path (%path-command-query-path query)))
               (entries-by-directory
                 (funcall *path-command-directory-map-fn*
                          (%make-path-command-directory-reader)
                          directories)))
          (%path-command-candidates-from-entries
           entries-by-directory
           query-prefix
           #'%executable-candidate-p)))))
