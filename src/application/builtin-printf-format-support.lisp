(in-package #:nshell.application)

(defun %printf-pad (text width left-p &optional (pad-character #\Space))
  (let ((padding (max 0 (- (or width 0) (length text)))))
    (if (zerop padding)
        text
        (let ((padding-text (make-string padding :initial-element pad-character)))
          (if left-p
              (concatenate 'string text padding-text)
              (concatenate 'string padding-text text))))))

(defun %printf-flag-p (flags flag)
  (find flag flags :test #'char=))
