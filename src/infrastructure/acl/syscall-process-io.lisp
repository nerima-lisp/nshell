(in-package #:nshell.infrastructure.acl)

(defun %process-result-shell-exit (result)
  "Map a cl-process-kit PROCESS-RESULT to a shell exit status."
  (let ((code (process-kit:process-result-exit-code result))
        (signal (process-kit:process-result-signal result)))
    (cond (code code)
          (signal (+ 128 signal))
          (t 0))))

(defun %copy-process-output (input output)
  (let ((buffer (make-string 4096)))
    (loop for count = (read-sequence buffer input)
          while (plusp count)
          do (write-string buffer output :end count))
    (when (streamp output)
      (ignore-errors
       (finish-output output)))))

(defun %start-stream-copier (input output name)
  (when input
    (sb-thread:make-thread
     (lambda ()
       (ignore-errors
        (%copy-process-output input output)))
     :name name)))

(defun %start-process-output-copier (proc output)
  (%start-stream-copier (and proc (sb-ext:process-output proc))
                        output
                        "nshell process output copier"))

(defun %join-stream-copier (thread)
  (when thread
    (ignore-errors
     (sb-thread:join-thread thread))))

(defun %join-process-output-copiers (copiers)
  (dolist (copier copiers)
    (%join-stream-copier copier)))
