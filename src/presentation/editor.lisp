(in-package #:nshell.presentation)

(defun %split-editor-command (command)
  (let ((tokens '())
        (current (make-string-output-stream))
        (quoted-p nil)
        (escaped-p nil)
        (token-started-p nil))
    (labels ((finish-token ()
               (when token-started-p
                 (push (get-output-stream-string current) tokens)
                 (setf current (make-string-output-stream)
                       token-started-p nil))))
      (loop for character across command
            do (cond
                 (escaped-p
                  (write-char character current)
                  (setf escaped-p nil
                        token-started-p t))
                 ((char= character #\\)
                  (setf escaped-p t
                        token-started-p t))
                 ((and quoted-p (char= character quoted-p))
                  (setf quoted-p nil
                        token-started-p t))
                 ((and (not quoted-p)
                       (or (char= character #\') (char= character #\")))
                  (setf quoted-p character
                        token-started-p t))
                 ((and (not quoted-p)
                       (or (char= character #\Space)
                           (char= character #\Tab)
                           (char= character #\Newline)))
                  (finish-token))
                 (t
                  (write-char character current)
                  (setf token-started-p t))))
      (when escaped-p
        (write-char #\\ current))
      (finish-token)
      (nreverse tokens))))

(defun %editor-command-argv ()
  (let* ((environment (ensure-environment))
         (command (or (loop for name in '("NSHELL_EDITOR" "VISUAL" "EDITOR")
                            for value =
                            (nshell.domain.environment:env-get environment name)
                            when (and value (plusp (length value)))
                            return value)
                      "vi"))
         (argv (%split-editor-command command)))
    (if (and argv (plusp (length (first argv)))
             (not (string= (first argv) "")))
        argv
        '("vi"))))

(defun %write-editor-buffer (path text)
  (with-open-file (stream path :direction :output :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string text stream)
    (terpri stream)))

(defun %read-editor-buffer (path)
  (let ((text (host-kit:read-file-string path)))
    (if (and (plusp (length text))
             (char= (char text (1- (length text))) #\Newline))
        (subseq text 0 (1- (length text)))
        text)))

(defun %run-external-editor (argv path)
  (nshell.infrastructure.terminal:ansi-disable-sgr-mouse)
  (nshell.infrastructure.terminal:ansi-disable-bracketed-paste)
  (nshell.infrastructure.terminal:restore-terminal-mode)
  (unwind-protect
       (progn
         (finish-output)
         (sync-exported-environment)
         (nshell.infrastructure.acl:run-external-exec
          (first argv) (append (rest argv) (list (namestring path)))))
    (ignore-errors (nshell.infrastructure.terminal:enable-raw-mode))
    (ignore-errors (nshell.infrastructure.terminal:ansi-enable-bracketed-paste))
    (ignore-errors (nshell.infrastructure.terminal:ansi-enable-sgr-mouse))))
