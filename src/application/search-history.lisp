(in-package #:nshell.application)

(declaim (ftype function
                nshell.infrastructure.persistence::history-record-filter-token
                nshell.infrastructure.persistence::history-record-for-entry
                nshell.infrastructure.persistence::history-record-matches-p))

(defun %interactive-history-query-valid-p (query)
  (and query
       (not (nshell.domain.parsing:shell-input-blank-p
             query
             :include-return-p t))))

(defun %interactive-history-filter-with (filter key value)
  (list* key value
         (loop for (old-key old-value) on filter by #'cddr
               unless (eq old-key key)
                 append (list old-key old-value))))

(defun %interactive-history-filter-query (query)
  (let ((filter nil)
        (query-parts nil))
    (dolist (part (uiop:split-string query
                                     :separator '(#\Space #\Tab #\Newline)))
      (let ((token-filter
              (nshell.infrastructure.persistence::history-record-filter-token
               part)))
        (if token-filter
            (loop for (key value) on token-filter by #'cddr
                  do (setf filter (%interactive-history-filter-with filter key value)))
            (push part query-parts))))
    (values filter (%string-join (nreverse query-parts) " "))))

(defun %interactive-history-entry-filter-p (history entry filter)
  (or (null filter)
      (apply #'nshell.infrastructure.persistence::history-record-matches-p
             (nshell.infrastructure.persistence::history-record-for-entry
              history entry)
             filter)))

(defun %interactive-history-search-matches (history query)
  (multiple-value-bind (filter search-query)
      (%interactive-history-filter-query query)
    (when (or (%interactive-history-query-valid-p search-query) filter)
      (let ((prefix-matches
              (if (%interactive-history-query-valid-p search-query)
                  (history-kit:history-search history search-query
                                              :mode :line-prefix)
                  nil))
            (contains-matches
              (if (%interactive-history-query-valid-p search-query)
                  (history-kit:history-search history search-query
                                              :mode :contains)
                  (history-kit:history-entries history)))
            (seen (make-hash-table :test #'equal))
            (unique-contains nil))
        (setf prefix-matches
              (remove-if-not (lambda (entry)
                              (%interactive-history-entry-filter-p
                               history entry filter))
                            prefix-matches)
              contains-matches
              (remove-if-not (lambda (entry)
                              (%interactive-history-entry-filter-p
                               history entry filter))
                            contains-matches))
        (dolist (entry prefix-matches)
          (setf (gethash (history-kit:history-entry-text entry) seen) t))
        (dolist (entry contains-matches)
          (let ((text (history-kit:history-entry-text entry)))
            (unless (gethash text seen)
              (setf (gethash text seen) t)
              (push entry unique-contains))))
        (append prefix-matches (nreverse unique-contains))))))

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

(defun search-history-use-case (history query mode &key (exit-code :any) cwd origin)
  (remove-if-not
   (lambda (entry)
     (nshell.infrastructure.persistence::history-record-matches-p
      (nshell.infrastructure.persistence::history-record-for-entry history entry)
      :exit-code exit-code
      :cwd cwd
      :origin origin))
   (history-kit:history-search history query :mode mode)))

(defun interactive-history-search-use-case (history query)
  "Search for interactive reverse search, preferring command-line starts.

  Line-prefix matches make multi-line history feel command-aware: a continuation
  line that starts with QUERY ranks before incidental mid-line substring matches,
  while the contains fallback preserves the usual Ctrl-R substring search.

  Metadata filters may be entered as status:failed, exit:N, cwd:PATH, or
  origin:typed|proposal|agent tokens in the query."
  (%interactive-history-search-matches history query))
