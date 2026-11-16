(in-package #:nshell.domain.completion)

(define-value-struct %path-command-query
  ((path nil :type (or null string))
   (prefix "" :type string))
  :public-accessors nil
  :constructor %make-path-command-query)

(defparameter *path-command-cache-ttl-seconds* 0.25d0
  "Maximum age of cached PATH directory entries whose stamp cannot prove that a
later change would alter it (see %PATH-COMMAND-STAMP-SETTLED-P).")

(defparameter *path-command-cache-revalidate-seconds* 1d0
  "How long a settled PATH directory entry is trusted without taking the
directory's stamp again. Bounds how long a command added to PATH stays unseen.")

(defparameter *path-command-cache-max-age-seconds* 30d0
  "Age after which an entry is rescanned even with an unchanged stamp, because
some changes (a symlink target changing kind) keep the directory mtime.")

(defparameter *path-command-stamp-settle-seconds* 2
  "A stamp this many seconds older than the scan start is settled: a change
after the scan gets a later whole-second mtime, so it cannot repeat the stamp.")

(defparameter *path-command-cache-limit* 128
  "Maximum number of PATH directory entry cache records.")

(defvar *path-command-directory-stamp-fn* #'file-write-date
  "Function called with a resolved PATH directory to obtain its change stamp.")

(defvar *path-command-cache-clock-fn*
  (lambda ()
    (/ (get-internal-real-time)
       (coerce internal-time-units-per-second 'double-float)))
  "Monotonic clock used to expire PATH directory cache records.")

(defvar *path-command-cache-wall-clock-fn* #'get-universal-time
  "Wall clock, in the stamp function's universal-time seconds, read before a
PATH directory scan to decide whether its stamp is settled.")

(define-value-struct %path-command-directory-cache-entry
  ((stamp nil)
   (scanned-at 0d0 :type double-float)
   (checked-at 0d0 :type double-float)
   (settled-p nil)
   (entries nil :type list))
  :public-accessors nil
  :constructor %make-path-command-directory-cache-entry)

(defvar *path-command-directory-cache* (make-hash-table :test #'equal))
(defvar *path-command-directory-cache-generation* 0)

(defvar *path-command-cache-lock-factory* nil)
(defvar *path-command-directory-cache-lock* nil)
(defvar *path-command-directory-key-locks* (make-hash-table :test #'equal))
