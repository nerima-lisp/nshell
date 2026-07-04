(in-package #:nshell.domain.history)

(defun history-match-prefix (entry query &key case-sensitive)
  "True if ENTRY text starts with QUERY."
  (%history-text-prefix-p (history-entry-text entry) query
                          :case-sensitive case-sensitive))

(defun history-match-exact (entry query &key case-sensitive)
  "True if ENTRY text exactly matches QUERY."
  (%history-text-equal-p (history-entry-text entry) query
                         :case-sensitive case-sensitive))

(defun history-match-contains (entry query &key case-sensitive)
  "True if ENTRY text contains QUERY."
  (%history-text-contains-p (history-entry-text entry) query
                            :case-sensitive case-sensitive))

(defun history-match-line-prefix (entry query &key case-sensitive)
  "True if any line in ENTRY text starts with QUERY."
  (%history-line-prefix-p (history-entry-text entry) query
                          :case-sensitive case-sensitive))

(defun history-entry-line-prefix-suffix (entry query &key case-sensitive)
  "Return the suffix after QUERY for the first ENTRY line starting with QUERY."
  (let ((text (history-entry-text entry)))
    (loop with line-start = 0
          for newline = (position #\Newline text :start line-start)
          for line-end = (or newline (length text))
          when (and (<= (+ line-start (length query)) line-end)
                    (if case-sensitive
                        (string= text query
                                 :start1 line-start
                                 :end1 (+ line-start (length query)))
                        (string-equal text query
                                      :start1 line-start
                                      :end1 (+ line-start (length query)))))
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
