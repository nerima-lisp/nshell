;;; nshell REPL - CPS-based interactive shell loop
;;; fish-inspired UX with trampoline-driven continuations
(in-package #:nshell.presentation)

(defun %render-prompt-after-terminal-resize ()
  (let ((*preserve-transient-panel-on-next-prompt-p* t))
    (render-prompt-cont)))

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

(defun read-key-cont ()
  (if (nshell.infrastructure.acl:consume-terminal-resize-p)
      (lambda () (%render-prompt-after-terminal-resize))
      (let* ((raw-event
               (nshell.infrastructure.terminal:read-key-event
                :interrupt-predicate
                (lambda ()
                  (or (when (nshell.infrastructure.acl:consume-sigint-received-p)
                        t)
                      (%poll-assistant-model-event)))))
             (event (unless (nshell.feature.assistant:assistant-model-event-p
                              raw-event)
                      (%map-rendered-mouse-event-to-buffer raw-event))))
        (cond
          ((nshell.feature.assistant:assistant-model-event-p raw-event)
           (lambda ()
             (when (eql *assistant-turn-generation*
                        (nshell.feature.assistant:assistant-model-event-generation
                         raw-event))
               (setf *last-assistant-model-event* raw-event)
               (when (functionp *assistant-model-event-handler*)
                 (funcall *assistant-model-event-handler* raw-event)))
             (read-key-cont)))
          ((%assistant-repeat-cancel-event-p event)
           (lambda () (process-output-event :ask-cancel-turn)))
          (event
           (lambda ()
             (setf *assistant-last-cancel-at* nil)
             (multiple-value-bind (new-state output-event)
                 (reduce-input-state *input-state* event)
               (setf *input-state* new-state)
               (process-output-event output-event))))
          ((nshell.infrastructure.acl:consume-terminal-resize-p)
           (lambda () (%render-prompt-after-terminal-resize)))
          (t
           (setf *running* nil)
           nil)))))

;; REPL Entry
(defun run-repl (&key (load-config-p t) config-path (history-p t))
  "Run the interactive REPL and return the process exit code.

LOAD-CONFIG-P, CONFIG-PATH, and HISTORY-P make startup persistence explicit
for callers such as the executable's command-line policy.

INSTALL-INTERACTIVE-TERMINAL is called from INSIDE the UNWIND-PROTECT on
purpose. It changes the process group, the signal handlers, the terminal mode
and the ANSI modes in that order, so a failure part-way through still leaves
state to undo; installing outside the cleanup would skip the undo entirely and
hand the user's next shell a terminal with SGR mouse reporting still on."
  (initialize-repl-state
   :load-config-p load-config-p
   :config-path config-path
   :history-p history-p)
  (unwind-protect
      (if (setf *interactive-terminal-installed-p*
                (install-interactive-terminal))
          (progn
            (with-cps-trampoline (render-prompt-cont))
            *last-exit-code*)
          ;; Raw mode is a precondition for the line editor and could not be
          ;; entered; INSTALL-INTERACTIVE-TERMINAL has already said so on
          ;; stderr. Running the editor against a cooked terminal anyway is the
          ;; one outcome worth avoiding, so end the session instead.
          1)
    (setf *interactive-terminal-installed-p* nil)
    (restore-interactive-terminal)
    (format t "Goodbye!~%")))
