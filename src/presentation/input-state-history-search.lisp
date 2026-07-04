;;; History-search mode transitions for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defun %history-search-original-state (state)
  (let ((original (input-state-search-original-buffer state)))
    (copy-input-state-clearing-completion
     state
     :buffer original
     :cursor-pos (or (input-state-search-original-cursor state)
                     (length original))
     :search-index (input-state-search-index state))))

(defun %history-search-update (state &rest initargs)
  (values (apply #'copy-input-state-clearing-completion state initargs)
          :search-update))

(defun %history-search-finished-state (state)
  (copy-input-state-with
   (clear-history-search-session-state state)
   :mode :insert))

(defun %history-search-cancelled-state (state)
  (copy-input-state-with
   (clear-history-search-session-state
    (%history-search-original-state state))
   :mode :insert))

(defun %history-search-finish (state &optional (output :suggest-update))
  (values (%history-search-finished-state state) output))

(defun %history-search-abort (state)
  (values (%history-search-cancelled-state state) :suggest-update))

(defun %update-history-search-query (state text)
  (with-normalized-cleared-completion-state (state state)
    (let* ((query (input-state-search-query state))
           (remaining (- +max-input-buffer-size+ (length query))))
      (if (or (not (stringp text)) (zerop (length text)) (<= remaining 0))
          (values state :none)
          (let ((inserted (if (> (length text) remaining)
                              (subseq text 0 remaining)
                              text)))
            (%history-search-update
             state
             :search-query (concatenate 'string query inserted)
             :search-index 0))))))

(defun %move-history-search-selection (state delta)
  (with-normalized-cleared-completion-state (state state)
    (%history-search-update
     state
     :search-index (+ (input-state-search-index state) delta))))

(defun %backspace-history-search-query (state)
  (with-normalized-cleared-completion-state (state state)
    (let ((query (input-state-search-query state)))
      (if (zerop (length query))
          (%history-search-abort state)
          (%history-search-update
           state
           :search-query (subseq query 0 (1- (length query)))
           :search-index 0)))))

(defun %history-search-matched-state (state text)
  (copy-input-state-clearing-completion
   state
   :buffer text
   :cursor-pos (length text)
   :search-index (input-state-search-index state)))

(defun apply-history-search-results-to-input-state (state result-texts)
  "Apply history RESULT-TEXTS to STATE while preserving pure reducer semantics.

  RESULT-TEXTS must be strings, newest first. SEARCH-INDEX selects among them
with wraparound so repeated Ctrl-R can cycle through older matches."
  (with-normalized-cleared-completion-state (state state)
    (let ((matches (remove-if-not #'stringp result-texts)))
      (cond
        ((not (eq (input-state-mode state) :search))
         state)
        (matches
         (let* ((index (mod (input-state-search-index state) (length matches)))
                (text (nth index matches)))
           (%history-search-matched-state state text)))
        (t
         (%history-search-original-state state))))))

(defun reduce-search-input-state (state key-event)
  (case (nshell.domain.input:key-event-type key-event)
    (:char (let ((ch (nshell.domain.input:key-event-char key-event)))
             (if ch
                 (%update-history-search-query state (string ch))
                 (values state :none))))
    (:paste (%update-history-search-query
             state
             (getf (nshell.domain.input:key-event-data key-event)
                   :text)))
    (:backspace (%backspace-history-search-query state))
    ((:ctrl-r :up :ctrl-p) (%move-history-search-selection state 1))
    ((:ctrl-s :down :ctrl-n) (%move-history-search-selection state -1))
    (:enter (%history-search-finish state :execute))
    ((:right :ctrl-f) (%history-search-finish state))
    ((:escape :ctrl-g) (%history-search-abort state))
    (:ctrl-l (values state :clear-screen))
    (:ctrl-c (clear-input-state state))
    (otherwise (values state :redraw))))
