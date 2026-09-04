;;; Shell glob matching and filesystem candidates
(in-package #:nshell.domain.expansion)

(defun pathname-directory-string (path)
  (let ((dir (pathname-directory (pathname path))))
    (cond
      ((and dir (member :absolute dir))
       (format nil "/~{~a/~}" (remove :absolute dir)))
      ((and dir (member :relative dir))
       (format nil "~{~a/~}" (remove :relative dir)))
      (t ""))))

(defun glob-char-p (ch)
  "True when CH is a shell glob metacharacter (*, ?, or [)."
  (member ch '(#\* #\? #\[) :test #'char=))

(defun glob-root (pattern)
  (let ((wild (position-if #'glob-char-p pattern)))
    (if wild
        (let* ((prefix (subseq pattern 0 wild))
               (slash (position #\/ prefix :from-end t)))
          (if slash (subseq prefix 0 (1+ slash)) "./"))
        (pathname-directory-string pattern))))

(defun %walk-directory-files (filesystem dir continuation)
  (let ((directory-files (and filesystem
                              (nshell.domain.filesystem:filesystem-directory-files filesystem)))
        (subdirectories (and filesystem
                             (nshell.domain.filesystem:filesystem-subdirectories filesystem))))
    (when (functionp directory-files)
      (dolist (file (funcall directory-files dir)) (funcall continuation file)))
    (when (functionp subdirectories)
      (dolist (subdir (funcall subdirectories dir))
        (%walk-directory-files filesystem subdir continuation)))))

(defun recursive-directory-files (root &optional filesystem)
  (unless filesystem (return-from recursive-directory-files))
  (ignore-errors
    (let ((files '()))
      (%walk-directory-files filesystem (pathname root) (lambda (file) (push file files)))
      files)))

(defun immediate-directory-files (root &optional filesystem)
  (let ((directory-files (and filesystem
                              (nshell.domain.filesystem:filesystem-directory-files filesystem))))
    (when (functionp directory-files)
      (ignore-errors (funcall directory-files (pathname root))))))

(define-value-struct %glob-match-subject
    ((pattern "" :type string) (root "./") (file #p"" :type pathname)))

(defun %glob-file-match-subject (pattern root file)
  (%make-glob-match-subject pattern root file))

(defun %glob-match-subject-candidate (subject)
  (let* ((root (glob-match-subject-root subject))
         (candidate (namestring (glob-match-subject-file subject))))
    (cond
      ((string= root "./") (if (string-prefix-p "./" candidate) (subseq candidate 2) candidate))
      ((string-prefix-p root candidate) candidate)
      (t (concatenate 'string root candidate)))))

(defun glob-pattern-p (pattern) (some #'glob-char-p pattern))

(defun bracket-negation-p (pattern start end)
  (and (< start end) (member (char pattern start) '(#\! #\^) :test #'char=)))

(defun bracket-range-member-p (pattern start end ch)
  (loop with index = start while (< index end)
        thereis (let ((left (char pattern index)))
                  (cond
                    ((and (< (+ index 2) end) (char= (char pattern (1+ index)) #\-))
                     (let ((right (char pattern (+ index 2))))
                       (incf index 3) (char<= left ch right)))
                    (t (incf index) (char= left ch))))))

(defun bracket-match-p (pattern-index pattern ch)
  (let ((end (position #\] pattern :start (1+ pattern-index))))
    (if end
        (let* ((content-start (1+ pattern-index))
               (negated-p (bracket-negation-p pattern content-start end))
               (match-start (if negated-p (1+ content-start) content-start))
               (matched-p (bracket-range-member-p pattern match-start end ch)))
          (values (if negated-p (not matched-p) matched-p) (1+ end) t))
        (values nil (1+ pattern-index) nil))))

(defun glob-match-p (pattern text)
  (let ((pattern-length (length pattern)) (text-length (length text)))
    (labels ((match (pidx tidx)
               (cond
                 ((= pidx pattern-length) (= tidx text-length))
                 ((and (< (1+ pidx) pattern-length)
                       (char= (char pattern pidx) #\*)
                       (char= (char pattern (1+ pidx)) #\*))
                  (or (match (+ pidx 2) tidx)
                      (and (< tidx text-length) (match pidx (1+ tidx)))))
                 ((char= (char pattern pidx) #\*)
                  (or (match (1+ pidx) tidx)
                      (and (< tidx text-length) (char/= (char text tidx) #\/) (match pidx (1+ tidx)))))
                 ((char= (char pattern pidx) #\?)
                  (and (< tidx text-length) (char/= (char text tidx) #\/) (match (1+ pidx) (1+ tidx))))
                 ((char= (char pattern pidx) #\[)
                  (and (< tidx text-length)
                       (multiple-value-bind (ok next-pidx parsed-p)
                           (bracket-match-p pidx pattern (char text tidx))
                         (if parsed-p (and ok (match next-pidx (1+ tidx)))
                             (and (char= (char text tidx) #\[) (match (1+ pidx) (1+ tidx)))))))
                 (t (and (< tidx text-length) (char= (char pattern pidx) (char text tidx))
                         (match (1+ pidx) (1+ tidx)))))))
      (match 0 0))))
