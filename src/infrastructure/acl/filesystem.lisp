(in-package #:nshell.infrastructure.acl)

;;; Completion lists a directory on every keystroke, so a directory with
;;; thousands of entries (a busy /tmp) costs a full listing per character. The
;;; cache below keys on the directory's write date as well as a time-to-live,
;;; so an entry added or removed through any process invalidates it at once
;;; rather than after the time-to-live expires.

(defparameter *directory-listing-cache-ttl-seconds* 5)

(defparameter *directory-listing-cache-limit* 128
  "Entries kept before the cache is dropped whole; walking a deep tree must not
grow it without bound.")

(defvar *directory-listing-cache* (make-hash-table :test #'equal))

(defun clear-directory-listing-cache ()
  (clrhash *directory-listing-cache*))

(defun %directory-listing-stamp (directory)
  (ignore-errors (file-write-date (host-kit:ensure-directory-pathname directory))))

(defun %directory-listing-cache-key (kind directory)
  (cons kind (ignore-errors
              (namestring (host-kit:ensure-directory-pathname directory)))))

(defun %cached-directory-listing (kind directory reader)
  (let ((key (%directory-listing-cache-key kind directory)))
    (if (null (cdr key))
        (funcall reader directory)
        (let ((stamp (%directory-listing-stamp directory))
              (now (get-universal-time))
              (entry (gethash key *directory-listing-cache*)))
          (if (and entry
                   (eql stamp (first entry))
                   (< (- now (second entry)) *directory-listing-cache-ttl-seconds*))
              (third entry)
              (let ((value (funcall reader directory)))
                (when (> (hash-table-count *directory-listing-cache*)
                         *directory-listing-cache-limit*)
                  (clear-directory-listing-cache))
                (setf (gethash key *directory-listing-cache*)
                      (list stamp now value))
                value))))))

(defun cached-directory-files (directory)
  (%cached-directory-listing :files directory #'host-kit:directory-files))

(defun cached-subdirectories (directory)
  (%cached-directory-listing :subdirectories directory #'host-kit:subdirectories))

(defun make-host-filesystem ()
  (nshell.domain.filesystem:make-filesystem
   :directory-files #'cached-directory-files
   :subdirectories #'cached-subdirectories
   :executable-p #'executable-file-p
   :directory-map #'map-path-command-directories))
