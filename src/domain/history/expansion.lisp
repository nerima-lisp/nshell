(in-package #:nshell.domain.history)

(defun %history-expansion-entry-by-index (history index)
  (let ((entries (history-kit:history-entries history)))
    (when (and (integerp index)
               (<= 0 index)
               (< index (length entries)))
      (history-kit:history-entry-text (nth index entries)))))

(defun %history-expansion-error (designator)
  (format nil "history expansion failed: ~a" designator))

(defun %history-expansion-delimiter-p (character)
  (find character '(#\Space #\Tab #\Newline #\Return
                    #\; #\| #\& #\< #\> #\( #\) #\' #\" #\\)
        :test #'char=))

(defun %history-expansion-prefix-p (prefix text)
  (and (stringp text)
       (<= (length prefix) (length text))
       (string= prefix text :end2 (length prefix))))

(defun %history-expansion-at (history line start)
  (let* ((line-length (length line))
         (next (1+ start)))
    (cond
      ((>= next line-length)
       (values nil next nil nil))
      ((char= (char line next) #\!)
       (let ((replacement (%history-expansion-entry-by-index history 0)))
         (if (stringp replacement)
             (values replacement (+ next 1) nil t)
             (values nil (+ next 1) (%history-expansion-error "!!") t))))
      ((char= (char line next) #\$)
       (let ((replacement (history-last-argument-at history 0)))
         (if (stringp replacement)
             (values replacement (+ next 1) nil t)
             (values nil (+ next 1) (%history-expansion-error "!$") t))))
      ((char= (char line next) #\-)
       (let ((digit-start (+ next 1))
             (digit-end (+ next 1)))
         (loop while (and (< digit-end line-length)
                          (digit-char-p (char line digit-end)))
               do (incf digit-end))
         (if (= digit-start digit-end)
             (values nil next nil nil)
             (let* ((index (parse-integer line :start digit-start :end digit-end))
                    (replacement
                      (%history-expansion-entry-by-index history (1- index))))
               (if (and (plusp index) (stringp replacement))
                   (values replacement digit-end nil t)
                   (values nil digit-end
                           (%history-expansion-error
                            (subseq line start digit-end))
                           t))))))
      ((char= (char line next) #\?)
       (let ((close (position #\? line :start (+ next 1))))
         (cond
           ((null close)
            (values nil line-length
                    (%history-expansion-error (subseq line start)) t))
           ((= close (+ next 1))
            (values nil (1+ close)
                    (%history-expansion-error (subseq line start (1+ close))) t))
           (t
            (let* ((query (subseq line (+ next 1) close))
                   (entry
                     (find-if
                      (lambda (candidate)
                        (search query
                                (history-kit:history-entry-text candidate)))
                      (history-kit:history-entries history))))
              (if entry
                  (values (history-kit:history-entry-text entry)
                          (1+ close) nil t)
                  (values nil (1+ close)
                          (%history-expansion-error
                           (subseq line start (1+ close)))
                          t)))))))
      (t
       (let ((end (loop with position = next
                        while (and (< position line-length)
                                   (not (%history-expansion-delimiter-p
                                         (char line position))))
                        do (incf position)
                        finally (return position))))
         (if (= end next)
             (values nil next nil nil)
             (let* ((designator (subseq line next end))
                    (entry
                    (find-if
                     (lambda (candidate)
                        (%history-expansion-prefix-p
                         designator
                         (history-kit:history-entry-text candidate)))
                       (history-kit:history-entries history))))
               (if entry
                   (values (history-kit:history-entry-text entry) end nil t)
                   (values nil end
                           (%history-expansion-error designator)
                           t)))))))))

(defun history-expand-line (history line)
  "Expand common interactive history designators in LINE without mutating HISTORY.

Return the expanded line and NIL on success. If a recognized designator cannot
be resolved, return NIL and an explanatory error string. Single-quoted and
backslash-escaped exclamation marks remain literal."
  (block expansion
    (let ((position 0)
          (single-quoted-p nil)
          (line-length (length line)))
      (values
       (with-output-to-string (output)
         (loop while (< position line-length)
               do (let ((character (char line position)))
                    (cond
                      ((and (not single-quoted-p)
                            (char= character #\\)
                            (< (1+ position) line-length))
                       (write-char character output)
                       (write-char (char line (1+ position)) output)
                       (incf position 2))
                      ((char= character #\')
                       (write-char character output)
                       (setf single-quoted-p (not single-quoted-p))
                       (incf position))
                      ((and (not single-quoted-p) (char= character #\!))
                       (multiple-value-bind (replacement next-position error
                                             expanded-p)
                           (%history-expansion-at history line position)
                         (if expanded-p
                             (if error
                                 (return-from expansion (values nil error))
                                 (progn
                                   (write-string replacement output)
                                   (setf position next-position)))
                             (progn
                               (write-char character output)
                               (incf position)))))
                      (t
                       (write-char character output)
                       (incf position))))))
       nil))))
