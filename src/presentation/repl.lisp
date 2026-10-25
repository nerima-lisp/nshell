;;; nshell REPL - CPS-based interactive shell loop
;;; fish-inspired UX with trampoline-driven continuations
(in-package #:nshell.presentation)

(defun %render-prompt-after-terminal-resize ()
  (when *rerun-confirmation-pending-p*
    (setf *rerun-confirmation-pending-p* nil
          *rerun-command-assessment* nil)
    (clear-rendered-transient-panel))
  (clear-rendered-completions)
  (let ((*preserve-transient-panel-on-next-prompt-p* t))
    (render-prompt-cont)))

(defun %read-key-event-for-current-mode (interrupt-predicate)
  "Read keys with vi Escape handling whenever a vi editing mode is active."
  (let ((vi-mode-p
          (and *vi-mode-enabled*
               *input-state*
               (member (input-state-mode *input-state*)
                       '(:insert :vi-command :vi-d :vi-c :vi-visual)
                       :test #'eq))))
    (if vi-mode-p
        (nshell.infrastructure.terminal:read-key-event
         :interrupt-predicate interrupt-predicate
         :vi-mode-p t)
        (nshell.infrastructure.terminal:read-key-event
         :interrupt-predicate interrupt-predicate))))

(defun %assistant-repeat-cancel-event-p (event)
  (let ((last-cancel-at *assistant-last-cancel-at*)
        (now (boundary-monotonic)))
    (and (nshell.domain.input:key-event-p event)
         (eq :ctrl-c (nshell.domain.input:key-event-type event))
         last-cancel-at
         (<= 0 (- now last-cancel-at) +assistant-cancel-window-ticks+))))

(defun %map-rendered-mouse-event-to-buffer (event)
  (let ((data (and *input-state*
                   (nshell.domain.input:key-event-p event)
                   (nshell.domain.input:key-event-data event))))
    (if (and data
             (eq :sgr (getf data :protocol))
             (member (getf data :event) '(:press :drag :release))
             (null (getf data :buffer-index)))
        (let ((index
                (%rendered-buffer-index-at-position
                 (input-state-buffer *input-state*)
                 (getf data :row)
                 (getf data :column)
                 *prompt-rendered-prompt-width*
                 :terminal-width *prompt-rendered-terminal-width*
                 :origin-row *prompt-rendered-origin-row*
                 :origin-column *prompt-rendered-origin-column*)))
          (if (integerp index)
              (nshell.domain.input:make-key-event
               :mouse
               nil
               (nshell.domain.input:key-event-number event)
               (list* :buffer-index index data))
              event))
        event)))

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
              *assistant-command-origin* :typed
              *assistant-command-confirmed-p* nil
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
          (setf *assistant-command-origin* :typed
                *assistant-command-confirmed-p* nil
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

(defun %process-input-event (event)
  (let ((input-state-before *input-state*))
    (handler-case
        (progn
          (when (and *rerun-confirmation-pending-p*
                     (nshell.infrastructure.acl:consume-terminal-resize-p))
            (return-from %process-input-event
              (%render-prompt-after-terminal-resize)))
          (multiple-value-bind (new-state output-event)
              (reduce-input-state *input-state* event)
            (when (and (eq *assistant-command-origin* :proposal)
                       (not (string= (input-state-buffer *input-state*)
                                     (input-state-buffer new-state))))
              (setf *assistant-command-confirmed-p* nil))
            (when (and (not (eq output-event :rerun-last-command))
                       (or *rerun-confirmation-pending-p*
                           *rerun-command-assessment*))
              (setf *rerun-confirmation-pending-p* nil
                    *rerun-command-assessment* nil)
              (clear-rendered-transient-panel))
            (progn
              (when (eq :ctrl-c
                        (nshell.domain.input:key-event-type event))
                (setf *osc133-state* :none))
              (setf *assistant-last-cancel-at* nil
                    *input-state* new-state))
            (process-output-event output-event)))
      (storage-condition ()
        (setf *input-state* input-state-before)
        (with-cleared-rendered-completions-and-reset-prompt-cont
          (format t "~%nshell: storage exhausted; input was preserved~%")))
      (error ()
        (setf *input-state* input-state-before)
        (with-cleared-rendered-completions-and-reset-prompt-cont
          (format t "~%nshell: input processing failed; input was preserved~%"))))))

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
                     (%poll-assistant-model-event)))))
            (event (unless (nshell.feature.assistant:assistant-model-event-p
                            raw-event)
                     (%map-rendered-mouse-event-to-buffer raw-event))))
       (cond
         ((not *running*)
          +repl-exit+)
         ((and *rerun-confirmation-pending-p*
               (nshell.infrastructure.acl:consume-terminal-resize-p))
          (lambda () (%render-prompt-after-terminal-resize)))
         ((nshell.feature.assistant:assistant-model-event-p raw-event)
          (lambda ()
            (when (eql *assistant-turn-generation*
                       (nshell.feature.assistant:assistant-model-event-generation
                        raw-event))
              (setf *last-assistant-model-event* raw-event)
              (when (functionp *assistant-model-event-handler*)
                (funcall *assistant-model-event-handler* raw-event)))
            (read-key-cont)))
         ((and event *rerun-confirmation-pending-p*)
          (lambda () (%process-input-event event)))
         ((and event
               (eq :ignore (nshell.domain.input:key-event-type event))
               (getf (nshell.domain.input:key-event-data event) :terminal-resize))
          (lambda () (%render-prompt-after-terminal-resize)))
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
the next shell could start with SGR mouse reporting still on."
  (let ((*history-loading-enabled-p* history-p)
        (*history-persistence-enabled-p* (and history-p (not private-p)))
        (nshell.infrastructure.persistence:*history-file-mutations-enabled-p*
         (and history-p (not private-p)))
        (*history-seen-command-texts* (make-hash-table :test #'equal)))
    (initialize-repl-state
     :load-config-p load-config-p
     :config-path config-path
     :history-p history-p
     :private-p private-p)
    (when greeting-p
      (print-session-greeting))
    (unwind-protect
        (progn
          (with-cps-trampoline
           (if (setf *interactive-terminal-installed-p*
                     (install-interactive-terminal))
               (progn
                  (%apply-east-asian-ambiguous-width)
                  (render-prompt-cont))
             ;; Raw mode is a precondition for the line editor and could not be
             ;; entered; INSTALL-INTERACTIVE-TERMINAL has already said so on
             ;; stderr. Running the editor against a cooked terminal anyway is the
             ;; one outcome worth avoiding, so end the session instead.
             (progn
               (setf *last-exit-code* 1)
               +repl-exit+)))
          *last-exit-code*)

      (setf *interactive-terminal-installed-p* nil)
      (unwind-protect
          (unwind-protect
              (ignore-errors (nshell.feature.assistant:assistant-model-stop))
            (restore-interactive-terminal))
        (%completion-help-drain-workers))
      (format t "Goodbye!~%"))))
