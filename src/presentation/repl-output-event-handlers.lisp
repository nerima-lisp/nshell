(in-package #:nshell.presentation)

  (define-output-event-handler %process-edit-command-output-event
                             with-cleared-rendered-completions-and-reset-prompt-cont
                             (host-kit:with-temporary-file (stream path :suffix ".txt")
                               (close stream)
                               (format t "~%")
                               (%write-editor-buffer path (input-state-buffer *input-state*))
                               (handler-case
                                   (let ((status (%run-external-editor (%editor-command-argv) path)))
                                     (if (and (eql status 0) (probe-file path))
                                         (let ((text (%read-editor-buffer path)))
                                           (setf *input-state*
                                                 (make-repl-input-state
                                                  :buffer text :cursor-pos (length text)))
                                           (refresh-current-input-state-suggestion))
                                         (format t "nshell: editor exited with status ~a~%" status)))
                                 (error (condition)
                                        (format t "nshell: editor failed: ~a~%" condition)))))

  (define-output-event-handler %process-redraw-output-event
                               with-cleared-rendered-completions-and-prompt-cont)

  (define-output-event-handler %process-copy-output-event
                               with-cleared-rendered-completions-and-prompt-cont
                               (let ((selection (and *input-state*
                                                     (kill-ring-first-selection *input-state*))))
                                 (when selection
                                   (let ((text (kill-ring-selection-text selection)))
                                     (when (plusp (length text))
                                       (nshell.infrastructure.terminal:copy-to-clipboard
                                        text))))))

  (define-output-event-handler %process-quit-output-event
                               progn
                               (setf *running* nil)
                               nil)

  (define-output-event-handler %process-default-output-event
                               with-cleared-rendered-completions-and-prompt-cont)
