(in-package #:nshell.feature.assistant)

(defparameter +assistant-default-output-max-bytes+ 8192)

(defstruct (assistant-context
            (:constructor make-assistant-context
                (&key command exit duration-ms cwd git-status last-output
                      environment-names)))
  command
  exit
  duration-ms
  cwd
  git-status
  last-output
  environment-names)

(defun %assistant-utf8-char-bytes (character)
  (let ((code (char-code character)))
    (cond ((<= code #x7f) 1)
          ((<= code #x7ff) 2)
          ((<= code #xffff) 3)
          (t 4))))

(defun %assistant-tail-bytes (text max-bytes)
  (if (or (null text) (<= max-bytes 0))
      ""
      (loop with start = (length text)
            with byte-count = 0
            for position downfrom (1- (length text)) to 0
            for character = (char text position)
            for character-bytes = (%assistant-utf8-char-bytes character)
            do (if (> (+ byte-count character-bytes) max-bytes)
                   (return (subseq text start))
                   (progn
                     (incf byte-count character-bytes)
                     (setf start position)))
            finally (return (subseq text start)))))

(defun %assistant-redacted-context-value (value denylist-paths denylist-commands)
  (redact-payload value
                  :denylist-paths denylist-paths
                  :denylist-commands denylist-commands))

(defun assemble-assistant-context
    (&key command exit duration-ms cwd git-status last-output
          (environment-names nil) (last-output-max-bytes
                                   +assistant-default-output-max-bytes+)
          denylist-paths denylist-commands)
  "Build a redacted assistant context from caller-provided shell values.

No filesystem, environment, process, or git operation occurs here."
  (let* (;; cwd and home paths intentionally remain visible; the requirements
          ;; exclude them from redaction, while token-shaped values are removed.
         (redacted-command
           (%assistant-redacted-context-value command denylist-paths
                                              denylist-commands))
         (redacted-git
           (%assistant-redacted-context-value git-status denylist-paths
                                              denylist-commands))
         (redacted-output
           (redact-lines last-output
                         :denylist-paths denylist-paths
                         :denylist-commands denylist-commands))
         (redacted-environment-names
           (%assistant-environment-names environment-names)))
    (make-assistant-context
     :command redacted-command
     :exit exit
     :duration-ms duration-ms
     :cwd (redact-text cwd)
     :git-status redacted-git
     :last-output (%assistant-tail-bytes redacted-output
                                        last-output-max-bytes)
     :environment-names redacted-environment-names)))

(defun assistant-context-payload (context)
  "Return CONTEXT as a JSON-compatible string-keyed alist."
  (list (cons "command" (assistant-context-command context))
        (cons "exit" (assistant-context-exit context))
        (cons "duration-ms" (assistant-context-duration-ms context))
        (cons "cwd" (assistant-context-cwd context))
        (cons "git" (assistant-context-git-status context))
        (cons "last-output" (assistant-context-last-output context))
        (cons "environment-names"
              (assistant-context-environment-names context))))
