(in-package #:nshell.domain.history)

(defun history-match-prefix (entry query &key case-sensitive)
  "True if ENTRY text starts with QUERY."
  (let ((text (history-entry-text entry)))
    (if case-sensitive
        (and (>= (length text) (length query))
             (string= text query :end1 (length query)))
        (and (>= (length text) (length query))
             (string-equal text query :end1 (length query))))))

(defun history-match-exact (entry query &key case-sensitive)
  "True if ENTRY text exactly matches QUERY."
  (if case-sensitive
      (string= (history-entry-text entry) query)
      (string-equal (history-entry-text entry) query)))

(defun history-match-contains (entry query &key case-sensitive)
  "True if ENTRY text contains QUERY."
  (let ((text (history-entry-text entry)))
    (if case-sensitive
        (search query text)
        (search query text :test #'char-equal))))

(defun line-starts-with-p (text query line-start line-end case-sensitive)
  (let ((query-end (+ line-start (length query))))
    (and (<= query-end line-end)
         (if case-sensitive
             (string= text query :start1 line-start :end1 query-end)
             (string-equal text query :start1 line-start :end1 query-end)))))

(defun history-match-line-prefix (entry query &key case-sensitive)
  "True if any line in ENTRY text starts with QUERY."
  (let ((text (history-entry-text entry)))
    (loop with line-start = 0
          for newline = (position #\Newline text :start line-start)
          for line-end = (or newline (length text))
          thereis (line-starts-with-p text query line-start line-end case-sensitive)
          while newline
          do (setf line-start (1+ newline)))))

(defun history-entry-line-prefix-suffix (entry query &key case-sensitive)
  "Return the suffix after QUERY for the first ENTRY line starting with QUERY."
  (let ((text (history-entry-text entry)))
    (loop with line-start = 0
          for newline = (position #\Newline text :start line-start)
          for line-end = (or newline (length text))
          when (line-starts-with-p text query line-start line-end case-sensitive)
            return (subseq text (+ line-start (length query)) line-end)
          while newline
          do (setf line-start (1+ newline)))))

(defun history-search (history query &key (mode :prefix) (case-sensitive nil) (smartcase t))
  "Search HISTORY for entries matching QUERY."
  (let ((match-fn (ecase mode
                    (:prefix #'history-match-prefix)
                    (:exact #'history-match-exact)
                    (:contains #'history-match-contains)
                    (:line-prefix #'history-match-line-prefix)))
        (effective-case-sensitive (if smartcase
                                      (some #'upper-case-p query)
                                      case-sensitive)))
    (remove-if-not (lambda (entry)
                     (funcall match-fn entry query
                              :case-sensitive effective-case-sensitive))
                   (command-history-entries history))))
