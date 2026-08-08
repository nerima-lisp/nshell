(in-package #:nshell.infrastructure.acl)

(defun %pipeline-output-mode (kind)
  (if (nshell.domain.parsing:redirect-append-kind-p kind)
      :append
      :supersede))

(defun %open-pipeline-output-redirect (kind target redirect-streams)
  (let ((stream (open target
                      :direction :output
                      :if-exists (%pipeline-output-mode kind)
                      :if-does-not-exist :create)))
    (values stream (cons stream redirect-streams))))

(defun %take-pipeline-output-pipe-stream (next-pipe)
  (when next-pipe
    (let ((fd (second next-pipe)))
      (when fd
        (prog1
            (sb-sys:make-fd-stream fd
                                   :output t
                                   :buffering :line)
          (setf (second next-pipe) nil))))))

(defun %pipeline-output-streams (stage-redirects next-pipe redirect-streams
                                 &key default-output)
  (let ((output nil)
        (output-materialized-p nil)
        (output-pipe-stream nil)
        (output-redirected-p nil)
        (error-output t))
    (labels ((current-output ()
               (unless output-materialized-p
                 (setf output
                       (if next-pipe
                           (setf output-pipe-stream
                                 (%take-pipeline-output-pipe-stream next-pipe))
                           default-output)
                       output-materialized-p t))
               output)
             (redirect-output (kind target)
               (multiple-value-bind (stream streams)
                   (%open-pipeline-output-redirect kind target redirect-streams)
                 (setf output stream
                       output-materialized-p t
                       output-redirected-p t
                       redirect-streams streams)))
             (redirect-error (kind target)
               (multiple-value-bind (stream streams)
                   (%open-pipeline-output-redirect kind target redirect-streams)
                 (setf error-output stream
                       redirect-streams streams)))
             (redirect-output-and-error (kind target)
               (redirect-output kind target)
               (setf error-output :output)))
      (nshell.domain.parsing:map-redirect-entries
       (lambda (kind target)
         (case kind
           ((:> :>>) (redirect-output kind target))
           ((:2> :2>>) (redirect-error kind target))
           ((:&> :&>>) (redirect-output-and-error kind target))
           (:2>&1
            (setf error-output
                  (if output-redirected-p
                      :output
                      (current-output))))))
       stage-redirects)
      (values (current-output)
              error-output
              output-pipe-stream
              redirect-streams))))

(defun %take-pipeline-input-pipe-stream (prev-pipe)
  (when prev-pipe
    (let ((fd (first prev-pipe)))
      (when fd
        (prog1
            (sb-sys:make-fd-stream fd
                                   :input t
                                   :buffering :line)
          (setf (first prev-pipe) nil))))))

(defun %open-pipeline-input-redirect (kind target redirect-streams)
  (let ((stream
          (case kind
            (:< (open target
                      :direction :input
                      :if-does-not-exist :error))
            (:<<< (%here-string-stream target))
            (:<< (%here-document-stream target)))))
    (values stream (cons stream redirect-streams))))

(defun %pipeline-stage-streams (stage-redirects prev-pipe next-pipe redirect-streams
                                &key (default-output :stream))
  (multiple-value-bind (input-kind input-target)
      (nshell.domain.parsing:redirect-input-spec stage-redirects)
    (multiple-value-bind (input input-pipe-stream redirect-streams)
        (case input-kind
          ((:< :<<< :<<)
           (multiple-value-bind (stream streams)
               (%open-pipeline-input-redirect input-kind input-target redirect-streams)
             (values stream nil streams)))
          (otherwise
           (if prev-pipe
               (let ((stream (%take-pipeline-input-pipe-stream prev-pipe)))
                 (values stream stream redirect-streams))
               (values t nil redirect-streams))))
      (multiple-value-bind (output error-output output-pipe-stream redirect-streams)
          (%pipeline-output-streams stage-redirects next-pipe redirect-streams
                                    :default-output default-output)
        (values input
                output
                error-output
                input-pipe-stream
                output-pipe-stream
                redirect-streams)))))

(defun %close-new-redirect-streams (redirect-streams previous-redirect-streams)
  (loop for streams on redirect-streams
        until (eq streams previous-redirect-streams)
        do (ignore-errors (close (car streams)))))

(defun %close-unused-next-pipe-writer (next-pipe output-pipe-stream)
  (when (and next-pipe (null output-pipe-stream) (integerp (second next-pipe)))
    (ignore-errors (sb-posix:close (second next-pipe)))
    (setf (second next-pipe) nil)))
