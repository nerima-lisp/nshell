(in-package #:nshell.presentation)

(progn
  (defvar *nfr05-diagnostic-path* nil)
  (defvar *nfr05-diagnostic-active-p* nil)
  (defvar *nfr05-diagnostic-started-at* nil)
  (defvar *nfr05-diagnostic-gc-count* (cons 0 nil))
  (defvar *nfr05-diagnostic-gc-count-start* 0)
  (defvar *nfr05-diagnostic-gc-time-start* 0)
  (defvar *nfr05-diagnostic-stage-ticks* nil)
  (defvar *nfr05-diagnostic-output-event* nil)

  (eval-when (:compile-toplevel :load-toplevel :execute)
    (defun %nfr05-diagnostic-thunk-body (form)
      (unless (and (consp form)
                   (eq (first form) 'lambda)
                   (null (second form)))
        (error "NFR-05 diagnostic macro expected a zero-argument lambda"))
      (cddr form)))

  (defmacro %nfr05-diagnostic-measure (stage thunk-form)
    (let ((body (%nfr05-diagnostic-thunk-body thunk-form)))
      `(if *nfr05-diagnostic-active-p*
           (let ((started-at (get-internal-real-time)))
             (unwind-protect
                  (progn ,@body)
               (incf (gethash ,stage *nfr05-diagnostic-stage-ticks* 0)
                     (- (get-internal-real-time) started-at))))
           (progn ,@body))))

  (defmacro %nfr05-with-timed-terminal-output (thunk-form)
    (let ((body (%nfr05-diagnostic-thunk-body thunk-form)))
      `(if (not *nfr05-diagnostic-active-p*)
           (progn ,@body)
           (let ((stream (make-instance '%nfr05-timing-output-stream
                                        :target *standard-output*)))
             (unwind-protect
                  (let ((*standard-output* stream))
                    (progn ,@body))
               (%nfr05-diagnostic-finish))))))

  (defmacro %nfr05-diagnostic-begin ()
    `(when *nfr05-diagnostic-path*
       (setf *nfr05-diagnostic-active-p* t
             *nfr05-diagnostic-started-at* (get-internal-real-time)
             *nfr05-diagnostic-gc-count-start*
             (sb-ext:atomic-incf (car *nfr05-diagnostic-gc-count*) 0)
             *nfr05-diagnostic-gc-time-start* sb-ext:*gc-run-time*
             *nfr05-diagnostic-stage-ticks* (make-hash-table :test #'eq)
             *nfr05-diagnostic-output-event* nil)))

  (defmacro %nfr05-diagnostic-set-output-event (event)
    `(when *nfr05-diagnostic-active-p*
       (setf *nfr05-diagnostic-output-event* ,event)))

  (defclass %nfr05-timing-output-stream
      (sb-gray:fundamental-character-output-stream)
    ((target :initarg :target :reader %nfr05-timing-output-target)))

  (defmethod sb-gray:stream-line-column
      ((stream %nfr05-timing-output-stream))
    (sb-gray:stream-line-column (%nfr05-timing-output-target stream)))

  (defmethod sb-gray:stream-write-char
      ((stream %nfr05-timing-output-stream) character)
    (%nfr05-diagnostic-measure
     :terminal-write
     (lambda ()
       (write-char character (%nfr05-timing-output-target stream)))))

  (defmethod sb-gray:stream-write-string
      ((stream %nfr05-timing-output-stream) string &optional (start 0) end)
    (%nfr05-diagnostic-measure
     :terminal-write
     (lambda ()
       (write-string string (%nfr05-timing-output-target stream)
                     :start start :end end))))

  (defmethod sb-gray:stream-force-output
      ((stream %nfr05-timing-output-stream))
    (%nfr05-diagnostic-measure
     :terminal-flush
     (lambda ()
       (force-output (%nfr05-timing-output-target stream)))))

  (defmethod sb-gray:stream-finish-output
      ((stream %nfr05-timing-output-stream))
    (%nfr05-diagnostic-measure
     :terminal-flush
     (lambda ()
       (finish-output (%nfr05-timing-output-target stream)))))

  (defun %nfr05-after-gc ()
    (sb-ext:atomic-incf (car *nfr05-diagnostic-gc-count*)))

  (defun %nfr05-enable-diagnostics ()
    (setf *nfr05-diagnostic-path*
          (host-kit:getenv "NSHELL_NFR05_DIAGNOSTIC_SIDECAR")
          *nfr05-diagnostic-active-p* nil)
    (when *nfr05-diagnostic-path*
      (setf sb-ext:*after-gc-hooks*
            (adjoin #'%nfr05-after-gc sb-ext:*after-gc-hooks* :test #'eq)))
    *nfr05-diagnostic-path*)

  (defun %nfr05-ticks-to-ns (ticks)
    (round (* ticks 1000000000) internal-time-units-per-second))

  (defun %nfr05-diagnostic-stage-ns (stage)
    (%nfr05-ticks-to-ns
     (gethash stage *nfr05-diagnostic-stage-ticks* 0)))

  (defun %nfr05-event-name ()
    (if (symbolp *nfr05-diagnostic-output-event*)
        (string-downcase (symbol-name *nfr05-diagnostic-output-event*))
        "unknown"))

  (defun %nfr05-diagnostic-finish ()
    (when (and *nfr05-diagnostic-active-p* *nfr05-diagnostic-path*)
      (let ((render-wall-ns
              (%nfr05-ticks-to-ns
               (- (get-internal-real-time) *nfr05-diagnostic-started-at*))))
        (with-open-file (stream *nfr05-diagnostic-path*
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (format stream
                  "{\"schema_version\":1,\"record\":\"nfr05-render-diagnostic\",\"output_event\":~s,\"render_wall_ns\":~d,\"gc_count\":~d,\"gc_time_ns\":~d,\"gc_time_source\":\"sb-ext:*gc-run-time* process CPU time\",\"suggestion_ns\":~d,\"grapheme_geometry_ns\":~d,\"display_width_ns\":~d,\"terminal_write_ns\":~d,\"terminal_flush_ns\":~d,\"lock_wait_ns\":null,\"lock_wait_source\":\"not measured in process; see paired native capture\",\"command_execution_requested\":false}~%"
                  (%nfr05-event-name)
                  render-wall-ns
                  (- (sb-ext:atomic-incf (car *nfr05-diagnostic-gc-count*) 0)
                     *nfr05-diagnostic-gc-count-start*)
                  (%nfr05-ticks-to-ns
                   (- sb-ext:*gc-run-time* *nfr05-diagnostic-gc-time-start*))
                  (%nfr05-diagnostic-stage-ns :suggestion)
                  (%nfr05-diagnostic-stage-ns :grapheme-geometry)
                  (%nfr05-diagnostic-stage-ns :display-width)
                  (%nfr05-diagnostic-stage-ns :terminal-write)
                  (%nfr05-diagnostic-stage-ns :terminal-flush)))
        (setf *nfr05-diagnostic-active-p* nil
              *nfr05-diagnostic-started-at* nil
              *nfr05-diagnostic-stage-ticks* nil
              *nfr05-diagnostic-output-event* nil))))
)
