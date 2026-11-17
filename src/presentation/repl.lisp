;;; nshell REPL - CPS-based interactive shell loop
;;; fish-inspired UX with trampoline-driven continuations
(in-package #:nshell.presentation)

(defun %render-prompt-after-terminal-resize () (clear-rendered-completions) (let ((*preserve-transient-panel-on-next-prompt-p* t)) (render-prompt-cont)))

(defun %read-key-event-for-current-mode (interrupt-predicate
                                         &optional idle-predicate)
  "Read keys with vi Escape handling whenever a vi editing mode is active.
IDLE-PREDICATE, when given, is polled only while no key is pending."
  (let ((vi-mode-p
          (and *vi-mode-enabled*
               *input-state*
               (member (input-state-mode *input-state*)
                       '(:insert :vi-command :vi-d :vi-c :vi-visual)
                       :test #'eq))))
    (cond
      ((and vi-mode-p idle-predicate)
       (nshell.infrastructure.terminal:read-key-event
        :interrupt-predicate interrupt-predicate
        :idle-predicate idle-predicate
        :vi-mode-p t))
      (vi-mode-p
       (nshell.infrastructure.terminal:read-key-event
        :interrupt-predicate interrupt-predicate
        :vi-mode-p t))
      (idle-predicate
       (nshell.infrastructure.terminal:read-key-event
        :interrupt-predicate interrupt-predicate
        :idle-predicate idle-predicate))
      (t
       (nshell.infrastructure.terminal:read-key-event
        :interrupt-predicate interrupt-predicate)))))

(defun %assistant-repeat-cancel-event-p (event)
  (let ((last-cancel-at *assistant-last-cancel-at*)
        (now (boundary-monotonic)))
    (and (nshell.domain.input:key-event-p event)
         (eq :ctrl-c (nshell.domain.input:key-event-type event))
         last-cancel-at
         (<= 0 (- now last-cancel-at) +assistant-cancel-window-ticks+))))

(defun %transient-panel-expand-event-p (event)
  (and (transient-panel-displayed-p)
       (nshell.domain.input:key-event-p event)
       (eq :char (nshell.domain.input:key-event-type event))
       (char= #\v (nshell.domain.input:key-event-char event))))

(defun %process-failure-explain-event (event)
  (setf *failure-explain-available-p* nil)
  (if (eq :ctrl-right-bracket
          (nshell.domain.input:key-event-type event))
      (progn
        (clear-rendered-transient-panel)
        (setf *assistant-request-kind* :explain
              *assistant-explain-candidates* nil
              *assistant-explain-candidate-index* 0
              *assistant-command-approval* nil
              *input-state*
                (copy-input-state-with *input-state* :mode :ask-waiting))
        (process-output-event :ask-submit))
      (progn
        (clear-rendered-transient-panel)
        (setf *assistant-request-kind* nil)
        (multiple-value-bind (new-state output-event)
            (reduce-input-state *input-state* event)
          (setf *input-state* new-state)
          (process-output-event output-event)))))

(defun %process-command-not-found-fallback-event (event)
  (let ((text *command-not-found-fallback-text*))
    (setf *command-not-found-fallback-text* nil
          *command-not-found-command* nil
          *failure-explain-available-p* nil
          *preserve-transient-panel-on-next-prompt-p* nil
          *transient-panel-content* nil)
    (if (eq :ctrl-right-bracket
            (nshell.domain.input:key-event-type event))
        (progn
          (clear-rendered-transient-panel)
          (setf *assistant-command-approval* nil
                *assistant-request-kind* :ask
                *input-state*
                  (copy-input-state-with
                   (make-repl-input-state :buffer text)
                   :mode :ask-waiting))
          (process-output-event :ask-submit))
        (progn
          (clear-rendered-transient-panel)
          (setf *input-state* (make-repl-input-state))
          (multiple-value-bind (new-state output-event)
              (reduce-input-state *input-state* event)
            (setf *input-state* new-state)
            (process-output-event output-event))))))

(defun %history-search-replacement-p (state-before state-after)
  "True when STATE-AFTER ended a history search on a recalled entry."
  (and (eq :search (input-state-mode state-before))
       (not (eq :search (input-state-mode state-after)))
       (not (string= (input-state-buffer state-after)
                     (input-state-search-original-buffer state-before)))))

(defun %process-input-event (event)
  (let ((input-state-before *input-state*))
    (call-with-crash-capture
     (lambda ()
          (when (%suggestion-acceptance-key-event-p event)
            (%await-current-suggestion-before-acceptance))
          (multiple-value-bind (new-state output-event)
              (reduce-input-state *input-state* event)
            ;; A pending result answers the old buffer, cursor and
            ;; suggestion; :SUGGEST-UPDATE schedules a new request instead.
            (when (and (not (eq output-event :suggest-update))
                       (or output-event
                           (not (string= (input-state-buffer *input-state*)
                                         (input-state-buffer new-state)))
                           (/= (input-state-cursor-pos *input-state*)
                               (input-state-cursor-pos new-state))
                           (not (eq (input-state-suggestion *input-state*)
                                    (input-state-suggestion new-state)))))
              (%invalidate-current-input-suggestion))
            ;; A recalled history entry carries the origin it was run with.
            (when (%history-search-replacement-p *input-state* new-state)
              (setf new-state
                    (copy-input-state-with
                     new-state
                     :proposal-origin (%history-text-proposal-origin-p
                                       (input-state-buffer new-state)))))
            ;; An approval belongs to one exact text; any other line drops it.
            (let ((approval *assistant-command-approval*))
              (when (and approval
                         (not (string= (car approval)
                                       (input-state-buffer new-state))))
                (setf *assistant-command-approval* nil)))
            (progn
              (when (eq :ctrl-c
                        (nshell.domain.input:key-event-type event))
                (setf *osc133-state* :none))
              (setf *assistant-last-cancel-at* nil
                    *input-state* new-state))
            (process-output-event output-event)))
     (lambda (crash)
       (setf *input-state* input-state-before)
       (let* ((end-session-p nil)
              (continuation
                (with-cleared-rendered-completions-and-reset-prompt-cont
                  (if (%crash-storage-p crash)
                      (format t "~%nshell: storage exhausted; input was preserved~%")
                      (format t "~%nshell: input processing failed; input was preserved~%"))
                  (%record-crash-log crash *standard-output*)
                  (setf end-session-p (%note-interactive-crash crash)))))
         (if end-session-p
             (%end-session-after-crash)
             continuation))))))

(defun %handle-pending-shell-termination ()
  (let ((status (nshell.infrastructure.acl:consume-shell-termination-status)))
    (when status
      (when (= status (+ 128 sb-unix:sighup))
        (maphash
         (lambda (job-id entry)
           (let* ((processes (cond
                               ((null entry) nil)
                               ((listp entry) entry)
                               (t (list entry))))
                  (job (nshell.domain.job-control:monitor-find-job
                        nshell.application:*job-monitor*
                        job-id))
                  (pgid (and job
                             (nshell.domain.execution:job-control-pgid job))))
             (when (and pgid
                        (not (and (integerp nshell.application:*shell-pgid*)
                                  (= pgid nshell.application:*shell-pgid*)))
                        (some (function nshell.infrastructure.acl:process-alive-p)
                              processes))
               (ignore-errors
                 (nshell.infrastructure.acl:kill-process (- pgid) :sighup)))))
         *proc-registry*))
      (setf *last-exit-code* status
            *running* nil)
      +repl-exit+)))

(defun read-key-cont ()
  (cond
    ((not *running*)
     +repl-exit+)
    ((nshell.infrastructure.acl:consume-terminal-resize-p)
     (lambda () (%render-prompt-after-terminal-resize)))
    (t
     (let* ((raw-event
              (%read-key-event-for-current-mode
               (lambda ()
                 (or (%handle-pending-shell-termination)
                     (when (nshell.infrastructure.acl:consume-terminal-resize-p)
                       (nshell.domain.input:make-key-event
                        :ignore nil nil (list :terminal-resize t)))
                     (when (nshell.infrastructure.acl:consume-sigint-received-p)
                       t)
                     (when (nshell.infrastructure.acl:consume-git-status-update-p)
                       (nshell.domain.input:make-key-event
                        :ignore nil nil (list :git-status-update t)))
                     (%poll-assistant-model-event)))
               (and *interactive-terminal-installed-p*
                    *suggestion-worker-state*
                    #'%poll-suggestion-worker-event)))
            (event (unless (nshell.feature.assistant:assistant-model-event-p raw-event) raw-event)))
       (cond
         ((not *running*)
          +repl-exit+)
         ((nshell.feature.assistant:assistant-model-event-p raw-event)
          (lambda ()
            (when (eql *assistant-turn-generation*
                       (nshell.feature.assistant:assistant-model-event-generation
                        raw-event))
              (setf *last-assistant-model-event* raw-event)
              (when (functionp *assistant-model-event-handler*)
                (funcall *assistant-model-event-handler* raw-event)))
            (read-key-cont)))
         ((and event
               (eq :ignore (nshell.domain.input:key-event-type event)))
          (cond
            ((getf (nshell.domain.input:key-event-data event) :terminal-resize)
             (lambda () (%render-prompt-after-terminal-resize)))
            ((getf (nshell.domain.input:key-event-data event) :git-status-update)
             (lambda ()
               (let ((*preserve-transient-panel-on-next-prompt-p* t))
                 (render-prompt-cont))))
            ((getf (nshell.domain.input:key-event-data event)
                   :suggestion-worker-result)
             (lambda ()
               (if (%apply-suggestion-worker-result
                    (getf (nshell.domain.input:key-event-data event)
                          :suggestion-worker-result))
                   (let ((*preserve-transient-panel-on-next-prompt-p* t))
                     (render-prompt-cont))
                   (read-key-cont))))
            (t (lambda () (read-key-cont)))))
         ((and event *command-not-found-fallback-text*)
          (lambda () (%process-command-not-found-fallback-event event)))
         ((and event (%transient-panel-expand-event-p event))
          (lambda ()
            (commit-transient-panel-to-scrollback)
            (reset-rendered-prompt-state)
            (render-prompt-cont)))
         ((and event *failure-explain-available-p*)
          (lambda () (%process-failure-explain-event event)))
         ((and event *assistant-explain-candidates*)
          (lambda () (%process-explain-panel-event event)))
         ((and event
               (eq *assistant-request-kind* :agent)
               (functionp *assistant-model-event-handler*))
          (lambda ()
            (if (eq :ctrl-c (nshell.domain.input:key-event-type event))
                (process-output-event :ask-cancel-turn)
                (read-key-cont))))
         ((and event *agent-session*)
          (lambda () (%process-agent-panel-event event)))
         ((%assistant-repeat-cancel-event-p event)
          (lambda () (process-output-event :ask-cancel-turn)))
         (event
          (lambda () (%process-input-event event)))
         ((nshell.infrastructure.acl:consume-terminal-resize-p)
          (lambda () (%render-prompt-after-terminal-resize)))
         (t
          (setf *running* nil)
          +repl-exit+))))))


;; REPL Entry
(defun run-repl (&key (load-config-p t) config-path (history-p t) private-p
                      greeting-p)
  "Run the interactive REPL and return the process exit code.

LOAD-CONFIG-P and CONFIG-PATH control startup configuration. HISTORY-P controls
history reads and writes. PRIVATE-P prevents this session's commands and
assistant state from being written. When HISTORY-P is true, existing history
remains available in private mode.

INSTALL-INTERACTIVE-TERMINAL runs inside the UNWIND-PROTECT because it changes
the process group, signal handlers, terminal mode, and ANSI modes. If setup
fails part-way through, the cleanup must still restore that state; otherwise
a later shell can inherit SGR mouse reporting that was active when nshell started.

Setup is not guarded by crash recovery: a failure there ends the session as
before. Every later trampoline step is. A --safe restart the user accepted after
repeated crashes happens only after the cleanup has restored the terminal."
  (let ((*history-loading-enabled-p* history-p)
        (*history-persistence-enabled-p* (and history-p (not private-p)))
        (nshell.infrastructure.persistence:*history-file-mutations-enabled-p*
         (and history-p (not private-p)))
        (*history-seen-command-texts* (make-hash-table :test #'equal))
        (*crash-streak* nil)
        (*safe-reexec-requested-p* nil))
    (initialize-repl-state
     :load-config-p load-config-p
     :config-path config-path
     :history-p history-p
     :private-p private-p)
    (when greeting-p
      (print-session-greeting))
    (let ((exit-code
            (unwind-protect
                 (progn
                   (with-cps-trampoline
                     (if (setf *interactive-terminal-installed-p*
                               (install-interactive-terminal))
                         (progn
                           (%apply-east-asian-ambiguous-width)
                           (funcall (%guard-repl-continuation
                                     (lambda () (render-prompt-cont)))))
                         ;; Raw mode is a precondition for the line editor and
                         ;; could not be entered; INSTALL-INTERACTIVE-TERMINAL
                         ;; has already said so on stderr. Running the editor
                         ;; against a cooked terminal anyway is the one outcome
                         ;; worth avoiding, so end the session instead.
                         (progn
                           (setf *last-exit-code* 1)
                           +repl-exit+)))
                   *last-exit-code*)
              (setf *interactive-terminal-installed-p* nil)
              (unwind-protect
                   (unwind-protect
                        (ignore-errors (nshell.feature.assistant:assistant-model-stop))
                     (restore-interactive-terminal))
                (unwind-protect
                     (%stop-suggestion-worker)
                  (%completion-help-drain-workers)))
              (format t "Goodbye!~%"))))
      (if *safe-reexec-requested-p*
          (%reexec-with-safe-mode)
          exit-code))))
