;;; History-search mode transitions for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defstruct (history-search-edit
            (:constructor %make-history-search-edit (&key kind text delta)))
  kind
  text
  delta)

(defstruct (history-search-query-insertion
            (:constructor %make-history-search-query-insertion
                (&key query accepted-text ignored-p))
            (:conc-name %history-search-query-insertion-))
  (query "" :type string :read-only t)
  (accepted-text "" :type string :read-only t)
  (ignored-p nil :type boolean :read-only t))

(defun history-search-query-insertion-query (insertion)
  (%history-search-query-insertion-query insertion))

(defun history-search-query-insertion-accepted-text (insertion)
  (%history-search-query-insertion-accepted-text insertion))

(defun history-search-query-insertion-ignored-p (insertion)
  (%history-search-query-insertion-ignored-p insertion))

(defun make-history-search-query-edit (text)
  (%make-history-search-edit :kind :query :text text))

(defun make-history-search-selection-edit (delta)
  (%make-history-search-edit :kind :selection :delta delta))

(defun make-history-search-backspace-edit ()
  (%make-history-search-edit :kind :backspace))

(defun history-search-query-insertion-for-text (query text)
  (let ((remaining (- +max-input-buffer-size+ (length query))))
    (if (or (not (stringp text))
            (zerop (length text))
            (<= remaining 0))
        (%make-history-search-query-insertion
         :query query
         :accepted-text ""
         :ignored-p t)
        (let ((accepted-text (if (> (length text) remaining)
                                 (subseq text 0 remaining)
                                 text)))
          (%make-history-search-query-insertion
           :query (concatenate 'string query accepted-text)
           :accepted-text accepted-text
           :ignored-p nil)))))

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

(defun commit-history-search-edit (state edit)
  (with-normalized-cleared-completion-state (state state)
    (ecase (history-search-edit-kind edit)
      (:query
       (let ((insertion
               (history-search-query-insertion-for-text
                (input-state-search-query state)
                (history-search-edit-text edit))))
         (if (history-search-query-insertion-ignored-p insertion)
             (values state :none)
             (%history-search-update
              state
              :search-query (history-search-query-insertion-query insertion)
              :search-index 0))))
      (:selection
       (%history-search-update
        state
        :search-index (+ (input-state-search-index state)
                         (history-search-edit-delta edit))))
      (:backspace
       (let ((query (input-state-search-query state)))
         (if (zerop (length query))
             (%history-search-abort state)
             (%history-search-update
              state
              :search-query (subseq query 0 (1- (length query)))
              :search-index 0)))))))

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
  (commit-history-search-edit state (make-history-search-query-edit text)))

(defun %move-history-search-selection (state delta)
  (commit-history-search-edit state (make-history-search-selection-edit delta)))

(defun %backspace-history-search-query (state)
  (commit-history-search-edit state (make-history-search-backspace-edit)))

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
