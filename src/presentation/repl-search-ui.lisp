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

(defun %search-result-row (text query selected-p width theme)
  (let* ((marker (%search-result-marker selected-p))
         (visible (%truncate-string-to-width
                   (concatenate 'string marker text) width)))
    (if selected-p
        (%write-styled visible :completion-selected theme)
        (let* ((marker-length (length marker))
               (match-start (history-search-match-start text query))
               (row-start (and match-start (+ marker-length match-start)))
               (visible-length (length visible)))
          (if (and row-start (< row-start visible-length))
              (let ((row-end (min (+ row-start (length query)) visible-length)))
                (write-string (subseq visible 0 row-start))
                (%write-styled (subseq visible row-start row-end) :search-match theme)
                (write-string (subseq visible row-end)))
              (write-string visible))))))

(defun %search-header-text (query count)
  (if (zerop count)
      (format nil "history: ~a  (no matches)" query)
      (format nil "history: ~a  (~d matches)" query count)))

(defun render-search-results (query matches selected-index
                              &key (terminal-width (terminal-width))
                                   (theme (nshell.domain.configuration:default-theme)))
  "Render the Ctrl-R match picker: a `:comment`-styled header line above up to
+HISTORY-SEARCH-MAX-VISIBLE-MATCHES+ rows of MATCHES (newest first), the row at
SELECTED-INDEX marked and styled `:completion-selected`. Returns the number of
lines written, for the caller to clear on the next redraw."
  (let* ((count (length matches))
         (visible-matches
           (subseq matches 0 (min +history-search-max-visible-matches+ count))))
    (format t "~%")
    (%write-styled (%search-header-text query count) :comment theme)
    (format t "~%")
    (loop for text in visible-matches
          for index from 0
          do (%search-result-row text query (eql index selected-index)
                                 terminal-width theme)
             (format t "~%"))
    (1+ (length visible-matches))))

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
         (texts (history-kit:history-entry-texts entries)))
    (render-search-results-below-prompt
     query texts (input-state-search-index *input-state*))))
