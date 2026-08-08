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
  (%remember-redirected-stdout)
  (%release-owned-stdout)
  (let ((stream (open filename
                      :direction :output
                      :if-exists mode
                      :if-does-not-exist :create)))
    (setf *redirected-stdout-owned* stream
          *standard-output* stream)))

(defun redirect-error (filename mode)
  (%remember-redirected-stderr)
  (%release-owned-stderr)
  (let ((stream (open filename
                      :direction :output
                      :if-exists mode
                      :if-does-not-exist :create)))
    (setf *redirected-stderr-owned* stream
          *error-output* stream)))

(defun redirect-output-and-error (filename mode)
  (%remember-redirected-stdout)
  (%remember-redirected-stderr)
  (%release-owned-stdout)
  (%release-owned-stderr)
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
  (%remember-redirected-stderr)
  (%release-owned-stderr)
  (setf *error-output* *standard-output*))

(defun redirect-input (filename)
  (%remember-redirected-stdin)
  (%release-owned-stdin)
  (let ((stream (open filename :direction :input :if-does-not-exist :error)))
    (setf *redirected-stdin-owned* stream
          *standard-input* stream)))

(defun redirect-input-string (value)
  (%remember-redirected-stdin)
  (%release-owned-stdin)
  (let ((stream (%here-string-stream value)))
    (setf *redirected-stdin-owned* stream
          *standard-input* stream)))

(defun redirect-input-document (value)
  (%remember-redirected-stdin)
  (%release-owned-stdin)
  (let ((stream (%here-document-stream value)))
    (setf *redirected-stdin-owned* stream
          *standard-input* stream)))

(defun restore-redirects ()
  (let ((owned-streams
          (remove-duplicates
           (remove nil
                   (list *redirected-stdout-owned*
                         *redirected-stderr-owned*
                         *redirected-stdin-owned*))
           :test #'eq)))
    (when *redirected-stdout*
      (setf *standard-output* *redirected-stdout*))
    (when *redirected-stderr*
      (setf *error-output* *redirected-stderr*))
    (when *redirected-stdin*
      (setf *standard-input* *redirected-stdin*))
    (dolist (stream owned-streams)
      (%close-owned-redirect-stream stream))
    (setf *redirected-stdout* nil
          *redirected-stderr* nil
          *redirected-stdin* nil
          *redirected-stdout-owned* nil
          *redirected-stderr-owned* nil
          *redirected-stdin-owned* nil)))
