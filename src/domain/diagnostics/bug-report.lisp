;;; The `nshell bug-report` issue draft (task P0-6, design decision D-54,
;;; proposal/08 "bug-report だけで再現に必要な情報が揃う").
;;;
;;; The draft goes to a public issue tracker, so what it may contain is decided
;;; here by allow-lists: an environment variable shows its value only when its
;;; name is TERM, COLORTERM, LANG, or LC_*; set NSHELL_* variables show only
;;; their names; configuration files show only presence, size, and SHA-256.
;;; Directories are named by how nshell finds them, never by their real path.
(in-package #:nshell.domain.bug-report)

(defparameter +printable-environment-names+ '("TERM" "COLORTERM" "LANG")
  "Variables whose value the draft may show, besides the LC_* family.")

(defun %uppercase-name-char-p (character)
  (or (char<= #\A character #\Z)
      (char<= #\0 character #\9)
      (char= character #\_)))

(defun %prefixed-name-p (prefix name)
  "Return true when NAME is PREFIX followed by at least one character of
[A-Z0-9_]."
  (and (stringp name)
       (> (length name) (length prefix))
       (string= prefix name :end2 (length prefix))
       (every #'%uppercase-name-char-p (subseq name (length prefix)))))

(defun environment-value-printable-p (name)
  "Return true when the draft may show the value of the environment variable
NAME: exactly TERM, COLORTERM, or LANG, or LC_ followed by [A-Z0-9_]+. The
comparison is case-sensitive, so lc_all, TERMX, and LANGUAGE are refused."
  (and (stringp name)
       (or (member name +printable-environment-names+ :test #'string=)
           (%prefixed-name-p "LC_" name))
       t))

(defun nshell-variable-name-p (name)
  "Return true when NAME is NSHELL_ followed by [A-Z0-9_]+. Only such names are
listed; a name with other characters is left out rather than printed."
  (%prefixed-name-p "NSHELL_" name))

(defun parse-environment-entries (entries)
  "Return ENTRIES, a list of \"NAME=VALUE\" strings, as an alist of (NAME .
VALUE). The name ends at the first =; an entry without = is dropped. When a
name occurs twice, the first entry wins, as getenv(3) does."
  (let ((result '()))
    (dolist (entry entries (nreverse result))
      (let ((separator (and (stringp entry) (position #\= entry))))
        (when (and separator (plusp separator))
          (let ((name (subseq entry 0 separator)))
            (unless (assoc name result :test #'string=)
              (push (cons name (subseq entry (1+ separator))) result))))))))

(defun %absolute-path-p (value)
  (and (stringp value) (plusp (length value)) (char= (char value 0) #\/)))

(defun config-directory (xdg-config-home home)
  "Return the nshell configuration directory, ending in a slash: under
XDG-CONFIG-HOME when it is absolute, otherwise HOME/.config. This is the rule
the startup file and the functions directory use."
  (format nil "~a/nshell/"
          (string-right-trim
           "/"
           (if (%absolute-path-p xdg-config-home)
               xdg-config-home
               (format nil "~a/.config" (string-right-trim "/" home))))))

(defun config-directory-label (xdg-config-home)
  "Return how the draft names the configuration directory: by the variable
that selects it, never by its value, which may name the user."
  (if (%absolute-path-p xdg-config-home)
      "$XDG_CONFIG_HOME/nshell/"
      "~/.config/nshell/"))

(defun crash-log-directory-label (xdg-state-home)
  "Return how the draft names the crash log directory; see
NSHELL.DOMAIN.CRASH:CRASH-LOG-DIRECTORY for the rule it follows."
  (if (%absolute-path-p xdg-state-home)
      "$XDG_STATE_HOME/nshell/crash/"
      "~/.local/state/nshell/crash/"))

(defun crash-log-file-name-p (name)
  "Return true when NAME has the shape NSHELL.DOMAIN.CRASH:CRASH-LOG-FILE-NAME
produces: YYYYMMDDTHHMMSS.UUUUUUZ.log with an optional -N before .log. Other
files in the directory are not ours, and their names are not printed."
  (let ((length (and (stringp name) (length name))))
    (flet ((digits-p (start end)
             (and (<= end length)
                  (every #'digit-char-p (subseq name start end)))))
      (and length
           (>= length 27)
           (digits-p 0 8)
           (char= (char name 8) #\T)
           (digits-p 9 15)
           (char= (char name 15) #\.)
           (digits-p 16 22)
           (char= (char name 22) #\Z)
           (string= ".log" name :start2 (- length 4))
           (or (= length 27)
               (and (char= (char name 23) #\-)
                    (> length 28)
                    (digits-p 24 (- length 4))))))))

(defun %crash-log-attempt (name)
  (if (char= (char name 23) #\-)
      (parse-integer name :start 24 :end (- (length name) 4))
      0))

(defun %crash-log-newer-p (left right)
  "Order crash log names newest first: by the timestamp, then by the -N suffix
the writer adds when the plain name was taken."
  (let ((left-time (subseq left 0 23))
        (right-time (subseq right 0 23)))
    (if (string= left-time right-time)
        (> (%crash-log-attempt left) (%crash-log-attempt right))
        (string> left-time right-time))))

(defun make-config-file-fact (state &key size sha256)
  "Return what the draft says about one configuration file. STATE is :ABSENT,
:PRESENT (SIZE and SHA256 given), :UNREADABLE (SIZE given when known), or
:NOT-REGULAR for a directory, FIFO, or other non-file at the path."
  (list state size sha256))

(defun %config-file-fact-text (fact)
  (destructuring-bind (state size sha256) fact
    (ecase state
      (:absent "absent")
      (:present (format nil "~d bytes, sha256 ~a" size sha256))
      (:unreadable (if size
                       (format nil "~d bytes, unreadable" size)
                       "unreadable"))
      (:not-regular "not a regular file"))))

(defun %one-line (text)
  "Return TEXT with each control character replaced by a space, so a value
cannot add lines to the draft or send terminal escapes."
  (map 'string
       (lambda (character)
         (if (or (< (char-code character) 32) (= (char-code character) 127))
             #\Space
             character))
       text))

(defun %printable-value (value home)
  "Return VALUE as the draft shows it: on one line, HOME shown as ~, and
token-shaped text redacted. TERM and LANG values hold neither, but a user can
put anything in LC_*."
  (string-right-trim
   '(#\Newline)
   (nshell.feature.assistant:redact-lines
    (nshell.domain.crash:replace-home-directory (%one-line value) home))))

(defun %write-file-group (output label facts)
  (format output "- ~a: ~d file~:p~%" label (length facts))
  (loop for fact in facts
        for index from 1
        do (format output "  - ~a #~d: ~a~%"
                   label index (%config-file-fact-text fact))))

(defun render-bug-report (&key version lisp-version os architecture
                               terminal-width environment home
                               config-label init-file conf-files function-files
                               crash-label crash-log-names dependencies)
  "Return the issue draft text.

ENVIRONMENT is an alist of (NAME . VALUE). Only values whose name passes
ENVIRONMENT-VALUE-PRINTABLE-P are written, and only names that pass
NSHELL-VARIABLE-NAME-P are listed; everything else in ENVIRONMENT is ignored.
HOME is shown as ~ in those values. INIT-FILE, CONF-FILES, and FUNCTION-FILES
are facts from MAKE-CONFIG-FILE-FACT, in load order; conf.d and functions
files are numbered instead of named, because a file name is user content.
CRASH-LOG-NAMES are file names in the crash log directory; only names that
pass CRASH-LOG-FILE-NAME-P are counted, and the newest is named.
DEPENDENCIES is a list of (NAME . VERSION). TERMINAL-WIDTH is NIL when no
terminal answered."
  (let ((locale-entries (sort (remove-if-not (lambda (name)
                                               (%prefixed-name-p "LC_" name))
                                             (copy-list environment)
                                             :key #'car)
                              #'string< :key #'car))
        (nshell-names (sort (remove-if-not #'nshell-variable-name-p
                                           (mapcar #'car environment))
                            #'string<))
        (crash-logs (sort (remove-if-not #'crash-log-file-name-p
                                         (copy-list crash-log-names))
                          #'%crash-log-newer-p)))
    (with-output-to-string (output)
      (format output "## nshell bug report~%~%")
      (format output "<!-- nshell bug-report printed this draft and sent nothing.~%")
      (format output "     Fill in the sections below, check the rest, and paste it~%")
      (format output "     into a new issue. -->~%~%")
      (format output "### What happened~%~%")
      (format output "<!-- What you did, what you expected, and what happened instead. -->~%~%")
      (format output "### Steps to reproduce~%~%1.~%~%")
      (format output "### Environment~%~%")
      (format output "- nshell: ~a~%" version)
      (format output "- Lisp: ~a~%" lisp-version)
      (format output "- OS: ~a~%" os)
      (format output "- Architecture: ~a~%" architecture)
      (format output "- Terminal width: ~:[unknown~;~:*~d~]~%" terminal-width)
      (dolist (name +printable-environment-names+)
        (let ((entry (assoc name environment :test #'string=)))
          (format output "- ~a: ~:[(unset)~;~:*~a~]~%"
                  name (and entry (%printable-value (cdr entry) home)))))
      (dolist (entry locale-entries)
        (when (environment-value-printable-p (car entry))
          (format output "- ~a: ~a~%"
                  (car entry) (%printable-value (cdr entry) home))))
      (format output "- NSHELL_* variables set (names only): ~:[none~;~:*~{~a~^, ~}~]~%"
              nshell-names)
      (format output "~%### Configuration~%~%")
      (format output "Directory: ~a (presence, size, and sha256 only)~%~%" config-label)
      (format output "- init.lisp: ~a~%" (%config-file-fact-text init-file))
      (%write-file-group output "conf.d" conf-files)
      (%write-file-group output "functions" function-files)
      (format output "~%### Crash logs~%~%")
      (format output "Directory: ~a~%~%" crash-label)
      (format output "- Logs: ~d~%" (length crash-logs))
      (when crash-logs
        (format output "- Most recent: ~a~%" (first crash-logs)))
      (format output "~%### Dependencies~%~%")
      (dolist (dependency dependencies)
        (format output "- ~a: ~a~%" (car dependency) (or (cdr dependency) "unknown"))))))
