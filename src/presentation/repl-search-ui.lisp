;;; Interactive history-search rendering.
(in-package #:nshell.presentation)

(defconstant +history-search-max-visible-matches+ 8
  "Number of history matches shown below the prompt during Ctrl-R search.")

(defvar *search-rendered-lines* 0)

(defun reset-rendered-search-state ()
  (setf *search-rendered-lines* 0))

(defun clear-rendered-search-results ()
  (when (> *search-rendered-lines* 0)
    (%clear-rendered-transient-output *search-rendered-lines*)
    (reset-rendered-search-state)))

(defun %history-search-smart-case-p (query)
  "T when QUERY should match case-insensitively. Smart case switches to
case-sensitive matching once QUERY contains an uppercase letter."
  (notany #'upper-case-p query))

(defun history-search-match-start (text query)
  "Index of QUERY's leftmost occurrence in TEXT under smart-case rules, or NIL
when QUERY does not occur in TEXT."
  (if (zerop (length query))
      0
      (search query text
             :test (if (%history-search-smart-case-p query) #'char-equal #'char=))))

(defun %search-result-marker (selected-p)
  (if selected-p "▸ " "  "))

(defun %search-result-metadata (match)
  (if (stringp match)
      (list :text match)
      match))

(defun %search-result-badges (match)
  (let ((metadata (%search-result-metadata match))
        (badges nil))
    (case (getf metadata :origin)
      (:proposal (push (list " [提案]" :prompt-assistant) badges))
      (:agent (push (list " [エージェント]" :prompt-assistant) badges)))
    (let ((exit-code (getf metadata :exit-code)))
      (when (and (integerp exit-code) (not (zerop exit-code)))
        (push (list (format nil " [終了 ~d]" exit-code) :prompt-error) badges)))
    (nreverse badges)))

(defun %search-result-badges-within-width (badges width)
  (labels ((badges-width (items)
             (reduce #'+ items
                     :key (lambda (badge)
                            (%string-visible-width (first badge)))
                     :initial-value 0))
           (fit (items)
             (cond
               ((null items) nil)
               ((<= (badges-width items) width) items)
               ((cdr items) (fit (butlast items)))
               (t (list (list (%truncate-string-to-width
                               (first (first items)) width)
                              (second (first items))))))))
    (and (plusp width) (fit badges))))

(defun %search-header-text (query count)
  (format nil "~a | 絞り込み: status:failed status:success exit:N cwd:PATH host:HOST duration-min:MS duration-max:MS origin:typed|proposal|agent"
          (if (zerop count)
              (format nil "履歴: ~a  (該当なし)" query)
              (format nil "履歴: ~a  (~d 件)" query count))))

(defun %search-result-row (match query selected-p width theme)
  (let* ((metadata (%search-result-metadata match))
         (text (getf metadata :text))
         (lines (loop with start = 0
                      for end = (position #\Newline text :start start)
                      collect (subseq text start end)
                      do (if end
                             (setf start (1+ end))
                             (loop-finish))))
         (marker (%truncate-string-to-width (%search-result-marker selected-p)
                                           width))
         (badges (%search-result-badges-within-width
                  (%search-result-badges metadata)
                  (- width (%string-visible-width marker)))))
    (loop for line in lines
          for line-index from 0
          do (when (plusp line-index)
               (format t "~%"))
             (let* ((prefix (if (zerop line-index)
                                marker
                                (%truncate-string-to-width "↳ " width)))
                    (line-badges (if (zerop line-index) badges nil))
                    (badge-width (reduce #'+ line-badges
                                         :key (lambda (badge)
                                                (%string-visible-width (first badge)))
                                         :initial-value 0))
                    (text-width (max 0 (- width
                                         (%string-visible-width prefix)
                                         badge-width)))
                    (visible-text (%truncate-string-to-width line text-width))
                    (text-visible (concatenate (quote string) prefix visible-text)))
               (if selected-p
                   (%write-styled text-visible :completion-selected theme)
                   (let* ((match-start (history-search-match-start
                                        visible-text query))
                          (match-end (and match-start
                                          (min (+ match-start (length query))
                                               (length visible-text)))))
                     (if (and match-start match-end (> match-end match-start))
                         (progn
                           (write-string prefix)
                           (write-string (subseq visible-text 0 match-start))
                           (%write-styled (subseq visible-text match-start match-end)
                                          :search-match theme)
                           (write-string (subseq visible-text match-end)))
                         (write-string text-visible))))
               (dolist (badge line-badges)
                 (%write-styled (first badge) (second badge) theme))))
    (length lines)))

(defun render-search-results (query matches selected-index
                              &key (terminal-width (terminal-width))
                                   (theme (nshell.domain.configuration:default-theme)))
  "Render the Ctrl-R match picker: a `:comment`-styled header line above up to
+HISTORY-SEARCH-MAX-VISIBLE-MATCHES+ rows of MATCHES (newest first), the row at
SELECTED-INDEX marked and styled `:completion-selected`. Returns the number of
lines written, for the caller to clear on the next redraw."
  (let* ((count (length matches))
         (visible-matches
           (subseq matches 0 (min +history-search-max-visible-matches+ count)))
         (rendered-match-lines 0))
    (format t "~%")
    (%write-styled
     (%truncate-string-to-width (%search-header-text query count)
                                terminal-width)
     :comment theme)
    (format t "~%")
    (loop for match in visible-matches
          for index from 0
          do (incf rendered-match-lines
                   (%search-result-row match query (eql index selected-index)
                                       terminal-width theme))
             (format t "~%"))
    (1+ rendered-match-lines)))

(defun render-search-results-below-prompt (query matches selected-index)
  (setf *search-rendered-lines*
        (%render-transient-output-below-prompt
         (lambda ()
           (render-search-results
            query matches selected-index
            :theme (nshell.domain.configuration:config-theme *config*))))))

(defun render-current-history-search-panel ()
  "Recompute the current query's matches from *HISTORY* and render the picker
below the prompt using the input state's already-clamped selection index."
  (let* ((query (input-state-search-query *input-state*))
         (entries (nshell.application:interactive-history-search-use-case
                   *history* query))
         (matches (mapcar (lambda (entry)
                            (list :text (history-kit:history-entry-text entry)
                                  :exit-code (history-kit:history-entry-exit-code entry)
                                  :origin
                                  (nshell.infrastructure.persistence:history-record-origin
                                   (nshell.infrastructure.persistence:history-record-for-entry
                                    *history* entry))))
                          entries)))
    (render-search-results-below-prompt
     query matches (input-state-search-index *input-state*))))
