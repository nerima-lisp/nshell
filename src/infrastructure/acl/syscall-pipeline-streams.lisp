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
                       (cond
                         (next-pipe
                          (let ((fd (second next-pipe)))
                            (when fd
                              (setf output-pipe-stream
                                    (sb-sys:make-fd-stream fd
                                                           :output t
                                                           :buffering :line))
                              (setf (second next-pipe) nil)
                              output-pipe-stream)))
                         (t default-output))
                       output-materialized-p t))
               output))
      (nshell.domain.parsing:map-redirect-entries
       (lambda (kind target)
         (case kind
           ((:> :>>)
            (multiple-value-bind (stream streams)
                (%open-pipeline-output-redirect kind target redirect-streams)
              (setf output stream
                    output-materialized-p t
                    output-redirected-p t
                    redirect-streams streams)))
           ((:2> :2>>)
            (multiple-value-bind (stream streams)
                (%open-pipeline-output-redirect kind target redirect-streams)
              (setf error-output stream
                    redirect-streams streams)))
           ((:&> :&>>)
            (multiple-value-bind (stream streams)
                (%open-pipeline-output-redirect kind target redirect-streams)
              (setf output stream
                    output-materialized-p t
                    output-redirected-p t
                    error-output :output
                    redirect-streams streams)))
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

(defun %pipeline-stage-streams (stage-redirects prev-pipe next-pipe redirect-streams
                                &key (default-output :stream))
  (let ((input-pipe-stream nil)
        (output-pipe-stream nil))
    (multiple-value-bind (input-kind input-target)
        (nshell.domain.parsing:redirect-input-spec stage-redirects)
      (let ((input (cond
                     ((eq input-kind :<)
                      (let ((stream (open input-target
                                          :direction :input
                                          :if-does-not-exist :error)))
                        (push stream redirect-streams)
                        stream))
                     ((eq input-kind :<<<)
                      (let ((stream (%here-string-stream input-target)))
                        (push stream redirect-streams)
                        stream))
                     ((eq input-kind :<<)
                      (let ((stream (%here-document-stream input-target)))
                        (push stream redirect-streams)
                        stream))
                     (prev-pipe
                      (let ((fd (first prev-pipe)))
                        (when fd
                          (setf input-pipe-stream
                                (sb-sys:make-fd-stream fd
                                                       :input t
                                                       :buffering :line))
                          (setf (first prev-pipe) nil)
                          input-pipe-stream)))
                     (t t))))
        (multiple-value-bind (output error-output resolved-output-pipe-stream redirect-streams)
            (%pipeline-output-streams stage-redirects next-pipe redirect-streams
                                      :default-output default-output)
          (setf output-pipe-stream resolved-output-pipe-stream)
          (values input
                  output
                  error-output
                  input-pipe-stream
                  output-pipe-stream
                  redirect-streams))))))

(defun %close-new-redirect-streams (redirect-streams previous-redirect-streams)
  (loop for streams on redirect-streams
        until (eq streams previous-redirect-streams)
        do (ignore-errors (close (car streams)))))

(defun %close-unused-next-pipe-writer (next-pipe output-pipe-stream)
  (when (and next-pipe (null output-pipe-stream) (integerp (second next-pipe)))
    (ignore-errors (sb-posix:close (second next-pipe)))
    (setf (second next-pipe) nil)))
