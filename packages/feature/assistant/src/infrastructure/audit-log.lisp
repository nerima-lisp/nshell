(in-package #:nshell.feature.assistant)

(defvar *assistant-audit-file-path-override* nil)

(defun %assistant-default-audit-file-path ()
  (let* ((xdg-state-home (uiop:getenv "XDG_STATE_HOME"))
         ;; Existing persistence resolves user files from USER-HOMEDIR-PATHNAME.
         ;; XDG_STATE_HOME is preferred when supplied; the fallback keeps the
         ;; audit file in nshell's existing home-based state directory.
         (base-directory
           (if (and xdg-state-home (plusp (length xdg-state-home)))
               (pathname xdg-state-home)
               (user-homedir-pathname)))
         (relative-path
           (if (and xdg-state-home (plusp (length xdg-state-home)))
               "nshell/ai-audit.jsonl"
               ".nshell/ai-audit.jsonl")))
    (merge-pathnames relative-path
                     (uiop:ensure-directory-pathname base-directory))))

(defun assistant-audit-file-path ()
  (or *assistant-audit-file-path-override*
      (%assistant-default-audit-file-path)))

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
                                denylist-commands)
  (let ((redacted-payload
          (redact-payload payload
                          :denylist-paths denylist-paths
                          :denylist-commands denylist-commands))
        (redacted-response
          (redact-payload response-summary
                          :denylist-paths denylist-paths
                          :denylist-commands denylist-commands)))
    (json-kit:alist->json-object
     (list (cons "payload" (%assistant-json-value redacted-payload))
           (cons "response-summary" (%assistant-json-value redacted-response))))))

(defun append-assistant-audit-entry
    (payload response-summary &key denylist-paths denylist-commands)
  "Append one redacted payload and response summary as a JSONL entry.

Return NIL when serialization or persistence fails so audit failure cannot
change shell execution control flow."
  (handler-case
      (let ((path (assistant-audit-file-path)))
        (ensure-directories-exist path)
        (with-open-file (stream path
                                :direction :output
                                :if-exists :append
                                :if-does-not-exist :create)
          (write-line (json-kit:stringify
                       (%assistant-audit-record payload response-summary
                                                denylist-paths
                                                denylist-commands))
                      stream))
        t)
    ;; Existing persistence treats an unavailable optional state file as a
    ;; non-fatal condition. Keep the audit boundary best-effort for the same
    ;; reason: an audit I/O failure must not break the interactive shell.
    (error () nil)))
