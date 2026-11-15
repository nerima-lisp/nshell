(in-package #:nshell.feature.assistant)

(defun assistant-transcript-file-path (session-id)
  (assistant-state-file-path
   (format nil "transcript-~a.jsonl" session-id)))

(defparameter +assistant-max-transcript-sessions+ 20)

(defun %assistant-prune-transcripts ()
  (let ((paths
          (sort (remove-if-not #'probe-file
                               (directory
                                (merge-pathnames "transcript-*.jsonl"
                                                 (assistant-state-directory-path))))
                #'> :key #'file-write-date)))
    (dolist (path (nthcdr +assistant-max-transcript-sessions+ paths))
      (ignore-errors (delete-file path)))))

(defun assistant-snapshot-file-path ()
  (assistant-state-file-path "snapshot.json"))

(defun append-assistant-transcript-entry (session-id entry)
  (handler-case
      (let ((path (assistant-transcript-file-path session-id)))
        (%assistant-ensure-secure-state-directory path)
        (with-open-stream
            (stream (%assistant-open-state-output-stream
                     path sb-posix:o-append))
          (write-line
           (json-kit:stringify
            (%assistant-json-value
             (assistant-transcript-entry-payload entry)))
           stream))
        (%assistant-prune-transcripts)
        t)
    (error () nil)))

;; The snapshot is exported at every prompt render, and the prompt is rendered
;; for every key. Its reader (`nshell --mcp`) uses only the file content, so a
;; write is skipped when the content equals the last successful write to the
;; same path and the file we wrote is still the one at that path. Other nshell
;; sessions share the path and replace the file by rename, and a user may remove
;; it; either leaves our inode with no links. The descriptor kept open on that
;; inode prevents its number from being reused, so FSTAT's link count answers
;; whether the file is still ours without a path lookup.
(defvar *assistant-written-snapshot* nil
  "List (PATH-NAMESTRING CONTENT FD) for the last successful snapshot write.")

(defconstant +assistant-fd-cloexec+ 1) ; FD_CLOEXEC, which SB-POSIX does not export

(defun %assistant-written-snapshot-current-p (path content)
  (destructuring-bind (&optional written-path written-content fd)
      *assistant-written-snapshot*
    (and fd
         (string= path written-path)
         (string= content written-content)
         (ignore-errors
           (plusp (sb-posix:stat-nlink (sb-posix:fstat fd)))))))

(defun %assistant-remember-written-snapshot (path content fd)
  (let ((previous-fd (third *assistant-written-snapshot*)))
    (setf *assistant-written-snapshot* (list path content fd))
    (when previous-fd
      (ignore-errors (sb-posix:close previous-fd)))))

(defun %assistant-open-written-snapshot (path)
  (let ((fd (sb-posix:open (namestring path)
                           (logior sb-posix:o-rdonly sb-posix:o-nofollow))))
    (handler-case
        (progn
          (sb-posix:fcntl fd sb-posix:f-setfd +assistant-fd-cloexec+)
          fd)
      (error (condition)
        (sb-posix:close fd)
        (error condition)))))

(defun write-assistant-snapshot (snapshot)
  (handler-case
      (let* ((path (assistant-snapshot-file-path))
             (path-name (namestring path))
             (content
               (json-kit:stringify
                (%assistant-json-value (assistant-snapshot-payload snapshot)))))
        (unless (%assistant-written-snapshot-current-p path-name content)
          (let ((temporary-path
                  (assistant-state-file-path
                   (format nil "snapshot.json.tmp.~a" (gensym))))
                (fd nil))
            (%assistant-ensure-secure-state-directory path)
            (with-open-stream
                (stream (%assistant-open-state-output-stream
                         temporary-path sb-posix:o-excl))
              (write-string content stream)
              (terpri stream))
            ;; Open before the rename so the descriptor names our inode even
            ;; if another session replaces the path right after it.
            (handler-case
                (progn
                  (setf fd (%assistant-open-written-snapshot temporary-path))
                  (uiop:rename-file-overwriting-target temporary-path path))
              (error (condition)
                (when fd
                  (ignore-errors (sb-posix:close fd)))
                (error condition)))
            (%assistant-remember-written-snapshot path-name content fd)))
        t)
    (error () nil)))
