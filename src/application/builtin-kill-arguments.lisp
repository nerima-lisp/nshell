(in-package #:nshell.application)

(defun %parse-signal-designator (text)
  (or (%parse-integer-designator text)
      (when (stringp text)
        (let* ((raw (string-upcase text))
               (name (if (and (>= (length raw) 3)
                              (string= "SIG" (subseq raw 0 3)))
                         (subseq raw 3) raw)))
          (cdr (assoc name +job-signal-specs+ :test #'string=))))))

(defmacro %kill-parse-error (message-form)
  `(return-from %parse-kill-arguments
     (values nil nil nil ,message-form)))

(defun %parse-kill-arguments (args)
  (let ((remaining (copy-list args)) (signal-designator :sigterm)
        (targets nil) (options-p t) (list-signals-p nil))
    (loop while remaining do
      (let ((arg (pop remaining)))
        (cond
          ((and options-p (string= arg "--")) (setf options-p nil))
          ((and options-p (string= arg "-l")) (setf list-signals-p t))
          ((and options-p (or (string= arg "-s") (string= arg "--signal")))
           (if (null remaining)
               (%kill-parse-error "kill: option requires an argument -- signal~%")
               (let ((parsed (%parse-signal-designator (pop remaining))))
                 (if parsed (setf signal-designator parsed)
                     (%kill-parse-error "kill: invalid signal~%")))))
          ((and options-p (string-prefix-p "--signal=" arg))
           (let ((parsed (%parse-signal-designator
                          (subseq arg (length "--signal=")))))
             (if parsed (setf signal-designator parsed)
                 (%kill-parse-error "kill: invalid signal~%"))))
          ((and options-p (string= arg "-")) (push arg targets))
          ((and options-p (plusp (length arg)) (char= (char arg 0) #\-))
           (if (integerp (%parse-integer-designator arg))
               (push arg targets)
               (let ((parsed (%parse-signal-designator (subseq arg 1))))
                 (if parsed (setf signal-designator parsed)
                     (%kill-parse-error
                      (format nil "kill: unknown option: ~a~%" arg))))))
          (t (push arg targets)))))
    (values signal-designator (nreverse targets) list-signals-p nil)))
