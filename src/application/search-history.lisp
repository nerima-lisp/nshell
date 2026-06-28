(in-package #:nshell.application)

(defun %interactive-history-search-matches (history query)
  (when (and query (not (nshell.domain.parsing:shell-input-blank-p
                         query
                         :include-return-p t)))
    (let ((case-sensitive (some #'upper-case-p query))
          (line-prefix-matches nil)
          (contains-candidates nil)
          (line-prefix-texts (make-hash-table :test #'equal)))
      (labels ((line-prefix-match-p (text)
                 (loop with line-start = 0
                       for newline = (position #\Newline text :start line-start)
                       for line-end = (or newline (length text))
                       for query-end = (+ line-start (length query))
                       thereis (and (<= query-end line-end)
                                    (if case-sensitive
                                        (string= text query :start1 line-start :end1 query-end)
                                        (string-equal text query :start1 line-start :end1 query-end)))
                       while newline
                       do (setf line-start (1+ newline))))
               (contains-match-p (text)
                 (if case-sensitive
                     (search query text)
                     (search query text :test #'char-equal))))
        (dolist (entry (nshell.domain.history:history-all history))
          (let ((text (nshell.domain.history:entry-text entry)))
            (when (line-prefix-match-p text)
              (setf (gethash text line-prefix-texts) t)
              (push entry line-prefix-matches))
            (when (contains-match-p text)
              (push (cons text entry) contains-candidates)))))
      (append (nreverse line-prefix-matches)
              (loop for (text . entry) in (nreverse contains-candidates)
                    unless (gethash text line-prefix-texts)
                      collect entry)))))

(defun history-suggestion (history input &optional dispatcher)
  (unless (nshell.domain.parsing:shell-input-blank-p input)
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-completion-triggered-event input)))
    (let ((matches (nshell.domain.history:history-search history input :mode :line-prefix)))
      (when matches
        (let* ((best (or (find-if (lambda (entry)
                                    (let ((exit-code (nshell.domain.history:entry-exit-code entry)))
                                      (or (null exit-code)
                                          (zerop exit-code))))
                                  matches)
                         (first matches)))
               (suffix
                 (nshell.domain.history:history-entry-line-prefix-suffix
                  best
                  input
                  :case-sensitive (some #'upper-case-p input))))
          (when (and suffix (< 0 (length suffix)))
            suffix))))))

(defun search-history-use-case (history query mode &optional dispatcher)
  (let ((matches (nshell.domain.history:history-search history query :mode mode)))
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-domain-event :history-searched)))
    matches))

(defun interactive-history-search-use-case (history query &optional dispatcher)
  "Search for interactive reverse search, preferring command-line starts.

  Line-prefix matches make multi-line history feel command-aware: a continuation
line that starts with QUERY ranks before incidental mid-line substring matches,
while the contains fallback preserves the usual Ctrl-R substring search."
  (let ((matches (%interactive-history-search-matches history query)))
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-domain-event :history-searched)))
    matches))
