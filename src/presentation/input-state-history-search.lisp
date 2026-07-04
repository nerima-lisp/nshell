;;; History-search mode transitions for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defstruct (history-search-edit-plan
            (:constructor %make-history-search-edit-plan (&key kind text delta))
            (:conc-name %history-search-edit-plan-))
  (kind :query :read-only t)
  (text "" :read-only t)
  (delta 0 :read-only t))

(defstruct (history-search-edit
            (:constructor %make-history-search-edit (plan))
            (:conc-name %history-search-edit-))
  (plan (error "PLAN is required.") :read-only t))

(defstruct (history-search-query-insertion
            (:constructor %make-history-search-query-insertion
                (&key query accepted-text ignored-p))
            (:conc-name %history-search-query-insertion-))
  (query "" :type string :read-only t)
  (accepted-text "" :type string :read-only t)
  (ignored-p nil :type boolean :read-only t))

(defstruct (history-search-transition
            (:constructor %make-history-search-transition (state output))
            (:conc-name %history-search-transition-))
  (state nil :read-only t)
  (output :none :type symbol :read-only t))

(defstruct (history-search-key-command
            (:constructor %make-history-search-key-command
                (&key kind text delta output))
            (:conc-name %history-search-key-command-))
  (kind :none :type symbol :read-only t)
  (text "" :type string :read-only t)
  (delta 0 :type integer :read-only t)
  (output :none :type symbol :read-only t))

(defun history-search-query-insertion-query (insertion)
  (%history-search-query-insertion-query insertion))

(defun history-search-query-insertion-accepted-text (insertion)
  (%history-search-query-insertion-accepted-text insertion))

(defun history-search-query-insertion-ignored-p (insertion)
  (%history-search-query-insertion-ignored-p insertion))

(defun history-search-transition-state (transition)
  (%history-search-transition-state transition))

(defun history-search-transition-output (transition)
  (%history-search-transition-output transition))

(defun history-search-transition (state output)
  (%make-history-search-transition state output))

(defun commit-history-search-transition (transition)
  (values (history-search-transition-state transition)
          (history-search-transition-output transition)))

(defun history-search-key-command-kind (command)
  (%history-search-key-command-kind command))

(defun history-search-key-command-text (command)
  (%history-search-key-command-text command))

(defun history-search-key-command-delta (command)
  (%history-search-key-command-delta command))

(defun history-search-key-command-output (command)
  (%history-search-key-command-output command))

(defun history-search-edit-plan (edit)
  (%history-search-edit-plan edit))

(defun history-search-edit-plan-kind (plan)
  (%history-search-edit-plan-kind plan))

(defun history-search-edit-plan-text (plan)
  (%history-search-edit-plan-text plan))

(defun history-search-edit-plan-delta (plan)
  (%history-search-edit-plan-delta plan))

(defun make-history-search-query-edit (text)
  (%make-history-search-edit
   (%make-history-search-edit-plan :kind :query :text text)))

(defun make-history-search-selection-edit (delta)
  (%make-history-search-edit
   (%make-history-search-edit-plan :kind :selection :delta delta)))

(defun make-history-search-backspace-edit ()
  (%make-history-search-edit
   (%make-history-search-edit-plan :kind :backspace)))

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
  (let ((plan (history-search-edit-plan edit)))
    (with-normalized-cleared-completion-state (state state)
      (ecase (history-search-edit-plan-kind plan)
        (:query
         (let ((insertion
                 (history-search-query-insertion-for-text
                  (input-state-search-query state)
                  (history-search-edit-plan-text plan))))
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
                           (history-search-edit-plan-delta plan))))
        (:backspace
         (let ((query (input-state-search-query state)))
           (if (zerop (length query))
               (%history-search-abort state)
               (%history-search-update
                state
                :search-query (subseq query 0 (1- (length query)))
                :search-index 0))))))))

(defun %history-search-finished-state (state)
  (copy-input-state-with
   (clear-history-search-session-state state)
   :mode :insert))

(defun %history-search-cancelled-state (state)
  (copy-input-state-with
   (clear-history-search-session-state
    (%history-search-original-state state))
   :mode :insert))

(defun history-search-finished-transition (state output)
  (history-search-transition (%history-search-finished-state state) output))

(defun history-search-cancelled-transition (state)
  (history-search-transition (%history-search-cancelled-state state)
                             :suggest-update))

(defun %history-search-finish (state &optional (output :suggest-update))
  (commit-history-search-transition
   (history-search-finished-transition state output)))

(defun %history-search-abort (state)
  (commit-history-search-transition
   (history-search-cancelled-transition state)))

(defun %update-history-search-query (state text)
  (commit-history-search-edit state (make-history-search-query-edit text)))

(defun %move-history-search-selection (state delta)
  (commit-history-search-edit state (make-history-search-selection-edit delta)))

(defun %backspace-history-search-query (state)
  (commit-history-search-edit state (make-history-search-backspace-edit)))

(defun %history-search-key-event-paste-text (key-event)
  (let ((text (getf (nshell.domain.input:key-event-data key-event)
                    :text)))
    (if (stringp text) text "")))

(defun history-search-key-command-for-event (key-event)
  (case (nshell.domain.input:key-event-type key-event)
    (:char
     (let ((ch (nshell.domain.input:key-event-char key-event)))
       (if ch
           (%make-history-search-key-command :kind :query :text (string ch))
           (%make-history-search-key-command :kind :none))))
    (:paste
     (%make-history-search-key-command
      :kind :query
      :text (%history-search-key-event-paste-text key-event)))
    (:backspace
     (%make-history-search-key-command :kind :backspace))
    ((:ctrl-r :up :ctrl-p)
     (%make-history-search-key-command :kind :selection :delta 1))
    ((:ctrl-s :down :ctrl-n)
     (%make-history-search-key-command :kind :selection :delta -1))
    (:enter
     (%make-history-search-key-command :kind :finish :output :execute))
    ((:right :ctrl-f)
     (%make-history-search-key-command :kind :finish :output :suggest-update))
    ((:escape :ctrl-g)
     (%make-history-search-key-command :kind :abort))
    (:ctrl-l
     (%make-history-search-key-command :kind :output :output :clear-screen))
    (:ctrl-c
     (%make-history-search-key-command :kind :clear))
    (otherwise
     (%make-history-search-key-command :kind :output :output :redraw))))

(defun commit-history-search-key-command (state command)
  (ecase (history-search-key-command-kind command)
    (:query
     (%update-history-search-query
      state
      (history-search-key-command-text command)))
    (:selection
     (%move-history-search-selection
      state
      (history-search-key-command-delta command)))
    (:backspace
     (%backspace-history-search-query state))
    (:finish
     (%history-search-finish state
                             (history-search-key-command-output command)))
    (:abort
     (%history-search-abort state))
    (:clear
     (clear-input-state state))
    (:output
     (values state (history-search-key-command-output command)))
    (:none
     (values state :none))))

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
  (commit-history-search-key-command
   state
   (history-search-key-command-for-event key-event)))
