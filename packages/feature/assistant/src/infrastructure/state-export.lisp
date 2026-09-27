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
        (with-open-file (stream path
                                :direction :output
                                :if-exists :append
                                :if-does-not-exist :create)
          (write-line
           (json-kit:stringify
            (%assistant-json-value
             (assistant-transcript-entry-payload entry)))
           stream))
        (%assistant-secure-state-file path)
        (%assistant-prune-transcripts)
        t)
    (error () nil)))

(defun write-assistant-snapshot (snapshot)
  (handler-case
      (let* ((path (assistant-snapshot-file-path))
             (temporary-path
               (assistant-state-file-path
                (format nil "snapshot.json.tmp.~a" (gensym)))))
        (%assistant-ensure-secure-state-directory path)
        (with-open-file (stream temporary-path
                                :direction :output
                                :if-exists :error
                                :if-does-not-exist :create)
          (write-string
           (json-kit:stringify
            (%assistant-json-value (assistant-snapshot-payload snapshot)))
           stream)
          (terpri stream))
        (%assistant-secure-state-file temporary-path)
        (uiop:rename-file-overwriting-target temporary-path path)
        (%assistant-secure-state-file path)
        t)
    (error () nil)))
