(in-package #:nshell.presentation)

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

(defun %snapshot-suggestion-knowledge-base (knowledge-base)
  (when knowledge-base
    (let ((snapshot (nshell.domain.completion:make-empty-knowledge-base)))
      (setf (nshell.domain.completion::rule-knowledge-base-facts snapshot)
            (copy-list
             (nshell.domain.completion::rule-knowledge-base-facts
              knowledge-base))
            (nshell.domain.completion::rule-knowledge-base-rules snapshot)
            (copy-list
             (nshell.domain.completion::rule-knowledge-base-rules
              knowledge-base))
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
      snapshot)))

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
     :alias-table (%copy-suggestion-table *aliases*)
     :function-table (%copy-suggestion-table *functions*)
     :environment-arguments (repl-completion-environment-arguments))))

(defun %compute-suggestion-worker-request (request)
  (handler-case
      (let ((*nfr05-diagnostic-active-p* nil))
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
                (%suggestion-worker-request-environment-arguments request))))
    (error (condition)
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

(defun %ensure-suggestion-worker ()
  (let ((state (or *suggestion-worker-state*
                   (setf *suggestion-worker-state*
                         (%make-suggestion-worker-state)))))
    (unless (%suggestion-worker-state-thread state)
      (let ((start-gate (sb-thread:make-semaphore :count 0)))
        (setf (%suggestion-worker-state-thread state)
              (sb-thread:make-thread
               (lambda ()
                 (sb-thread:wait-on-semaphore start-gate)
                 (%suggestion-worker-loop state))
               :name "nshell suggestion worker"))
        (sb-thread:signal-semaphore start-gate)))
    state))

(defun %schedule-current-input-state-suggestion (&optional text)
  (when (and *input-state*
             (stringp (or text (input-state-buffer *input-state*))))
    (let* ((state (%ensure-suggestion-worker))
           (request
             (%make-current-suggestion-request
              (or text (input-state-buffer *input-state*))))
           (signal-p nil)
           (generation nil))
      (setf (input-state-suggestion *input-state*) nil)
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
    (when (and result
               (or (%suggestion-worker-result-condition result)
                   (stringp (%suggestion-worker-result-suggestion result))))
      (nshell.domain.input:make-key-event
       :ignore nil nil (list :suggestion-worker-result result)))))

(progn
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
  (defun %suggestion-acceptance-key-event-p (event)
    (and *input-state*
         (eq :insert (input-state-mode *input-state*))
         (input-state-at-eol-p *input-state*)
         (member
          (input-dispatch-binding-action-name
           (nshell.domain.input:key-event-type event))
          (list :accept-suggestion
                :move-eol-or-accept-suggestion
                :accept-suggestion-word)
          :test (function eq))))
  (defun %await-current-suggestion-before-acceptance ()
    (let ((state *suggestion-worker-state*))
      (when (and state
                 *input-state*
                 (eq :insert (input-state-mode *input-state*)))
        (let ((text (copy-seq (input-state-buffer *input-state*)))
              (generation nil))
          (setf generation
                (sb-thread:with-mutex
                    ((%suggestion-worker-state-mutex state))
                  (%suggestion-worker-state-generation state)))
          (labels ((current-request-p (request)
                     (and request
                          (= generation
                             (%suggestion-worker-request-generation request))
                          (string= text
                                   (%suggestion-worker-request-text request)))))
            (loop
              (let ((result nil)
                    (request-p nil))
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
                   (when (%current-suggestion-worker-result-p result)
                     (if (%suggestion-worker-result-condition result)
                         (format *error-output*
                                 "nshell: suggestion calculation failed; input was preserved~%")
                         (setf (input-state-suggestion *input-state*)
                               (%suggestion-worker-result-suggestion result))))
                   (return t))
                  (request-p
                   (sleep 0.001))
                  (t
                   (return nil)))))))))))

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
        (when thread
          (sb-thread:signal-semaphore
           (%suggestion-worker-state-semaphore state))
          (unless (eq thread sb-thread:*current-thread*)
            (sb-thread:join-thread thread))))
      (setf *suggestion-worker-state* nil))
    (setf *suggestion-history-source* nil
          *suggestion-history-snapshot* nil)
    nil))

(defun %request-current-input-state-suggestion (&optional text)
  (if *interactive-terminal-installed-p*
      (%schedule-current-input-state-suggestion text)
      (if text
          (refresh-current-input-state-suggestion text)
          (refresh-current-input-state-suggestion))))
