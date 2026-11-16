;;; Crash reports as values (task P0-4, proposal/08 "端末を壊さない・固まらない").
(in-package #:nshell.domain.crash)

(defparameter +crash-repeat-threshold+ 3
  "Consecutive crashes at one place after which the REPL offers a --safe restart.")

(defconstant +unix-epoch-universal-time+ 2208988800)

(defparameter +safe-reexec-carried-flags+
  '("-i" "--interactive" "-l" "--login" "-e" "--errexit"
    "--no-config" "--no-history" "--private")
  "Flags a --safe restart keeps from the original command line. They take no
value and none conflicts with --safe. --config is dropped because it does.")

(defun %nonempty-string-p (value)
  (and (stringp value) (plusp (length value))))

(defun crash-log-directory (xdg-state-home home)
  "Return the crash log directory as a namestring ending in a slash.
XDG-STATE-HOME is used when it is an absolute path; the XDG base directory
specification says to ignore a relative one. Otherwise the directory is under
HOME/.local/state."
  (format nil "~a/nshell/crash/"
          (string-right-trim
           "/"
           (if (and (%nonempty-string-p xdg-state-home)
                    (char= (char xdg-state-home 0) #\/))
               xdg-state-home
               (format nil "~a/.local/state" (string-right-trim "/" home))))))

(defun %decoded-utc (unix-seconds)
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time (+ unix-seconds +unix-epoch-universal-time+) 0)
    (values year month day hour minute second)))

(defun crash-time-string (unix-seconds microseconds)
  "Return UNIX-SECONDS and MICROSECONDS as an ISO 8601 UTC timestamp."
  (multiple-value-bind (year month day hour minute second)
      (%decoded-utc unix-seconds)
    (format nil "~4,'0d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0d.~6,'0dZ"
            year month day hour minute second microseconds)))

(defun crash-log-file-name (unix-seconds microseconds &optional (attempt 0))
  "Return the log file name for a crash at UNIX-SECONDS and MICROSECONDS (UTC).
A nonzero ATTEMPT adds a -ATTEMPT suffix, for when the plain name is taken."
  (multiple-value-bind (year month day hour minute second)
      (%decoded-utc unix-seconds)
    (format nil "~4,'0d~2,'0d~2,'0dT~2,'0d~2,'0d~2,'0d.~6,'0dZ~a.log"
            year month day hour minute second microseconds
            (if (zerop attempt) "" (format nil "-~d" attempt)))))

(defun %path-component-char-p (character)
  (or (alphanumericp character)
      (find character "-_./")))

(defun replace-home-directory (text home)
  "Replace each occurrence of HOME in TEXT with ~ when the next character is
/, the end of TEXT, or a character that cannot continue a file name. What
comes before HOME does not matter, so HOME inside a longer value such as
prefix/home/u/locale is still replaced; /home/user2 is not replaced for HOME
/home/user. HOME loses its trailing slashes first, and a HOME shorter than two
characters (empty or /) changes nothing, since it would rewrite every path."
  (let ((home (and (stringp home) (string-right-trim "/" home))))
    (if (or (not (stringp text))
            (< (length home) 2))
        text
        (with-output-to-string (output)
          (loop with length = (length home)
                with start = 0
                for position = (search home text :start2 start)
                do (if (null position)
                       (progn
                         (write-string text output :start start)
                         (return))
                       (let ((end (+ position length)))
                         (if (or (= end (length text))
                                 (char= (char text end) #\/)
                                 (not (%path-component-char-p (char text end))))
                             (progn
                               (write-string text output :start start :end position)
                               (write-char #\~ output)
                               (setf start end))
                             (progn
                               (write-string text output
                                             :start start :end (1+ position))
                               (setf start (1+ position)))))))))))

(defun %nshell-package-name-p (name)
  (and (not (string= name "NSHELL.USER"))
       (or (string= name "NSHELL")
           (and (> (length name) 7)
                (string= "NSHELL." name :end2 7)))))

(defun nshell-frame-name-p (name)
  "Return true when the backtrace frame NAME belongs to nshell's own code: a
symbol, or a compound name such as (LAMBDA ... :IN F) or (FLET G :IN F), that
mentions a symbol of NSHELL or an NSHELL.* package. NSHELL.USER holds the
user's own definitions and NSHELL/TEST the tests, so neither counts."
  (labels ((walk (node)
             (typecase node
               (null nil)
               (symbol
                (let ((package (symbol-package node)))
                  (and package (%nshell-package-name-p (package-name package)))))
               (cons (or (walk (car node)) (walk (cdr node))))
               (t nil))))
    (walk name)))

(defun %qualified-name-string (object)
  (with-standard-io-syntax
    (let ((*package* (find-package "KEYWORD"))
          (*print-readably* nil)
          (*print-pretty* nil)
          (*print-length* 8)
          (*print-level* 4))
      (prin1-to-string object))))

(defun innermost-nshell-frame (frame-names)
  "Return the printed name of the first nshell frame in FRAME-NAMES, which are
ordered innermost first, or NIL when none belongs to nshell."
  (let ((name (find-if #'nshell-frame-name-p frame-names)))
    (and name (%qualified-name-string name))))

(defun crash-place (condition-type frame-names)
  "Return the place of a crash as a string: CONDITION-TYPE and the innermost
nshell frame of FRAME-NAMES. Two crashes are at the same place when these
strings are equal."
  (format nil "~a in ~a"
          (%qualified-name-string condition-type)
          (or (innermost-nshell-frame frame-names) "no nshell frame")))

(defun crash-streak-advance (streak place)
  "Return the streak after a crash at PLACE. STREAK is NIL or a value this
function returned; a crash at a different place starts a new streak."
  (if (and streak (string= (car streak) place))
      (cons place (1+ (cdr streak)))
      (cons place 1)))

(defun crash-streak-count (streak)
  (if streak (cdr streak) 0))

(defun crash-streak-repeated-p (streak)
  (>= (crash-streak-count streak) +crash-repeat-threshold+))

(defun %redact (text home)
  (nshell.feature.assistant:redact-lines (replace-home-directory text home)))

(defun %write-indented-lines (text output)
  (with-input-from-string (input text)
    (loop for line = (read-line input nil nil)
          while line
          do (format output "  ~a~%" line))))

(defparameter +crash-log-frame-limit+ 40
  "Backtrace frames written to a crash log.")

(defun render-crash-log (&key time condition-type message frame-names
                              frame-arguments home lisp-version)
  "Return the text of a crash log.

FRAME-NAMES are the backtrace frame names, innermost first; the log lists the
first +CRASH-LOG-FRAME-LIMIT+ of them and counts the rest. FRAME-ARGUMENTS
holds printed argument strings for the leading frames, or is shorter or NIL
when arguments were not captured. HOME becomes ~ everywhere. MESSAGE and the
arguments also go
through the assistant redaction: they carry user data such as command text.
Frame names are code, so they are not redacted; the token rule would replace
every long hyphenated function name."
  (with-output-to-string (output)
    (format output "nshell crash log~%")
    (format output "time: ~a~%" time)
    (format output "lisp: ~a~%" lisp-version)
    (format output "condition: ~a~%" (%qualified-name-string condition-type))
    (format output "place: ~a~%"
            (replace-home-directory (crash-place condition-type frame-names) home))
    (format output "message:~%")
    (%write-indented-lines (%redact (or message "") home) output)
    (if (null frame-names)
        (format output "backtrace: unavailable~%")
        (progn
          (format output "backtrace:~%")
          (loop for name in frame-names
                for index from 0 below +crash-log-frame-limit+
                for arguments = (nth index frame-arguments)
                do (format output "  ~d: ~a~@[ ~a~]~%"
                           index
                           (replace-home-directory
                            (%qualified-name-string name) home)
                           (and arguments
                                (substitute #\Space #\Newline
                                            (%redact arguments home)))))
          (when (> (length frame-names) +crash-log-frame-limit+)
            (format output "  ... ~d more frames~%"
                    (- (length frame-names) +crash-log-frame-limit+)))))))

(defun safe-reexec-arguments (arguments)
  "Return the argument list for restarting with --safe: --safe followed by
the flags of ARGUMENTS listed in +SAFE-REEXEC-CARRIED-FLAGS+, each once."
  (cons "--safe"
        (remove-duplicates
         (remove-if-not (lambda (argument)
                          (member argument +safe-reexec-carried-flags+
                                  :test #'equal))
                        arguments)
         :test #'equal :from-end t)))
