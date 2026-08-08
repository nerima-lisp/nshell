(in-package #:nshell.domain.history)

(defun %history-cap-entries (history entries)
  (subseq entries 0 (min (length entries)
                         (command-history-max-entries history))))

(defun %history-unique-entries (entries)
  (let ((seen (make-hash-table :test #'equal)))
    (loop for entry in entries
          for text = (entry-text entry)
          unless (gethash text seen)
            do (setf (gethash text seen) t)
            and collect entry)))

(defun %history-replace-entries (history entries &key clear-navigation-p)
  (setf (command-history-entries history)
        (%history-cap-entries history entries))
  (when clear-navigation-p
    (%history-clear-navigation history))
  history)

(defun history-add (history text &optional exit-code)
  "Add TEXT to HISTORY and keep the newest entry for duplicate command text."
  (let* ((entry (make-history-entry text (get-universal-time) exit-code))
         (new-entries (%history-unique-entries
                       (cons entry (command-history-entries history)))))
    (%history-replace-entries history new-entries)))

(defun history-all (history)
  "Return all history entries, most recent first."
  (command-history-entries history))

(defun history-empty-p (history)
  "True if HISTORY has no entries."
  (null (command-history-entries history)))

(defun history-clear (history)
  "Remove all entries from HISTORY and reset transient navigation."
  (%history-replace-entries history nil :clear-navigation-p t))

(defun history-delete (history text &key (case-sensitive t))
  "Delete entries whose text exactly matches TEXT and return the deleted count."
  (let* ((old-entries (command-history-entries history))
         (new-entries
           (remove-if (lambda (entry)
                        (%history-text-equal-p (entry-text entry) text
                                               :case-sensitive case-sensitive))
                      old-entries))
         (deleted (- (length old-entries) (length new-entries))))
    (%history-replace-entries history new-entries)
    (when (plusp deleted)
      (%history-clear-navigation history))
    deleted))

(defun history-size (history)
  "Return current number of entries in HISTORY."
  (length (command-history-entries history)))

(defun history-merge (history entries)
  "Merge ENTRIES into HISTORY, preserving newest-first de-duplicated order."
  (let ((source-entries (if (command-history-p entries)
                            (command-history-entries entries)
                            entries)))
    (dolist (entry (reverse source-entries) history)
      (history-add history
                   (history-entry-text entry)
                   (history-entry-exit-code entry)))))

(defun %history-expansion-entry-by-index (history index)
  (let ((entries (history-all history)))
    (when (and (integerp index)
               (<= 0 index)
               (< index (length entries)))
      (entry-text (nth index entries)))))

(defun %history-expansion-error (designator)
  (format nil "history expansion failed: ~a" designator))

(defun %history-expansion-delimiter-p (character)
  (find character '(#\Space #\Tab #\Newline #\Return
                    #\; #\| #\& #\< #\> #\( #\) #\' #\" #\\)
        :test #'char=))

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
                    (replacement (%history-expansion-entry-by-index history
                                                                       (1- index))))
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
                   (entry (find-if
                           (lambda (candidate)
                             (%history-text-contains-p
                              (entry-text candidate) query :case-sensitive t))
                           (history-all history))))
              (if entry
                  (values (entry-text entry) (1+ close) nil t)
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
                    (entry (find-if
                            (lambda (candidate)
                              (%history-text-prefix-p
                               (entry-text candidate) designator
                               :case-sensitive t))
                            (history-all history))))
               (if entry
                   (values (entry-text entry) end nil t)
                   (values nil end
                           (%history-expansion-error designator)
                           t)))))))))

(defun history-expand-line (history line)
  "Expand common interactive history designators in LINE without mutating HISTORY.

Return the expanded line and NIL on success.  If a recognized designator cannot
be resolved, return NIL and an explanatory error string.  Single-quoted and
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
