;;; nshell REPL - CPS-based interactive shell loop
;;; fish-inspired UX with trampoline-driven continuations
(in-package #:nshell.presentation)

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
      (lambda () (render-prompt-cont))
      (let ((event (%map-rendered-mouse-event-to-buffer
                    (nshell.infrastructure.terminal:read-key-event))))
        (cond
          (event
           (lambda ()
             (multiple-value-bind (new-state output-event)
                 (reduce-input-state *input-state* event)
               (setf *input-state* new-state)
               (process-output-event output-event))))
          ((nshell.infrastructure.acl:consume-terminal-resize-p)
           (lambda () (render-prompt-cont)))
          (t
           (setf *running* nil)
           nil)))))

;; REPL Entry
(defun run-repl ()
  (initialize-repl-state)
  (install-interactive-terminal)
  (unwind-protect
      (trampoline (lambda () (render-prompt-cont)))
    (restore-interactive-terminal)
    (format t "Goodbye!~%")))
