(in-package #:nshell.feature.assistant)

(defparameter +assistant-default-transcript-output-max-lines+ 10)

(defstruct (assistant-transcript-entry
            (:constructor %make-assistant-transcript-entry (payload)))
  payload)

(defstruct (assistant-snapshot
            (:constructor %make-assistant-snapshot (payload)))
  payload)

(defun %assistant-export-origin (origin)
  (and origin
       (string-downcase
        (if (keywordp origin)
            (symbol-name origin)
            (princ-to-string origin)))))

(defun %assistant-export-git (git denylist-values)
  (list (cons "branch"
              (redact-text (getf git :branch)
                           :denylist-values denylist-values))
        (cons "dirty" (not (null (getf git :dirty))))))

(defun %assistant-export-last (last denylist-paths denylist-commands
                               denylist-values)
  (when last
    (list (cons "text"
                (redact-lines (getf last :text)
                              :denylist-paths denylist-paths
                              :denylist-commands denylist-commands
                              :denylist-values denylist-values))
          (cons "exit" (getf last :exit))
          (cons "duration-ms" (getf last :duration-ms)))))

(defun %assistant-export-output-head
    (output denylist-paths denylist-commands denylist-values)
  (if (stringp output)
      (let ((lines
              (with-input-from-string (input output)
                (loop for line = (read-line input nil nil)
                      for count from 1
                      while (and line
                                 (<= count
                                     +assistant-default-transcript-output-max-lines+))
                      collect line))))
        (if lines
            (let ((redacted
                    (redact-lines
                     (format nil "~{~a~^~%~}" lines)
                     :denylist-paths denylist-paths
                     :denylist-commands denylist-commands
                     :denylist-values denylist-values)))
              (coerce
               (with-input-from-string (input redacted)
                 (loop for line = (read-line input nil nil)
                       while line collect line))
               'vector))
            #()))
      #()))

(defun make-assistant-transcript-entry
    (&key timestamp cwd text exit duration-ms origin output-head git
          denylist-paths denylist-commands denylist-values)
  (let ((payload
          (list (cons "timestamp" timestamp)
                (cons "cwd" (redact-text cwd :denylist-values denylist-values))
                (cons "text"
                      (redact-lines text
                                    :denylist-paths denylist-paths
                                    :denylist-commands denylist-commands
                                    :denylist-values denylist-values))
                (cons "exit" exit)
                (cons "duration-ms" duration-ms)
                (cons "origin" (%assistant-export-origin origin))
                (cons "output-head"
                      (%assistant-export-output-head
                       output-head denylist-paths denylist-commands
                       denylist-values))
                (cons "git" (%assistant-export-git git denylist-values)))))
    (%make-assistant-transcript-entry
     (redact-payload payload
                    :denylist-paths denylist-paths
                    :denylist-commands denylist-commands
                    :denylist-values denylist-values))))

(defun make-assistant-snapshot
    (&key cwd git jobs last env-names session-id ai
          denylist-paths denylist-commands denylist-values)
  (let ((payload
          (list (cons "cwd" (redact-text cwd :denylist-values denylist-values))
                (cons "git" (%assistant-export-git git denylist-values))
                (cons "jobs" (coerce jobs 'vector))
                (cons "last"
                      (%assistant-export-last last denylist-paths
                                               denylist-commands
                                               denylist-values))
                (cons "env-names"
                      (coerce (%assistant-environment-names env-names)
                              'vector))
                (cons "session-id"
                      (redact-text session-id
                                   :denylist-values denylist-values))
                (cons "ai"
                      (list (cons "connected" (not (null (getf ai :connected))))
                            (cons "turns" (getf ai :turns))
                            (cons "tokens" (getf ai :tokens)))))))
    (%make-assistant-snapshot
     (redact-payload payload
                    :denylist-paths denylist-paths
                    :denylist-commands denylist-commands
                    :denylist-values denylist-values))))
