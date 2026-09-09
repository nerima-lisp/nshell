(in-package #:nshell.feature.assistant)

(defun assistant-transcript-file-path (session-id)
  (assistant-state-file-path
   (format nil "transcript-~a.jsonl" session-id)))

(defun assistant-snapshot-file-path ()
  (assistant-state-file-path "snapshot.json"))

(defun append-assistant-transcript-entry (session-id entry)
  (handler-case
      (let ((path (assistant-transcript-file-path session-id)))
        (ensure-directories-exist path)
        (with-open-file (stream path
                                :direction :output
                                :if-exists :append
                                :if-does-not-exist :create)
          (write-line
           (json-kit:stringify
            (%assistant-json-value
             (assistant-transcript-entry-payload entry)))
           stream))
        t)
    (error () nil)))

(defun write-assistant-snapshot (snapshot)
  (handler-case
      (let ((path (assistant-snapshot-file-path)))
        (ensure-directories-exist path)
        (with-open-file (stream path
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (write-string
           (json-kit:stringify
            (%assistant-json-value (assistant-snapshot-payload snapshot)))
           stream)
          (terpri stream))
        t)
    (error () nil)))
