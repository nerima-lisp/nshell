(in-package #:nshell.feature.assistant)

(defvar *assistant-audit-file-path-override* nil)

(defparameter +assistant-audit-max-bytes+ (* 10 1024 1024))

(defun %assistant-default-audit-file-path ()
  (assistant-state-file-path "ai-audit.jsonl"))

(defun assistant-audit-file-path ()
  (or *assistant-audit-file-path-override*
      (%assistant-default-audit-file-path)))

(defun assistant-audit-tail (count)
  (if (not (and (integerp count) (plusp count)))
      (values nil nil)
      (handler-case
      (let ((path (assistant-audit-file-path)))
        (if (probe-file path)
            (with-open-file (stream path :direction :input)
              (let ((end (file-position stream :end))
                    (starts (list (file-position stream :end))))
                (loop for position downfrom (1- end) to 0
                      while (< (length starts) (1+ count))
                      do (file-position stream position)
                         (when (char= (read-char stream) #\Newline)
                           (push (1+ position) starts)))
                (file-position stream (or (car starts) 0))
                (let ((lines nil))
                  (loop for line = (read-line stream nil nil)
                        while line do (push line lines))
                  (values (last (nreverse lines) count) t))))
            (values nil nil)))
        (error ()
          (values nil nil)))))

(defun %assistant-json-key (key)
  (cond ((stringp key) key)
        ((symbolp key) (string-downcase (symbol-name key)))
        (t (princ-to-string key))))

(defun %assistant-json-alist-p (value)
  (and (listp value)
       (every (lambda (entry)
                (and (consp entry)
                     (or (stringp (car entry))
                         (symbolp (car entry)))))
              value)))

(defun %assistant-json-value (value)
  (cond
    ((stringp value) value)
    ((%assistant-plist-p value)
     (json-kit:alist->json-object
      (loop for tail on value by #'cddr
            collect (cons (%assistant-json-key (first tail))
                          (%assistant-json-value (second tail))))))
    ((%assistant-json-alist-p value)
     (json-kit:alist->json-object
      (mapcar (lambda (entry)
                (cons (%assistant-json-key (car entry))
                      (%assistant-json-value (cdr entry))))
              value)))
    ((vectorp value)
     (map 'vector #'%assistant-json-value value))
    ((consp value)
     (mapcar #'%assistant-json-value value))
    (t value)))

(defun %assistant-audit-record (payload response-summary denylist-paths
                                denylist-commands denylist-values)
  (let ((redacted-payload
          (redact-payload payload
                          :denylist-paths denylist-paths
                          :denylist-commands denylist-commands
                          :denylist-values denylist-values))
        (redacted-response
          (redact-payload response-summary
                          :denylist-paths denylist-paths
                          :denylist-commands denylist-commands
                          :denylist-values denylist-values)))
    (json-kit:alist->json-object
     (list (cons "payload" (%assistant-json-value redacted-payload))
           (cons "response-summary" (%assistant-json-value redacted-response))))))

(defun append-assistant-audit-entry
    (payload response-summary
     &key (denylist-paths +assistant-default-denylist-paths+)
          (denylist-commands +assistant-default-denylist-commands+)
          denylist-values)
  "Append one redacted payload and response summary as a JSONL entry.

Return NIL when serialization or persistence fails so audit failure cannot
change shell execution control flow."
  (handler-case
      (let ((path (assistant-audit-file-path)))
        (%assistant-ensure-secure-state-directory path)
        (when (and (probe-file path)
                   (>= (with-open-file (stream path :direction :input)
                         (file-length stream))
                       +assistant-audit-max-bytes+))
          (let ((rotated (merge-pathnames "ai-audit.jsonl.1"
                                          (assistant-state-directory-path))))
            (when (probe-file rotated) (delete-file rotated))
            (uiop:rename-file-overwriting-target path rotated)))
        (with-open-file (stream path
                                :direction :output
                                :if-exists :append
                                :if-does-not-exist :create)
          (write-line (json-kit:stringify
                       (%assistant-audit-record payload response-summary
                                                denylist-paths
                                                denylist-commands
                                                denylist-values))
                      stream))
        (%assistant-secure-state-file path)
        t)
    ;; Existing persistence treats an unavailable optional state file as a
    ;; non-fatal condition. Keep the audit boundary best-effort for the same
    ;; reason: an audit I/O failure must not break the interactive shell.
    (error () nil)))
