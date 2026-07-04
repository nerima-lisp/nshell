(in-package #:nshell.application)

(defstruct (%interactive-history-candidate
            (:constructor %make-interactive-history-candidate (text entry)))
  (text "" :type string :read-only t)
  (entry nil :read-only t))

(defun %interactive-history-query-case-sensitive-p (query)
  (some #'upper-case-p query))

(defun %interactive-history-query-valid-p (query)
  (and query
       (not (nshell.domain.parsing:shell-input-blank-p
             query
             :include-return-p t))))

(defun %interactive-history-line-prefix-match-p (text query case-sensitive)
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

(defun %interactive-history-contains-match-p (text query case-sensitive)
  (if case-sensitive
      (search query text)
      (search query text :test #'char-equal)))

(defun %interactive-history-line-prefix-matches (history query case-sensitive)
  (let ((entries nil)
        (texts (make-hash-table :test #'equal)))
    (dolist (entry (nshell.domain.history:history-all history))
      (let ((text (nshell.domain.history:entry-text entry)))
        (when (%interactive-history-line-prefix-match-p text query case-sensitive)
          (setf (gethash text texts) t)
          (push entry entries))))
    (values (nreverse entries) texts)))

(defun %interactive-history-contains-candidates (history query case-sensitive)
  (let ((candidates nil))
    (dolist (entry (nshell.domain.history:history-all history))
      (let ((text (nshell.domain.history:entry-text entry)))
        (when (%interactive-history-contains-match-p text query case-sensitive)
          (push (%make-interactive-history-candidate text entry)
                candidates))))
    (nreverse candidates)))

(defun %interactive-history-search-matches (history query)
  (when (%interactive-history-query-valid-p query)
    (let ((case-sensitive (%interactive-history-query-case-sensitive-p query)))
      (multiple-value-bind (line-prefix-matches line-prefix-texts)
          (%interactive-history-line-prefix-matches history query case-sensitive)
        (let ((contains-candidates
                (%interactive-history-contains-candidates history query case-sensitive)))
          (append line-prefix-matches
                  (loop for candidate in contains-candidates
                        for text = (%interactive-history-candidate-text candidate)
                        unless (gethash text line-prefix-texts)
                          collect (%interactive-history-candidate-entry candidate))))))))

(defun %interactive-history-best-entry (matches)
  (or (find-if (lambda (entry)
                 (let ((exit-code (nshell.domain.history:entry-exit-code entry)))
                   (or (null exit-code)
                       (zerop exit-code))))
               matches)
      (first matches)))

(defun history-suggestion (history input &optional dispatcher)
  (unless (nshell.domain.parsing:shell-input-blank-p input)
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-completion-triggered-event input)))
    (let ((matches (nshell.domain.history:history-search history input :mode :line-prefix)))
      (when matches
        (let* ((best (%interactive-history-best-entry matches))
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
                     (nshell.domain.events:make-history-searched-event)))
    matches))

(defun interactive-history-search-use-case (history query &optional dispatcher)
  "Search for interactive reverse search, preferring command-line starts.

  Line-prefix matches make multi-line history feel command-aware: a continuation
line that starts with QUERY ranks before incidental mid-line substring matches,
while the contains fallback preserves the usual Ctrl-R substring search."
  (let ((matches (%interactive-history-search-matches history query)))
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-history-searched-event)))
    matches))
