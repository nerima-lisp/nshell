(in-package #:nshell.application)

(defun %interactive-history-query-valid-p (query)
  (and query
       (not (nshell.domain.parsing:shell-input-blank-p
             query
             :include-return-p t))))

(defun %interactive-history-search-matches (history query)
  (when (%interactive-history-query-valid-p query)
    (let ((prefix-matches
            (history-kit:history-search history query :mode :line-prefix))
          (contains-matches
            (history-kit:history-search history query :mode :contains))
          (seen (make-hash-table :test #'equal))
          (unique-contains nil))
      (dolist (entry prefix-matches)
        (setf (gethash (history-kit:history-entry-text entry) seen) t))
      (dolist (entry contains-matches)
        (let ((text (history-kit:history-entry-text entry)))
          (unless (gethash text seen)
            (setf (gethash text seen) t)
            (push entry unique-contains))))
      (append prefix-matches (nreverse unique-contains)))))

(defun %interactive-history-best-entry (matches)
  (or (find-if (lambda (entry)
                 (let ((exit-code (history-kit:history-entry-exit-code entry)))
                   (or (null exit-code)
                       (zerop exit-code))))
               matches)
      (first matches)))

(defun history-suggestion (history input)
  (unless (nshell.domain.parsing:shell-input-blank-p input)
    (let ((matches (history-kit:history-search history input :mode :line-prefix)))
      (when matches
        (let* ((best (%interactive-history-best-entry matches))
               (suffix
                 (history-kit:history-entry-line-suffix
                  best
                  input
                  :case-sensitive (some #'upper-case-p input))))
          (when (and suffix (< 0 (length suffix)))
            suffix))))))

(defun search-history-use-case (history query mode)
  (history-kit:history-search history query :mode mode))

(defun interactive-history-search-use-case (history query)
  "Search for interactive reverse search, preferring command-line starts.

  Line-prefix matches make multi-line history feel command-aware: a continuation
  line that starts with QUERY ranks before incidental mid-line substring matches,
while the contains fallback preserves the usual Ctrl-R substring search."
  (%interactive-history-search-matches history query))
