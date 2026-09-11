(in-package #:nshell.presentation)

;; PREVIEW-PROMPT-FORMAT reads the live session's exit code, duration, and
;; config; REPL-STATE-DATA.LISP, which DEFVARs them, loads after this file in
;; the ASDF serial order, so they need a forward SPECIAL declaration here to
;; avoid an undefined-variable warning.
(declaim (special *last-exit-code* *last-command-duration-ms*
                  *failure-explain-available-p* *config*))

(defconstant +path-shorten-threshold-width+ 40
  "A cwd wider than this many columns is shortened fish-style regardless of
the terminal width.")

(defconstant +path-shorten-reserved-input-width+ 30
  "The cwd is shortened fish-style when fewer than this many columns would
otherwise remain in the terminal for typed input.")

(defun %char-visible-width (char)
  "Terminal column width of CHAR, delegating to cl-tty-kit's Unicode-aware
classifier (control/combining -> 0, wide/emoji -> 2, otherwise 1)."
  (cl-tty-kit:char-width char))

(defun %string-visible-width (text)
  "Sum of the terminal column widths of the characters in TEXT."
  (cl-tty-kit:string-width text))

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

(defun %strip-trailing-slash (path)
  "Drop a trailing path separator, except when PATH is the separator alone."
  (if (and (> (length path) 1)
           (char= (char path (1- (length path))) #\/))
      (subseq path 0 (1- (length path)))
      path))

(defun %shorten-path-component (component)
  "Cut COMPONENT to its first character, or its first two when it starts with
a dot, so a hidden directory keeps that marker after shortening."
  (cond
    ((zerop (length component)) component)
    ((and (char= (char component 0) #\.) (> (length component) 1))
     (subseq component 0 2))
    (t (subseq component 0 1))))

(defun %path-leader-and-parts (path)
  "Split PATH into its display leader (\"~\", \"/\", or \"\") and the list of
path components between the leader and the final component."
  (let* ((leader (cond
                   ((and (plusp (length path)) (char= (char path 0) #\~)) "~")
                   ((and (plusp (length path)) (char= (char path 0) #\/)) "")
                   (t nil)))
         (rest (if leader (subseq path (length leader)) path)))
    (values leader
            (remove "" (uiop:split-string rest :separator "/") :test #'string=))))

(defun %shorten-path-fish-style (path)
  "Fish-style path shortening: every component except the last is cut to its
first character, leaving the leader (~ or the leading /) and the final
component untouched."
  (multiple-value-bind (leader parts) (%path-leader-and-parts path)
    (if (or (null leader) (<= (length parts) 1))
        path
        (format nil "~a/~{~a~^/~}/~a"
                leader
                (mapcar #'%shorten-path-component (butlast parts))
                (car (last parts))))))

(defun %should-shorten-path-p (path terminal-width)
  (let ((width (%string-visible-width path)))
    (or (> width +path-shorten-threshold-width+)
        (< (- terminal-width width) +path-shorten-reserved-input-width+))))

(defun %home-candidates (home)
  "HOME as configured plus its resolved form, since the working directory
arrives resolved (macOS keeps /tmp as a symlink to /private/tmp)."
  (let ((resolved (ignore-errors
                   (%strip-trailing-slash
                    (namestring (truename (host-kit:ensure-directory-pathname home)))))))
    (remove-duplicates (remove nil (list home resolved)) :test #'string=)))

(defun %matching-home-prefix (cwd)
  "Return the spelling of HOME that prefixes CWD on a path boundary, or NIL."
  (let ((home (host-kit:getenv "HOME")))
    (when (and home (plusp (length home)))
      (find-if (lambda (candidate) (%home-prefix-p candidate cwd))
               (%home-candidates home)))))

(defun %display-cwd (cwd terminal-width)
  "Return CWD with a home-directory prefix shortened to ~, its trailing slash
dropped, and (when narrow) its interior components cut fish-style."
  (let* ((home (%matching-home-prefix cwd))
         (substituted (if home
                          (concatenate 'string "~" (subseq cwd (length home)))
                          cwd))
         (trimmed (%strip-trailing-slash substituted)))
    (if (%should-shorten-path-p trimmed terminal-width)
        (%shorten-path-fish-style trimmed)
        trimmed)))

(defun %truncate-string-to-width (text width)
  "Longest prefix of TEXT whose terminal width is at most WIDTH.
Delegates to cl-tty-kit, which drops a wide glyph whole rather than splitting
it and treats a negative WIDTH as 0."
  (cl-tty-kit:truncate-string text width :ellipsis ""))

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

(defun segment-kind->role (kind)
  "Map prompt segment kind to highlight role for theme lookup. :USER and
:JOBS (the {user} and {jobs} format segments) have no dedicated role yet and
borrow the closest existing one."
  (case kind
    (:host :prompt-host)
    (:user :prompt-host)
    (:path :prompt-path)
    (:exit :prompt-ok)
    (:exit-error :prompt-error)
    (:literal :normal)
    (:git :prompt-git)
    (:git-dirty :prompt-git-dirty)
    (:assistant :prompt-assistant)
    (:duration :prompt-duration)
    (:time :prompt-time)
    (:jobs :prompt-time)
    (t :normal)))

(defparameter *prompt-remote-session-p*
  (lambda ()
    (and (or (host-kit:getenv "SSH_CONNECTION")
             (host-kit:getenv "SSH_CLIENT")
             (host-kit:getenv "SSH_TTY"))
         t))
  "Function of no arguments returning T when the session is remote and the
prompt should show its host segment. A hook, like *GIT-STATUS-RESOLVER*, so
tests can force the answer instead of depending on the process environment.")

(defparameter *prompt-user*
  (lambda ()
    (or (host-kit:getenv "USER") (host-kit:getenv "LOGNAME")))
  "Function of no arguments returning the username shown in a remote-session
host segment, or NIL to omit the `user@' prefix. A hook, like
*PROMPT-REMOTE-SESSION-P*, so tests can force the answer.")

(defun %current-prompt-model (last-exit last-command-duration-ms
                              &optional (terminal-width (terminal-width)))
  ;; Hostname and working directory come from the cl-boundary-kit context so the
  ;; prompt is deterministic under test (see repl-boundaries); the real context
  ;; reads the actual host, preserving interactive behavior. DIRECTORY carries
  ;; the raw filesystem path for the git probe; CWD is the ~-substituted,
  ;; possibly shortened text actually shown, which "git -C" cannot resolve
  ;; (tilde expansion is a shell feature, not something a direct exec gets).
  (let ((directory (boundary-current-directory)))
    (nshell.domain.prompting:make-prompt-model
     :hostname (boundary-hostname)
     :cwd (%display-cwd directory terminal-width)
     :directory directory
     :exit-code last-exit
     :duration-ms last-command-duration-ms
     :remote-session-p (and (funcall *prompt-remote-session-p*) t)
     :user (funcall *prompt-user*))))

(defun %write-colored-segments (stream theme segments)
  (dolist (seg segments)
    (let* ((text (nshell.domain.prompting:prompt-segment-text seg))
           (kind (nshell.domain.prompting:prompt-segment-kind seg))
           (sequence (theme-color->ansi theme (segment-kind->role kind))))
      (if (plusp (length sequence))
          (progn
            (format stream "~a~a" sequence text)
            (nshell.infrastructure.terminal:ansi-reset-style stream))
          (write-string text stream)))))

(defun %colored-segments-string (theme segments)
  (with-output-to-string (stream)
    (%write-colored-segments stream theme segments)))

(defun %emit-right-prompt (theme visible-right-segments padding)
  "Draw VISIBLE-RIGHT-SEGMENTS PADDING columns to the right of the cursor and
restore the cursor, so the left prompt's position is left unchanged. This is the
terminal-effect half of the right prompt; the layout math lives in the caller."
  (nshell.infrastructure.terminal:ansi-save-cursor)
  (nshell.infrastructure.terminal:ansi-cursor-forward padding)
  (format t "~a" (%colored-segments-string theme visible-right-segments))
  (nshell.infrastructure.terminal:ansi-restore-cursor))

(defun %write-right-prompt (theme left-segments right-segments terminal-width)
  (let* ((left-width (%segments-visible-width left-segments))
         (available (- terminal-width left-width 2))
         (visible-right-segments (%truncate-segments right-segments available)))
    (when visible-right-segments
      (let ((padding (- terminal-width left-width
                        (%segments-visible-width visible-right-segments))))
        (when (> padding 0)
          (%emit-right-prompt theme visible-right-segments padding))))))

(defun %assistant-usage-text ()
  "The {ai} format-segment text, or NIL before the assistant's first turn."
  (when (plusp (nshell.feature.assistant:assistant-usage-turns
                nshell.feature.assistant:*assistant-usage*))
    (format nil "AI ~a" (nshell.feature.assistant:assistant-usage-short-text))))

(defun %assistant-usage-segment ()
  (let ((text (%assistant-usage-text)))
    (when text
      (nshell.domain.prompting:make-prompt-segment text :assistant))))

(defun %background-jobs-count ()
  "The {jobs} format-segment count: the shell's currently tracked jobs."
  (length (nshell.application:jobs)))

(defun %right-prompt-segments (pm failure-explain-p)
  (let* ((base (nshell.domain.prompting:render-right-prompt-model
                pm :failure-explain-p failure-explain-p))
         (assistant (%assistant-usage-segment)))
    (if assistant
        (append base
                (when base (list (nshell.domain.prompting:make-prompt-segment " " :literal)))
                (list assistant))
        base)))

(defparameter *prompt-left-format* nil
  "NIL to render the built-in left-prompt layout, or a format string (see
nshell.domain.prompting:render-prompt-format) installed by the PROMPT
builtin, overriding both this and NSHELL_PROMPT.")

(defparameter *prompt-right-format* nil
  "As *PROMPT-LEFT-FORMAT*, for the right prompt and NSHELL_RIGHT_PROMPT.")

(defparameter *prompt-format-environment-reader*
  (lambda (variable) (nshell.infrastructure.acl:current-environment-value variable))
  "Function of one environment-variable NAME returning its value or NIL. A
hook, like *PROMPT-REMOTE-SESSION-P*, so tests can force NSHELL_PROMPT /
NSHELL_RIGHT_PROMPT without depending on the real process environment.")

(defun %prompt-format-from-environment (variable)
  (let ((value (funcall *prompt-format-environment-reader* variable)))
    (and value (plusp (length value)) value)))

(defun %effective-prompt-format (override variable)
  "OVERRIDE (set by the PROMPT builtin) wins; otherwise fall back to the
named environment variable, read once per render since neither changes
mid-session. NIL from both means \"use the built-in layout\"."
  (or override (%prompt-format-from-environment variable)))

(defun %format-segments (format pm failure-explain-p)
  (nshell.domain.prompting:render-prompt-format
   format pm
   :failure-explain-p failure-explain-p
   :jobs-count (%background-jobs-count)
   :assistant-text (%assistant-usage-text)))

(defun apply-prompt-format (side value)
  "Install VALUE (a format string, or NIL to restore the default layout) as
the live session's prompt format for SIDE (:LEFT or :RIGHT)."
  (ecase side
    (:left (setf *prompt-left-format* value))
    (:right (setf *prompt-right-format* value)))
  value)

(defun current-prompt-format ()
  "Return the session's active left and right prompt format text: an
installed override, else the matching environment variable, else the
documented default string."
  (values (or (%effective-prompt-format *prompt-left-format* "NSHELL_PROMPT")
              nshell.domain.prompting:+default-left-prompt-format+)
          (or (%effective-prompt-format *prompt-right-format* "NSHELL_RIGHT_PROMPT")
              nshell.domain.prompting:+default-right-prompt-format+)))

(defun preview-prompt-format (format)
  "Render FORMAT once against the live session state as a left prompt and
return the resulting text, without installing it as the active format."
  (let* ((pm (%current-prompt-model *last-exit-code* *last-command-duration-ms*))
         (theme (nshell.domain.configuration:config-theme *config*)))
    (%colored-segments-string
     theme
     (%format-segments format pm *failure-explain-available-p*))))

(defun render-prompt (config last-exit &key (last-command-duration-ms nil)
                                      (failure-explain-p nil)
                                      (terminal-width (terminal-width))
                                      (window-title-p nil))
  "Render the left prompt with theme colors, and the terminal window title
when WINDOW-TITLE-P. *PROMPT-LEFT-FORMAT*/*PROMPT-RIGHT-FORMAT* (or
NSHELL_PROMPT/NSHELL_RIGHT_PROMPT) replace the built-in layout on whichever
side names a format."
  (let* ((theme (nshell.domain.configuration:config-theme config))
         (pm (%current-prompt-model last-exit last-command-duration-ms terminal-width))
         (left-format (%effective-prompt-format *prompt-left-format* "NSHELL_PROMPT"))
         (right-format (%effective-prompt-format *prompt-right-format* "NSHELL_RIGHT_PROMPT"))
         (segments (if left-format
                       (%format-segments left-format pm failure-explain-p)
                       (nshell.domain.prompting:render-prompt-model pm)))
         (right-segments (if right-format
                             (%format-segments right-format pm failure-explain-p)
                             (%right-prompt-segments pm failure-explain-p))))
    (when window-title-p
      (write-string (cl-tty-kit:ansi-set-window-title
                     (nshell.domain.prompting:prompt-model-cwd pm))))
    (%write-colored-segments *standard-output* theme segments)
    (when right-segments
      (%write-right-prompt theme segments right-segments terminal-width))
    (finish-output)
    (%segments-visible-width segments)))
