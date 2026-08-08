(in-package #:nshell.infrastructure.acl)

(defvar *redirected-stdout* nil)
(defvar *redirected-stdin* nil)
(defvar *redirected-stderr* nil
  "Holds the saved *error-output* while stderr is redirected or aliased.")
(defvar *redirected-stdout-owned* nil)
(defvar *redirected-stderr-owned* nil)
(defvar *redirected-stdin-owned* nil)

(defun %here-string-stream (value)
  (make-string-input-stream (format nil "~a~%" value)))

(defun %here-document-stream (value)
  (make-string-input-stream (or value "")))

(defun %remember-redirected-stdout ()
  (unless *redirected-stdout*
    (setf *redirected-stdout* *standard-output*)))

(defun %remember-redirected-stderr ()
  (unless *redirected-stderr*
    (setf *redirected-stderr* *error-output*)))

(defun %remember-redirected-stdin ()
  (unless *redirected-stdin*
    (setf *redirected-stdin* *standard-input*)))

(defun %close-owned-redirect-stream (stream)
  (when (and stream (streamp stream))
    (ignore-errors (close stream))))

(defun %release-owned-stdout ()
  (let ((stream *redirected-stdout-owned*))
    (when (and stream (not (eq stream *redirected-stderr-owned*)))
      (%close-owned-redirect-stream stream))
    (setf *redirected-stdout-owned* nil)))

(defun %release-owned-stderr ()
  (let ((stream *redirected-stderr-owned*))
    (when (and stream (not (eq stream *redirected-stdout-owned*)))
      (%close-owned-redirect-stream stream))
    (setf *redirected-stderr-owned* nil)))

(defun %release-owned-stdin ()
  (%close-owned-redirect-stream *redirected-stdin-owned*)
  (setf *redirected-stdin-owned* nil))

(defun redirect-output (filename mode)
  "Redirect *STANDARD-OUTPUT* to FILENAME until RESTORE-REDIRECTS runs.
MODE is a CL :IF-EXISTS value -- :SUPERSEDE for shell `>`, :APPEND for `>>`."
  (let ((stream (open filename
                      :direction :output
                      :if-exists mode
                      :if-does-not-exist :create)))
    (setf *redirected-stdout-owned* stream
          *standard-output* stream)))

(defun redirect-error (filename mode)
  "Redirect *ERROR-OUTPUT* to FILENAME until RESTORE-REDIRECTS runs.
MODE is a CL :IF-EXISTS value -- :SUPERSEDE for shell `2>`, :APPEND for `2>>`."
  (let ((stream (open filename
                      :direction :output
                      :if-exists mode
                      :if-does-not-exist :create)))
    (setf *redirected-stderr-owned* stream
          *error-output* stream)))

(defun redirect-output-and-error (filename mode)
  "Redirect both *STANDARD-OUTPUT* and *ERROR-OUTPUT* to the same open stream
on FILENAME, for shell `&>`/`&>>`. MODE is a CL :IF-EXISTS value."
  (let ((stream (open filename
                      :direction :output
                      :if-exists mode
                      :if-does-not-exist :create)))
    (setf *redirected-stdout-owned* stream
          *redirected-stderr-owned* stream
          *standard-output* stream
          *error-output* stream)))

(defun redirect-output-to-error ()
  (%remember-redirected-stdout)
  ;; Keep stderr explicit so standalone processes do not merge it into stdout.
  (%remember-redirected-stderr)
  (%release-owned-stdout)
  (setf *standard-output* *error-output*))

(defun redirect-error-to-output ()
  "Alias *ERROR-OUTPUT* to the current *STANDARD-OUTPUT*, for shell `2>&1`.
Unlike the file-based redirects above, this opens no stream of its own --
RESTORE-REDIRECTS's EQ check against the current *STANDARD-OUTPUT* is what
keeps it from double-closing a stream this function never owned."
  (setf *redirected-stderr* *error-output*
        *error-output* *standard-output*))

(defun redirect-input (filename)
  "Redirect *STANDARD-INPUT* to read from FILENAME until RESTORE-REDIRECTS
runs, for shell `<`. Signals if FILENAME does not exist."
  (let ((stream (open filename :direction :input :if-does-not-exist :error)))
    (setf *redirected-stdin-owned* stream
          *standard-input* stream)))

(defun redirect-input-string (value)
  "Redirect *STANDARD-INPUT* to VALUE plus a trailing newline, for a shell
here-string (`<<<`). Compare REDIRECT-INPUT-DOCUMENT, which uses VALUE as-is."
  (setf *redirected-stdin* *standard-input*
        *standard-input* (%here-string-stream value)))

(defun redirect-input-document (value)
  "Redirect *STANDARD-INPUT* to VALUE (or \"\" if NIL) verbatim, for a shell
here-document (`<<`/`<<-`) whose body the parser has already assembled.
Compare REDIRECT-INPUT-STRING, which appends a trailing newline."
  (setf *redirected-stdin* *standard-input*
        *standard-input* (%here-document-stream value)))

(defun restore-redirects ()
  "Undo every active redirect-* above, closing each stream this session
opened and restoring the *STANDARD-OUTPUT*/*ERROR-OUTPUT*/*STANDARD-INPUT*
they replaced. Only closes a stream when the matching *REDIRECTED-*
special is non-NIL, so a stream never touched by a redirect-* call (the
common case for at least one of the three) is left alone. The stderr
branch additionally skips closing when stderr is EQ to the current stdout
-- the state REDIRECT-ERROR-TO-OUTPUT or REDIRECT-OUTPUT-AND-ERROR leaves
behind -- so a stream already closed via the stdout branch (or never
independently opened at all) is not closed a second time."
  (let ((current-stdout *standard-output*)
        (current-stderr *error-output*)
        (current-stdin *standard-input*))
    (when *redirected-stdout*
      (setf *standard-output* *redirected-stdout*))
    (when *redirected-stderr*
      (setf *error-output* *redirected-stderr*))
    (when *redirected-stdin*
      (setf *standard-input* *redirected-stdin*))
    (dolist (stream
             (remove-duplicates
              (remove nil
                      (list *redirected-stdout-owned*
                            *redirected-stderr-owned*
                            *redirected-stdin-owned*))
              :test #'eq))
      (%close-owned-redirect-stream stream))
    (setf *redirected-stdout* nil
          *redirected-stderr* nil
          *redirected-stdin* nil
          *redirected-stdout-owned* nil
          *redirected-stderr-owned* nil
          *redirected-stdin-owned* nil)))
