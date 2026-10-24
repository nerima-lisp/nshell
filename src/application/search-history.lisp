(in-package #:nshell.application)

(declaim (ftype function
                nshell.infrastructure.persistence:history-record-filter-token
                nshell.infrastructure.persistence:history-record-for-entry
                nshell.infrastructure.persistence:history-record-matches-p))

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
        (query-parts nil)
        (search-parts nil)
        (part nil)
        (quoted-p nil))
    (labels ((finish-part ()
               (when part
                 (push (coerce (nreverse part) 'string) query-parts)
                 (setf part nil))))
      (loop for character across query
            do (cond
                 ((char= character #\")
                  (setf quoted-p (not quoted-p)))
                 ((and (not quoted-p)
                       (member character '(#\Space #\Tab #\Newline)))
                  (finish-part))
                 (t (push character part))))
      (finish-part))
    (dolist (part (nreverse query-parts))
      (let ((token-filter
              (nshell.infrastructure.persistence:history-record-filter-token
               part)))
        (if token-filter
            (loop for (key value) on token-filter by #'cddr
                  do (setf filter (%interactive-history-filter-with filter key value)))
            (push part search-parts))))
    (values filter (%string-join (nreverse search-parts) " "))))

(defun %interactive-history-entry-filter-p (history entry filter)
  (or (null filter)
      (apply #'nshell.infrastructure.persistence:history-record-matches-p
             (nshell.infrastructure.persistence:history-record-for-entry
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

(defun history-suggestion (history input &key cwd)
  (unless (nshell.domain.parsing:shell-input-blank-p input)
    (let* ((matches
             (history-kit:history-search history input :mode :line-prefix))
           (cwd-matches
             (and (stringp cwd)
                  (remove-if-not
                   (lambda (entry)
                     (%interactive-history-entry-filter-p
                      history entry (list :cwd cwd)))
                   matches)))
           (ranked-matches (or cwd-matches matches)))
      (when ranked-matches
        (let* ((best (%interactive-history-best-entry ranked-matches))
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
     (nshell.infrastructure.persistence:history-record-matches-p
      (nshell.infrastructure.persistence:history-record-for-entry history entry)
      :exit-code exit-code
      :cwd cwd
      :origin origin))
   (history-kit:history-search history query :mode mode)))

(defun interactive-history-search-use-case (history query)
  "After recognized metadata tokens are removed, entries with any line starting
  with the remaining free-text query are placed in the prefix group only; a
  substring match does not duplicate them. Entries without a line-prefix match
  but with a substring match follow. Both groups are newest first. With only
  metadata filters, results are newest first.

  Spaces, tabs, and newlines separate query terms. Double quotes group spaces
  inside a token and are removed before matching. They let metadata values
  include spaces, as in cwd:\"/workspace/My Project\". A backslash does not
  escape a quote; each quote opens or closes grouping. An unmatched opening
  quote extends the token to the end of the query.
  Recognized metadata tokens filter entries; unrecognized tokens remain free
  text. Every distinct filter and the free-text query must match. Repeated
  fields use only their last token. Free-text terms are joined with spaces and
  searched together as one query. Smart case uses only this free-text query:
  without uppercase letters, matching is case-insensitive; with an uppercase
  letter, it is case-sensitive. Metadata values do not affect that choice.
  With no free text, filters apply to all history entries. Without free text or
  a recognized filter, no entries are returned.

  Supported status tokens are status:failed, status:success, and status:ok.
  Other supported tokens are exit:N, cwd:PATH, origin:typed|proposal|agent,
  host:HOST, duration-min:MILLISECONDS, and duration-max:MILLISECONDS. Token
  names and status/origin values are case-sensitive. status:failed matches
  recorded nonzero exit codes. status:success and status:ok match recorded exit
  code 0. exit:N matches code N. Records without an exit code match none of the
  status or exit filters. cwd and host values must match exactly, including
  case. Duration limits use milliseconds and include the boundary. Entries
  without recorded durations match neither limit."
  (%interactive-history-search-matches history query))
