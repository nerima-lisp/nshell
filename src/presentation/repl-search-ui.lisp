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
      (:proposal (push (list " [proposal]" :prompt-assistant) badges))
      (:agent (push (list " [agent]" :prompt-assistant) badges)))
    (let ((exit-code (getf metadata :exit-code)))
      (when (and (integerp exit-code) (not (zerop exit-code)))
        (push (list (format nil " [exit ~d]" exit-code) :prompt-error) badges)))
    (nreverse badges)))

(defun %search-header-text (query count)
  (format nil "~a | filters: status:failed status:success exit:N cwd:PATH origin:typed|proposal|agent"
          (if (zerop count)
              (format nil "history: ~a  (no matches)" query)
              (format nil "history: ~a  (~d matches)" query count))))

(defun %search-result-row (match query selected-p width theme)
  (let* ((metadata (%search-result-metadata match))
         (text (getf metadata :text))
         (marker (%search-result-marker selected-p))
         (badges (%search-result-badges metadata))
         (badge-text (mapcar #'first badges))
         (badge-width (reduce #'+ badge-text :key #'%string-visible-width :initial-value 0))
         (text-width (max 0 (- width (%string-visible-width marker) badge-width)))
         (visible-text (%truncate-string-to-width text text-width))
         (visible (concatenate 'string marker visible-text
                               (if badge-text
                                   (apply #'concatenate 'string badge-text)
                                   "")))
         (text-visible (concatenate 'string marker visible-text)))
    (if selected-p
        (progn
          (%write-styled text-visible :completion-selected theme)
          (dolist (badge badges)
            (%write-styled (first badge) (second badge) theme)))
        (let* ((marker-length (length marker))
               (match-start (history-search-match-start visible-text query))
               (row-start (and match-start (+ marker-length match-start)))
               (row-end (and row-start
                             (min (+ row-start (length query))
                                  (+ marker-length (length visible-text))))))
          (if (and row-start row-end (> row-end row-start))
              (progn
                (write-string (subseq text-visible 0 row-start))
                (%write-styled (subseq visible row-start row-end) :search-match theme)
                (write-string (subseq text-visible row-end)))
              (write-string text-visible))
          (dolist (badge badges)
            (%write-styled (first badge) (second badge) theme))))))

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
    (%write-styled
     (%truncate-string-to-width (%search-header-text query count)
                                terminal-width)
     :comment theme)
    (format t "~%")
    (loop for match in visible-matches
          for index from 0
          do (%search-result-row match query (eql index selected-index)
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
         (matches (mapcar (lambda (entry)
                            (list :text (history-kit:history-entry-text entry)
                                  :exit-code (history-kit:history-entry-exit-code entry)
                                  :origin
                                  (nshell.infrastructure.persistence::history-record-origin
                                   (nshell.infrastructure.persistence::history-record-for-entry
                                    *history* entry))))
                          entries)))
    (render-search-results-below-prompt
     query matches (input-state-search-index *input-state*))))
