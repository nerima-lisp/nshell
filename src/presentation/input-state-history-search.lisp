;;; History-search mode transitions for the pure REPL input reducer.

(in-package #:nshell.presentation)

(define-value-struct %history-search-edit-plan
    ((kind :query)
     (text "")
     (delta 0))
  :keyword-constructor t)

(define-value-struct %history-search-edit
    ((plan (error "PLAN is required."))))

(define-value-struct %history-search-query-insertion
    ((query "" :type string)
     (accepted-text "" :type string)
     (ignored-p nil :type boolean))
  :keyword-constructor t)

(define-value-struct %history-search-transition
    ((state nil)
     (output :none :type symbol)))

(define-value-struct %history-search-key-command
    ((kind :none :type symbol)
     (text "" :type string)
     (delta 0 :type integer)
     (output :none :type symbol))
  :keyword-constructor t)

(defun history-search-transition (state output)
  (%make-history-search-transition state output))

(defun commit-history-search-transition (transition)
  (values (history-search-transition-state transition)
          (history-search-transition-output transition)))

(defmacro define-history-search-edit (name lambda-list kind &body initargs)
  `(defun ,name ,lambda-list
     (%make-history-search-edit
      (%make-history-search-edit-plan :kind ,kind ,@initargs))))

(define-history-search-edit make-history-search-query-edit
    (text) :query :text text)
(define-history-search-edit make-history-search-selection-edit
    (delta) :selection :delta delta)
(define-history-search-edit make-history-search-backspace-edit
    () :backspace :delta 0)

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

(defun %commit-history-search-query-edit (state plan)
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

(defun %commit-history-search-selection-edit (state plan)
  (%history-search-update
   state
   :search-index (+ (input-state-search-index state)
                    (history-search-edit-plan-delta plan))))

(defun %commit-history-search-backspace-edit (state)
  (let ((query (input-state-search-query state)))
    (if (zerop (length query))
        (%history-search-abort state)
        (%history-search-update
         state
         :search-query (subseq query 0 (1- (length query)))
         :search-index 0))))

(defun commit-history-search-edit (state edit)
  (let ((plan (history-search-edit-plan edit)))
    (with-normalized-cleared-completion-state (state state)
      (ecase (history-search-edit-plan-kind plan)
        (:query
         (%commit-history-search-query-edit state plan))
        (:selection
         (%commit-history-search-selection-edit state plan))
        (:backspace
         (%commit-history-search-backspace-edit state))))))

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
