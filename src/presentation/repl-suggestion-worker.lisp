(in-package #:nshell.presentation)

;;; Autosuggestion runs on one worker thread so a key redraw never waits for
;;; history search, KB proofs, PATH scans or git listings. The main thread owns
;;; *INPUT-STATE*; it hands the worker a request holding private snapshots of
;;; every mutable table the computation reads, and applies a result only while
;;; its generation and text still match the current buffer.

(defstruct (%suggestion-worker-request
            (:constructor %make-suggestion-worker-request
                (&key generation text history knowledge-base path filesystem
                      alias-table function-table environment-arguments)))
  generation
  text
  history
  knowledge-base
  path
  filesystem
  alias-table
  function-table
  environment-arguments)

(defstruct (%suggestion-worker-result
            (:constructor %make-suggestion-worker-result
                (&key generation text suggestion condition)))
  generation
  text
  suggestion
  condition)

(defstruct (%suggestion-worker-state
            (:constructor %make-suggestion-worker-state ()))
  (mutex (sb-thread:make-mutex :name "nshell suggestion worker"))
  (semaphore (sb-thread:make-semaphore :count 0))
  thread
  (generation 0)
  (status :idle)
  pending-request
  working-request
  result
  (shutdown-p nil))

(defvar *suggestion-worker-state* nil)
(defvar *suggestion-history-source* nil)
(defvar *suggestion-history-snapshot* nil)

(defvar *suggestion-knowledge-base-snapshot* nil
  "NIL or (SOURCE FACTS RULES SNAPSHOT) for the last knowledge base handed to
the worker.")

(defvar *suggestion-table-snapshots* nil
  "Alist from a source table to (ENTRIES . COPY) for the alias and function
tables last handed to the worker. ENTRIES is read only by the main thread.")

(defvar *suggestion-shown-full-text* nil
  "Buffer text followed by the suggestion currently shown, or NIL.")

(defparameter *suggestion-acceptance-wait-seconds* 0.5
  "Longest time an acceptance key waits for an in-flight suggestion.")

(defun %copy-suggestion-table (table)
  (when (hash-table-p table)
    (let ((copy (make-hash-table :test (hash-table-test table))))
      (maphash
       (lambda (key value)
         (setf (gethash key copy)
               (if (hash-table-p value)
                   (%copy-suggestion-table value)
                   value)))
       table)
      copy)))

(defun %suggestion-table-entries (table)
  (let ((entries nil))
    (maphash (lambda (key value) (push (cons key value) entries)) table)
    entries))

(defun %suggestion-table-unchanged-p (table entries)
  (and (= (hash-table-count table) (length entries))
       (every (lambda (entry)
                (multiple-value-bind (value foundp) (gethash (car entry) table)
                  (and foundp (eq value (cdr entry)))))
              entries)))

(defun %snapshot-suggestion-table (table)
  "Return a worker-private copy of TABLE, reusing the previous copy while every
key still maps to the same value."
  (when (hash-table-p table)
    (let ((cached (cdr (assoc table *suggestion-table-snapshots* :test #'eq))))
      (if (and cached (%suggestion-table-unchanged-p table (car cached)))
          (cdr cached)
          (let ((copy (%copy-suggestion-table table)))
            (setf *suggestion-table-snapshots*
                  (acons table
                         (cons (%suggestion-table-entries table) copy)
                         (remove table *suggestion-table-snapshots*
                                 :key #'car :test #'eq)))
            copy)))))

(defun %snapshot-suggestion-knowledge-base (knowledge-base)
  "Return a worker-private copy of KNOWLEDGE-BASE.
Every change to the fact or rule list replaces the list head (PUSH, REMOVE-IF,
SUBSTITUTE), so the previous copy, together with the rulebase the worker
compiled into it, is reused while both heads are unchanged. Description tables
change only next to a fact change, and suggestion text never reads them."
  (when knowledge-base
    (let ((facts (nshell.domain.completion::rule-knowledge-base-facts knowledge-base))
          (rules (nshell.domain.completion::rule-knowledge-base-rules knowledge-base))
          (cached *suggestion-knowledge-base-snapshot*))
      (if (and cached
               (eq knowledge-base (first cached))
               (eq facts (second cached))
               (eq rules (third cached)))
          (fourth cached)
          (let ((snapshot (nshell.domain.completion:make-empty-knowledge-base)))
            (setf (nshell.domain.completion::rule-knowledge-base-facts snapshot)
                  (copy-list facts)
                  (nshell.domain.completion::rule-knowledge-base-rules snapshot)
                  (copy-list rules)
                  (nshell.domain.completion::rule-knowledge-base-%rulebase-cache snapshot)
                  nil
                  (nshell.domain.completion::knowledge-base-command-description-facts
                   snapshot)
                  (%copy-suggestion-table
                   (nshell.domain.completion::knowledge-base-command-description-facts
                    knowledge-base))
                  (nshell.domain.completion::knowledge-base-flag-description-facts
                   snapshot)
                  (%copy-suggestion-table
                   (nshell.domain.completion::knowledge-base-flag-description-facts
                    knowledge-base)))
            (setf *suggestion-knowledge-base-snapshot*
                  (list knowledge-base facts rules snapshot))
            snapshot)))))

(defun %refresh-suggestion-history-snapshot ()
  (let ((history *history*))
    (setf *suggestion-history-source* history
          *suggestion-history-snapshot*
          (when history
            (let ((snapshot
                    (history-kit:make-history
                     :capacity (history-kit:history-capacity history)
                     :duplicate-policy
                     (history-kit:history-duplicate-policy history))))
              (nshell.infrastructure.persistence:history-record-add-batch
               snapshot
               (mapcar
                (lambda (entry)
                  (nshell.infrastructure.persistence:history-record-for-entry
                   history entry))
                (reverse (history-kit:history-entries history))))
              snapshot)))))

(defun %note-suggestion-history-changed ()
  "Rebuild the worker's history copy after *HISTORY* changed. Only an
interactive session uses the worker; elsewhere the copy is dropped so it is
rebuilt on demand."
  (if *interactive-terminal-installed-p*
      (%refresh-suggestion-history-snapshot)
      (setf *suggestion-history-source* nil
            *suggestion-history-snapshot* nil)))

(defun %ensure-suggestion-history-snapshot ()
  (unless (eq *history* *suggestion-history-source*)
    (%refresh-suggestion-history-snapshot))
  (or *suggestion-history-snapshot*
      (history-kit:make-history)))

(defun %make-current-suggestion-request (text)
  (let* ((environment (ensure-environment))
         (path (nshell.domain.environment:env-get environment "PATH")))
    (%make-suggestion-worker-request
     :text (copy-seq text)
     :history (%ensure-suggestion-history-snapshot)
     :knowledge-base (%snapshot-suggestion-knowledge-base *kb*)
     :path (and path (copy-seq path))
     :filesystem *repl-filesystem*
     :alias-table (%snapshot-suggestion-table *aliases*)
     :function-table (%snapshot-suggestion-table *functions*)
     :environment-arguments (repl-completion-environment-arguments))))

(defun %compute-suggestion-worker-request (request)
  ;; SERIOUS-CONDITION, not ERROR: a STORAGE-CONDITION here must become a
  ;; failed result instead of ending the worker with a request still marked
  ;; as in progress.
  (handler-case
      (%make-suggestion-worker-result
       :generation (%suggestion-worker-request-generation request)
       :text (%suggestion-worker-request-text request)
       :suggestion
       (apply #'compute-suggestion
              (%suggestion-worker-request-history request)
              (%suggestion-worker-request-text request)
              :knowledge-base
              (%suggestion-worker-request-knowledge-base request)
              :path (%suggestion-worker-request-path request)
              :filesystem (%suggestion-worker-request-filesystem request)
              :alias-table (%suggestion-worker-request-alias-table request)
              :function-table (%suggestion-worker-request-function-table request)
              (%suggestion-worker-request-environment-arguments request)))
    (serious-condition (condition)
      (%make-suggestion-worker-result
       :generation (%suggestion-worker-request-generation request)
       :text (%suggestion-worker-request-text request)
       :condition condition))))

(defun %suggestion-worker-loop (state)
  (loop
    (sb-thread:wait-on-semaphore
     (%suggestion-worker-state-semaphore state))
    (loop
      (let ((request nil)
            (stopping-p nil))
        (sb-thread:with-mutex
            ((%suggestion-worker-state-mutex state))
          (if (%suggestion-worker-state-shutdown-p state)
              (setf stopping-p t)
              (setf request
                    (%suggestion-worker-state-pending-request state)
                    (%suggestion-worker-state-pending-request state) nil
                    (%suggestion-worker-state-working-request state) request
                    (%suggestion-worker-state-status state)
                    (if request :working :idle))))
        (when stopping-p
          (return-from %suggestion-worker-loop nil))
        (unless request
          (return))
        (let ((result (%compute-suggestion-worker-request request))
              (idle-p nil)
              (stopping-p nil))
          (sb-thread:with-mutex
              ((%suggestion-worker-state-mutex state))
            (setf (%suggestion-worker-state-working-request state) nil)
            (when (and (not (%suggestion-worker-state-shutdown-p state))
                       (= (%suggestion-worker-request-generation request)
                          (%suggestion-worker-state-generation state)))
              (setf (%suggestion-worker-state-result state) result))
            (setf stopping-p (%suggestion-worker-state-shutdown-p state))
            (unless stopping-p
              (if (%suggestion-worker-state-pending-request state)
                  (setf (%suggestion-worker-state-status state) :working)
                  (setf (%suggestion-worker-state-status state) :idle
                        idle-p t))))
          (when stopping-p
            (return-from %suggestion-worker-loop nil))
          (when idle-p
            (return)))))))

(defun %suggestion-worker-alive-p (state)
  (let ((thread (%suggestion-worker-state-thread state)))
    (and thread (sb-thread:thread-alive-p thread))))

(defun %ensure-suggestion-worker ()
  (let ((state (or *suggestion-worker-state*
                   (setf *suggestion-worker-state*
                         (%make-suggestion-worker-state)))))
    (unless (%suggestion-worker-alive-p state)
      ;; A worker that died left its request marked as in progress and its
      ;; status non-idle, so nothing would signal a replacement thread.
      (sb-thread:with-mutex ((%suggestion-worker-state-mutex state))
        (setf (%suggestion-worker-state-working-request state) nil
              (%suggestion-worker-state-status state)
              (if (%suggestion-worker-state-pending-request state)
                  :scheduled
                  :idle)))
      (let ((start-gate (sb-thread:make-semaphore :count 0)))
        (setf (%suggestion-worker-state-thread state)
              (sb-thread:make-thread
               (lambda ()
                 (sb-thread:wait-on-semaphore start-gate)
                 (%suggestion-worker-loop state))
               :name "nshell suggestion worker"))
        (sb-thread:signal-semaphore start-gate)
        (when (%suggestion-worker-state-pending-request state)
          (sb-thread:signal-semaphore
           (%suggestion-worker-state-semaphore state)))))
    state))

(defun %show-suggestion (suggestion)
  (setf (input-state-suggestion *input-state*) suggestion
        *suggestion-shown-full-text*
        (and suggestion
             (concatenate 'string (input-state-buffer *input-state*) suggestion))))

(defun %retained-suggestion (text)
  "The part of the shown suggestion still ahead of TEXT, so typing along the
suggestion keeps it on screen until the worker answers; otherwise NIL."
  (let ((full *suggestion-shown-full-text*))
    (and full
         (not (nshell.domain.parsing:shell-input-blank-p text))
         (< (length text) (length full))
         (string= text full :end2 (length text))
         (subseq full (length text)))))

(defun %schedule-current-input-state-suggestion (&optional text)
  (when (and *input-state*
             (stringp (or text (input-state-buffer *input-state*))))
    (let* ((text (or text (input-state-buffer *input-state*)))
           (state (%ensure-suggestion-worker))
           (request (%make-current-suggestion-request text))
           (signal-p nil)
           (generation nil))
      (setf (input-state-suggestion *input-state*) (%retained-suggestion text))
      (unless (input-state-suggestion *input-state*)
        (setf *suggestion-shown-full-text* nil))
      (sb-thread:with-mutex
          ((%suggestion-worker-state-mutex state))
        (setf generation
              (incf (%suggestion-worker-state-generation state))
              (%suggestion-worker-request-generation request) generation
              (%suggestion-worker-state-pending-request state) request
              (%suggestion-worker-state-result state) nil)
        (when (eq :idle (%suggestion-worker-state-status state))
          (setf (%suggestion-worker-state-status state) :scheduled
                signal-p t)))
      (when signal-p
        (sb-thread:signal-semaphore
         (%suggestion-worker-state-semaphore state)))
      generation)))

(defun %invalidate-current-input-suggestion ()
  (setf *suggestion-shown-full-text* nil)
  (when *suggestion-worker-state*
    (let ((state *suggestion-worker-state*))
      (sb-thread:with-mutex
          ((%suggestion-worker-state-mutex state))
        (incf (%suggestion-worker-state-generation state))
        (setf (%suggestion-worker-state-pending-request state) nil
              (%suggestion-worker-state-result state) nil)
        (when (eq :scheduled (%suggestion-worker-state-status state))
          (setf (%suggestion-worker-state-status state) :idle))))))

(defun %take-suggestion-worker-result ()
  (when *suggestion-worker-state*
    (let ((state *suggestion-worker-state*))
      (sb-thread:with-mutex
          ((%suggestion-worker-state-mutex state))
        (prog1 (%suggestion-worker-state-result state)
          (setf (%suggestion-worker-state-result state) nil))))))

(defun %poll-suggestion-worker-event ()
  (let ((result (%take-suggestion-worker-result)))
    (when result
      (nshell.domain.input:make-key-event
       :ignore nil nil (list :suggestion-worker-result result)))))

(defun %current-suggestion-worker-result-p (result)
  (let ((state *suggestion-worker-state*))
    (and state
         *input-state*
         (eq :insert (input-state-mode *input-state*))
         (string= (%suggestion-worker-result-text result)
                  (input-state-buffer *input-state*))
         (sb-thread:with-mutex
             ((%suggestion-worker-state-mutex state))
           (= (%suggestion-worker-result-generation result)
              (%suggestion-worker-state-generation state))))))

(defun %apply-suggestion-worker-result (result)
  "Show RESULT when it answers the current buffer. Return true when the shown
suggestion changed."
  (when (%current-suggestion-worker-result-p result)
    (if (%suggestion-worker-result-condition result)
        (progn
          (format *error-output*
                  "nshell: suggestion calculation failed; input was preserved~%")
          t)
        (let ((suggestion (%suggestion-worker-result-suggestion result)))
          (unless (equal suggestion (input-state-suggestion *input-state*))
            (%show-suggestion suggestion)
            t)))))

(defun %suggestion-acceptance-key-event-p (event)
  (and *input-state*
       (eq :insert (input-state-mode *input-state*))
       (input-state-at-eol-p *input-state*)
       (member
        (input-dispatch-binding-action-name
         (nshell.domain.input:key-event-type event))
        '(:accept-suggestion
          :move-eol-or-accept-suggestion
          :accept-suggestion-word)
        :test #'eq)))

(defun %await-current-suggestion-before-acceptance ()
  "Wait for the suggestion of the current buffer before an acceptance key.
The wait ends when the result arrives, when no request for the buffer is left,
or after *SUGGESTION-ACCEPTANCE-WAIT-SECONDS*; the key then accepts what is
shown. A dead worker cannot answer, so the suggestion is computed here."
  (let ((state *suggestion-worker-state*))
    (when (and state
               *input-state*
               (eq :insert (input-state-mode *input-state*)))
      (let* ((text (copy-seq (input-state-buffer *input-state*)))
             (deadline (+ (get-internal-real-time)
                          (round (* *suggestion-acceptance-wait-seconds*
                                    internal-time-units-per-second))))
             (generation
               (sb-thread:with-mutex
                   ((%suggestion-worker-state-mutex state))
                 (%suggestion-worker-state-generation state))))
        (flet ((current-request-p (request)
                 (and request
                      (= generation
                         (%suggestion-worker-request-generation request))
                      (string= text
                               (%suggestion-worker-request-text request)))))
          (loop
            (let ((result nil)
                  (request-p nil)
                  (alive-p (%suggestion-worker-alive-p state)))
              (sb-thread:with-mutex
                  ((%suggestion-worker-state-mutex state))
                (setf result (%suggestion-worker-state-result state))
                (when result
                  (setf (%suggestion-worker-state-result state) nil))
                (setf request-p
                      (or (current-request-p
                           (%suggestion-worker-state-working-request state))
                          (current-request-p
                           (%suggestion-worker-state-pending-request state)))))
              (cond
                (result
                 (%apply-suggestion-worker-result result)
                 (return t))
                ((not request-p)
                 (return nil))
                ((not alive-p)
                 (%invalidate-current-input-suggestion)
                 (refresh-current-input-state-suggestion text)
                 (%show-suggestion (input-state-suggestion *input-state*))
                 (return t))
                ((>= (get-internal-real-time) deadline)
                 (return nil))
                (t
                 (sleep 0.001))))))))))

(defun %stop-suggestion-worker ()
  (let ((state *suggestion-worker-state*))
    (when state
      (let ((thread (%suggestion-worker-state-thread state)))
        (sb-thread:with-mutex
            ((%suggestion-worker-state-mutex state))
          (setf (%suggestion-worker-state-shutdown-p state) t
                (%suggestion-worker-state-pending-request state) nil
                (%suggestion-worker-state-result state) nil
                (%suggestion-worker-state-status state) :stopping))
        (when (and thread (sb-thread:thread-alive-p thread))
          (sb-thread:signal-semaphore
           (%suggestion-worker-state-semaphore state))
          (unless (eq thread sb-thread:*current-thread*)
            (sb-thread:join-thread thread :default nil))))
      (setf *suggestion-worker-state* nil))
    (setf *suggestion-history-source* nil
          *suggestion-history-snapshot* nil
          *suggestion-knowledge-base-snapshot* nil
          *suggestion-table-snapshots* nil
          *suggestion-shown-full-text* nil)
    nil))

(defun %request-current-input-state-suggestion (&optional text)
  (if *interactive-terminal-installed-p*
      (%schedule-current-input-state-suggestion text)
      (if text
          (refresh-current-input-state-suggestion text)
          (refresh-current-input-state-suggestion))))
