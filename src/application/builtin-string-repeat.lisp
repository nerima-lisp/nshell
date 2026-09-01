(in-package #:nshell.application)

(defun %string-repeat-effective-count (text count max-length)
  (or count (and max-length (max 1 (ceiling max-length (max 1 (length text))))) 1))

(defun %string-repeat-text (text count &optional max-length)
  (when (plusp count)
    (if max-length
        (let ((remaining max-length)
              (text-length (length text)))
          (with-output-to-string (out)
            (loop repeat count
                  while (and (plusp remaining) (plusp text-length))
                  for written = (min remaining text-length)
                  do (write-string text out :end written)
                     (decf remaining written))))
        (with-output-to-string (out)
          (loop repeat count
                do (write-string text out))))))

(defun %parse-string-repeat-options (remaining)
  (let ((repeat-count nil)
        (max-length nil)
        (quiet-p nil)
        (no-newline-p nil))
    (with-string-options
      (next-remaining error remaining "string"
                      +string-repeat-flag-option-specs+
                      +string-repeat-integer-option-specs+
                      (%string-flag-option-handler
                        (name remaining)
                        (quiet (setf quiet-p t))
                        (no-newline (setf no-newline-p t)))
                      (%string-integer-option-handler
                        (name parsed next-remaining)
                        (count (setf repeat-count parsed))
                        (max (setf max-length parsed))))
      (values repeat-count max-length quiet-p no-newline-p
              next-remaining error))))

(defun %string-repeat-bare-count-usage-p (repeat-count max-length remaining)
  (and (null repeat-count)
       (null max-length)
       (rest remaining)
       (multiple-value-bind (parsed error)
           (%string-parse-integer-option "count" (first remaining))
         (declare (ignore error))
         parsed)))

(defun %string-repeat-output
    (remaining repeat-count max-length quiet-p no-newline-p)
  (with-output-to-string (out)
    (loop for texts on remaining
          for text = (first texts)
          for effective-count = (%string-repeat-effective-count
                                 text repeat-count max-length)
          for repeated = (%string-repeat-text text effective-count max-length)
          do (when repeated
               (unless quiet-p (write-string repeated out))
               (unless (or quiet-p (and no-newline-p (null (rest texts))))
                 (write-char #\Newline out))))))

(defun %builtin-string-repeat (context args)
  (declare (ignore context))
  (multiple-value-bind
        (repeat-count max-length quiet-p no-newline-p remaining error)
      (%parse-string-repeat-options args)
    (when error
      (return-from %builtin-string-repeat (values error 1)))
    (when (%string-repeat-bare-count-usage-p repeat-count max-length remaining)
      (return-from %builtin-string-repeat (%builtin-string-usage)))
    (if (or (null remaining)
            (not (and (plusp (or repeat-count 1))
                      (or (null max-length) (plusp max-length)))))
        (values "" 1)
        (values (%string-repeat-output remaining repeat-count max-length
                                       quiet-p no-newline-p)
                0))))
