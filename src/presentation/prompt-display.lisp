(in-package #:nshell.presentation)

(defun %wide-character-p (char)
  (let ((code (char-code char)))
    (or (<= #x1100 code #x115f)
        (<= #x2e80 code #xa4cf)
        (<= #xac00 code #xd7a3)
        (<= #xf900 code #xfaff)
        (<= #xfe10 code #xfe19)
        (<= #xfe30 code #xfe6f)
        (<= #xff00 code #xff60)
        (<= #xffe0 code #xffe6))))

(defun %char-visible-width (char)
  (cond
    ((member char '(#\Newline #\Return #\Tab) :test #'char=) 0)
    ((%wide-character-p char) 2)
    (t 1)))

(defun %string-visible-width (text)
  (loop for char across text
        sum (%char-visible-width char)))

(defun %segments-visible-width (segments)
  (loop for segment in segments
        sum (%string-visible-width
             (nshell.domain.prompting:prompt-segment-text segment))))

(defun %home-prefix-p (home cwd)
  "Return T when CWD is HOME or a descendant of HOME on a path boundary."
  (let ((home-length (length home))
        (cwd-length (length cwd)))
    (and (<= home-length cwd-length)
         (string= home cwd :end2 home-length)
         (or (= home-length cwd-length)
             (let ((separator (char cwd home-length)))
               (or (char= separator #\/)
                   (char= separator #\\)))))))

(defun %display-cwd (cwd)
  "Return CWD with a home-directory prefix shortened to ~ when appropriate."
  (let ((home (uiop:getenv "HOME")))
    (if (and home (%home-prefix-p home cwd))
        (concatenate 'string "~" (subseq cwd (length home)))
        cwd)))

(defun %truncate-string-to-width (text width)
  (with-output-to-string (out)
    (loop with used = 0
          for char across text
          for char-width = (%char-visible-width char)
          while (<= (+ used char-width) width)
          do (progn
               (write-char char out)
               (incf used char-width)))))

(defun %truncate-segments (segments width)
  "Return SEGMENTS shortened so their visible terminal width is at most WIDTH."
  (when (plusp width)
    (loop with remaining = width
          for segment in segments
          while (plusp remaining)
          for text = (nshell.domain.prompting:prompt-segment-text segment)
          for kind = (nshell.domain.prompting:prompt-segment-kind segment)
          for text-width = (%string-visible-width text)
          if (<= text-width remaining)
            collect (progn
                      (decf remaining text-width)
                      segment)
          else
            append (let ((truncated (%truncate-string-to-width text remaining)))
                      (when (plusp (length truncated))
                        (setf remaining 0)
                        (list (nshell.domain.prompting:make-prompt-segment
                               truncated
                               kind)))))))

(defun %prompt-terminal-width ()
  "Return current terminal width, falling back to 80 columns outside a tty."
  (handler-case
      (multiple-value-bind (rows cols) (nshell.infrastructure.acl:get-terminal-size)
        (declare (ignore rows))
        (if (plusp cols) cols 80))
    (error () 80)))

(defun segment-kind->role (kind)
  "Map prompt segment kind to highlight role for theme lookup."
  (case kind
    (:host :prompt-host)
    (:path :prompt-path)
    (:exit :prompt-ok)
    (:exit-error :prompt-error)
    (:literal :normal)
    (:git :prompt-path)
    (:duration :comment)
    (:time :comment)
    (t :normal)))

(defun %current-prompt-model (last-exit last-command-duration-ms)
  (nshell.domain.prompting:make-prompt-model
   :hostname (or (uiop:hostname) "localhost")
   :cwd (%display-cwd (namestring (uiop:getcwd)))
   :exit-code last-exit
   :duration-ms last-command-duration-ms))

(defun %write-colored-segments (stream theme segments)
  (dolist (seg segments)
    (let ((text (nshell.domain.prompting:prompt-segment-text seg))
          (kind (nshell.domain.prompting:prompt-segment-kind seg)))
      (format stream "~a~a~C[0m"
              (theme-color->ansi theme (segment-kind->role kind))
              text
              #\Esc))))

(defun %colored-segments-string (theme segments)
  (with-output-to-string (stream)
    (%write-colored-segments stream theme segments)))

(defun %write-right-prompt (theme left-segments right-segments terminal-width)
  (let* ((left-width (%segments-visible-width left-segments))
         (available (- terminal-width left-width 2))
         (visible-right-segments (%truncate-segments right-segments available)))
    (when visible-right-segments
      (let* ((right-width (%segments-visible-width visible-right-segments))
             (padding (- terminal-width left-width right-width)))
        (when (> padding 0)
          (nshell.infrastructure.terminal:ansi-save-cursor)
          (format t "~C[~dC~a"
                  #\Esc
                  padding
                  (%colored-segments-string theme visible-right-segments))
          (nshell.infrastructure.terminal:ansi-restore-cursor))))))

(defun render-prompt (config last-exit &key (last-command-duration-ms nil)
                                      (terminal-width (%prompt-terminal-width)))
  "Render the left prompt with theme colors."
  (let* ((theme (nshell.domain.configuration:config-theme config))
         (pm (%current-prompt-model last-exit last-command-duration-ms))
         (segments (nshell.domain.prompting:render-prompt-model pm))
         (right-segments (nshell.domain.prompting:render-right-prompt-model pm)))
    (%write-colored-segments *standard-output* theme segments)
    (when right-segments
      (%write-right-prompt theme segments right-segments terminal-width))
    (finish-output)
    (%segments-visible-width segments)))
