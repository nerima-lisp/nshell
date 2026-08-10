(in-package #:nshell.infrastructure.persistence)
(defvar *history-file-path-override* nil
  "When non-nil, overrides the default history file path. Used for testing.")

(defparameter +history-record-prefix+ "# nshell-history-v2 "
  "Prefix for length-framed history records.")
(defparameter +max-history-entry-length+ (* 1024 1024)
  "Maximum number of characters stored in one history entry.")

(defun %default-history-file-path ()
  (merge-pathnames ".nshell_history" (user-homedir-pathname)))

(defun history-file-path ()
  "Return the path used to persist command history."
  (or *history-file-path-override* (%default-history-file-path)))

(defun %history-record-length (header)
  "Return the framed length in HEADER, or NIL when HEADER is not framed."
  (let ((prefix-length (length +history-record-prefix+)))
    (when (and (>= (length header) prefix-length)
               (string= +history-record-prefix+ header
                        :end1 prefix-length :end2 prefix-length))
      (let ((length-text (subseq header prefix-length)))
        (when (and (plusp (length length-text))
                   (every #'digit-char-p length-text))
          (handler-case
              (let ((length (parse-integer length-text :junk-allowed nil)))
                (when (<= length +max-history-entry-length+)
                  length))
            (error () nil)))))))

(defun %read-history-record (stream)
  (let ((header (read-line stream nil :eof)))
    (if (eq header :eof)
        (values nil :eof)
        (let ((length (%history-record-length header)))
          (if length
              (let ((text (make-string length)))
                (if (= length (read-sequence text stream))
                    (let ((separator (read-char stream nil nil)))
                      (if (or (null separator) (char= separator #\Newline))
                          (values text :entry)
                          (values nil :truncated)))
                    (values nil :truncated)))
              (values nil :invalid))))))

(defun %read-history-records (stream)
  (loop with entries = nil
        do (multiple-value-bind (entry status) (%read-history-record stream)
             (case status
               (:eof (return (nreverse entries)))
               (:entry (push entry entries))
               (:invalid (return (nreverse entries)))
               (:truncated (return (nreverse entries)))))))

(defun %append-history-record (stream text)
  (when (> (length text) +max-history-entry-length+)
    (error "History entry exceeds ~d characters."
           +max-history-entry-length+))
  (format stream "~a~d~%~a~%"
          +history-record-prefix+
          (length text)
          text))

(defun load-history-file ()
  (ignore-errors
      (let ((path (history-file-path)))
        (when (probe-file path)
          (with-open-file (f path :direction :input :if-does-not-exist nil)
            (%read-history-records f))))))

(defun append-history-entry (text)
  (ignore-errors
      (progn
        (ensure-directories-exist (history-file-path))
        (with-open-file (f (history-file-path) :direction :output
                           :if-exists :append :if-does-not-exist :create)
          (%append-history-record f text)))))
