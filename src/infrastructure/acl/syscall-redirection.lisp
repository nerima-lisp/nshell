(in-package #:nshell.infrastructure.acl)

(defvar *redirected-stdout* nil)
(defvar *redirected-stdin* nil)
(defvar *redirected-stderr* nil
  "Holds the saved *error-output* while stderr is redirected to a file; NIL when
stderr is not redirected (the default merge-into-stdout behavior is then kept).")

(defun %here-string-stream (value)
  (make-string-input-stream (format nil "~a~%" value)))

(defun %here-document-stream (value)
  (make-string-input-stream (or value "")))

(defun redirect-output (filename mode)
  (let ((stream (open filename
                      :direction :output
                      :if-exists mode
                      :if-does-not-exist :create)))
    (setf *redirected-stdout* *standard-output*
          *standard-output* stream)))

(defun redirect-error (filename mode)
  (let ((stream (open filename
                      :direction :output
                      :if-exists mode
                      :if-does-not-exist :create)))
    (setf *redirected-stderr* *error-output*
          *error-output* stream)))

(defun redirect-output-and-error (filename mode)
  (let ((stream (open filename
                      :direction :output
                      :if-exists mode
                      :if-does-not-exist :create)))
    (setf *redirected-stdout* *standard-output*
          *redirected-stderr* *error-output*
          *standard-output* stream
          *error-output* stream)))

(defun redirect-error-to-output ()
  (setf *redirected-stderr* *error-output*
        *error-output* *standard-output*))

(defun redirect-input (filename)
  (let ((stream (open filename :direction :input :if-does-not-exist :error)))
    (setf *redirected-stdin* *standard-input*
          *standard-input* stream)))

(defun redirect-input-string (value)
  (setf *redirected-stdin* *standard-input*
        *standard-input* (%here-string-stream value)))

(defun redirect-input-document (value)
  (setf *redirected-stdin* *standard-input*
        *standard-input* (%here-document-stream value)))

(defun restore-redirects ()
  (let ((current-stdout *standard-output*)
        (current-stderr *error-output*)
        (current-stdin *standard-input*))
    (when *redirected-stdout*
      (close current-stdout)
      (setf *standard-output* *redirected-stdout*
            *redirected-stdout* nil))
    (when *redirected-stderr*
      (unless (eq current-stderr current-stdout)
        (close current-stderr))
      (setf *error-output* *redirected-stderr*
            *redirected-stderr* nil))
    (when *redirected-stdin*
      (close current-stdin)
      (setf *standard-input* *redirected-stdin*
            *redirected-stdin* nil))))
