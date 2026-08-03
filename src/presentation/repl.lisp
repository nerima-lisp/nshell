;;; nshell REPL - CPS-based interactive shell loop
;;; fish-inspired UX with trampoline-driven continuations
(in-package #:nshell.presentation)

(defun read-key-cont ()
  (let ((event (nshell.infrastructure.terminal:read-key-event)))
    (if event
      (lambda ()
          (multiple-value-bind (new-state output-event)
              (reduce-input-state *input-state* event)
            (setf *input-state* new-state)
            (process-output-event output-event)))
        (progn
          (setf *running* nil)
          nil))))

;; REPL Entry
(defun run-repl ()
  "Run the interactive REPL and return the process exit code.
INSTALL-INTERACTIVE-TERMINAL is called from INSIDE the UNWIND-PROTECT on
purpose. It changes the process group, the signal handlers, the terminal mode
and the ANSI modes in that order, so a failure part-way through still leaves
state to undo; installing outside the cleanup would skip the undo entirely and
hand the user's next shell a terminal with SGR mouse reporting still on."
  (initialize-repl-state)
  (unwind-protect
      (if (install-interactive-terminal)
          (progn
            (trampoline (lambda () (render-prompt-cont)))
            0)
          ;; Raw mode is a precondition for the line editor and could not be
          ;; entered; INSTALL-INTERACTIVE-TERMINAL has already said so on
          ;; stderr. Running the editor against a cooked terminal anyway is the
          ;; one outcome worth avoiding, so end the session instead.
          1)
    (restore-interactive-terminal)
    (format t "Goodbye!~%")))
