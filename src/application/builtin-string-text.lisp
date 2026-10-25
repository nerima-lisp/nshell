(in-package #:nshell.application)

(defun %string-empty-p (string)
  (zerop (length string)))

(defun %string-emit-lines (lines &key (transform #'identity))
  (with-output-to-string (out)
    (dolist (line lines)
      (write-string (funcall transform line) out)
      (write-char #\Newline out))))

(defun %string-collect-texts (texts quiet-p collector)
  (let ((matched-p nil))
    (values
     (with-output-to-string (out)
       (dolist (text texts)
         (multiple-value-bind (line text-matched-p)
             (funcall collector text)
           (when text-matched-p
             (setf matched-p t)
             (unless quiet-p
               (write-string line out)
               (write-char #\Newline out))))))
     (if matched-p 0 1))))

(defun %string-wildcard-match-p (pattern string &key ignore-case)
  (if ignore-case
      (nshell.domain.expansion:glob-match-p
       (string-downcase pattern)
       (string-downcase string))
      (nshell.domain.expansion:glob-match-p pattern string)))

(defun %string-replace-text (text pattern replacement &key all ignore-case)
  (let ((test (%string-character-test ignore-case))
        (pattern-length (length pattern)))
    (if (%string-empty-p pattern)
        (values text nil)
        (if all
            (let ((matched-p nil))
              (values
               (with-output-to-string (out)
                 (loop with start = 0
                       for pos = (search pattern text :start2 start :test test)
                       while pos
                       do (setf matched-p t)
                          (write-string (subseq text start pos) out)
                          (write-string replacement out)
                          (setf start (+ pos pattern-length))
                       finally (write-string (subseq text start) out)))
               matched-p))
            (let ((pos (search pattern text :start2 0 :test test)))
              (if pos
                  (values (concatenate 'string
                                       (subseq text 0 pos)
                                       replacement
                                       (subseq text (+ pos pattern-length)))
                          t)
                  (values text nil)))))))

(defun %string-trim-trailing-newlines (string)
  (let ((end (length string)))
    (loop while (and (> end 0)
                     (char= (char string (1- end)) #\Newline))
          do (decf end))
    (subseq string 0 end)))
