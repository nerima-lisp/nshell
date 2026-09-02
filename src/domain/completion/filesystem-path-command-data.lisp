(in-package #:nshell.domain.completion)

(defstruct (%path-command-query
            (:constructor %make-path-command-query (path prefix))
            (:conc-name %path-command-query-))
  (path nil :type (or null string) :read-only t)
  (prefix "" :type string :read-only t))

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
