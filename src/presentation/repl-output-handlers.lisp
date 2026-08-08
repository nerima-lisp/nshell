;;; REPL output-event execution helpers
(in-package #:nshell.presentation)

(defmacro with-reset-rendered-prompt-state-and-prompt-cont (&body body)
  `(progn
     ,@body
     (reset-rendered-prompt-state)
     (lambda () (render-prompt-cont))))

(defmacro with-cleared-rendered-completions-and-prompt-cont (&body body)
  `(with-reset-rendered-prompt-state-and-prompt-cont
     (clear-rendered-completions)
     ,@body))

(defmacro define-output-event-handler (name wrapper &body body)
  `(defun ,name ()
     (,wrapper
      ,@body)))

(defun %elapsed-command-duration-ms (start-time end-time)
  (max 0
       (round (* 1000
                 (/ (- end-time start-time)
                    internal-time-units-per-second)))))

(defun refresh-current-input-state-suggestion (&optional (text (input-state-buffer *input-state*)))
  (let ((completion-path
          (nshell.domain.environment:env-get (ensure-environment) "PATH")))
    (setf (input-state-suggestion *input-state*)
          (compute-suggestion *history*
                              text
                              :knowledge-base *kb*
                              :path completion-path
                              :alias-table *aliases*
                              :function-table *functions*))))

(defun %history-last-argument-state (state argument start end index)
  (copy-input-state-clearing-completion
   state
   :buffer (concatenate 'string
                        (subseq (input-state-buffer state) 0 start)
                        argument
                        (subseq (input-state-buffer state) end))
   :cursor-pos (+ start (length argument))
   :last-argument-start start
   :last-argument-end (+ start (length argument))
   :last-argument-index index))

(defun %history-last-argument-selected-p (state)
  (let* ((buffer (input-state-buffer state))
         (start (input-state-last-argument-start state))
         (end (input-state-last-argument-end state))
         (index (input-state-last-argument-index state)))
    (and (integerp start)
         (integerp end)
         (integerp index)
         (<= 0 start end (length buffer))
         (let ((argument (nshell.domain.history:history-last-argument-at
                          *history* index)))
           (and argument
                (string= argument (subseq buffer start end)))))))

(defun %insert-history-last-argument-selected (state)
  (let* ((start (input-state-last-argument-start state))
         (end (input-state-last-argument-end state))
         (index (input-state-last-argument-index state))
         (argument (nshell.domain.history:history-last-argument-at
                    *history* (1+ index))))
    (if argument
        (let ((new-state (%history-last-argument-state
                          state argument start end (1+ index))))
          (%record-history-last-argument-transition
           state new-state :suggest-update)
          :suggest-update)
        :none)))

(defun %insert-history-last-argument-initial (state)
  (let ((argument (nshell.domain.history:history-last-argument-at *history* 0)))
    (if argument
        (let ((cursor (input-state-cursor-pos state)))
          (multiple-value-bind (inserted-state inserted-output)
              (insert-string-at-cursor state argument)
            (let ((new-state (%history-last-argument-state
                              inserted-state argument
                              cursor
                              (input-state-cursor-pos inserted-state)
                              0)))
              (%record-history-last-argument-transition
               state new-state inserted-output)
              inserted-output)))
        :none)))

(defun %record-history-last-argument-transition (old-state new-state output)
  (setf *input-state*
        (record-undo-transition
         old-state new-state output
         (nshell.infrastructure.terminal:make-key-event :alt-dot)))
  output)

(defun insert-history-last-argument ()
  (let ((old-state *input-state*))
    (if (%history-last-argument-selected-p old-state)
        (%insert-history-last-argument-selected old-state)
        (%insert-history-last-argument-initial old-state))))

(defun %execute-empty-input ()
  (with-reset-rendered-prompt-state-and-prompt-cont
    (format t "~%")
    (setf *last-command-duration-ms* nil)
    (setf *input-state* (make-repl-input-state))))

(defun %execute-complete-command (ast text)
  (with-reset-rendered-prompt-state-and-prompt-cont
    (format t "~%")
    (sync-exported-environment)
    ;; Time the command through the clock boundary (real clock == monotonic
    ;; get-internal-real-time), so a fake clock makes duration deterministic.
    (let ((start-time (boundary-monotonic))
          (exit-code nil))
      (unwind-protect
           (setf exit-code (or (execute-ast ast) 0))
        (let ((recorded-exit-code (if (integerp exit-code) exit-code 1)))
          (setf *last-exit-code* recorded-exit-code
                *last-command-duration-ms*
                (%elapsed-command-duration-ms
                 start-time
                 (boundary-monotonic)))
          (history-kit:history-add *history* text
                                   :exit-code recorded-exit-code)
          (history-kit:history-reset-navigation *history*)
          (nshell.infrastructure.persistence:append-history-entry text))))
    (setf *input-state* (make-repl-input-state))))

(defun %execute-parse-error (result)
  (with-reset-rendered-prompt-state-and-prompt-cont
    (format t "~%")
    (report-parse-diagnostics result *error-output*)
    (setf *last-exit-code* 2
          *last-command-duration-ms* nil
          *input-state* (make-repl-input-state))))

(defun %execute-incomplete-command (result)
  (format t "~%")
  (reset-rendered-prompt-state)
  (multiple-value-bind (continued-state output)
      (insert-newline-at-cursor *input-state*
                                :indent (if (or (nshell.domain.parsing:parse-diagnostic-kind-p
                                                 result :trailing-continuation)
                                                (nshell.domain.parsing:parse-diagnostic-kind-p
                                                 result :unclosed-block))
                                            2
                                            0))
    (declare (ignore output))
    (setf *input-state* continued-state))
  (lambda () (render-prompt-cont)))

(defun %execute-command-line (text)
  (handler-case
      (if (string= text "")
          (%execute-empty-input)
          (multiple-value-bind (expanded-text expansion-error)
              (nshell.domain.history:history-expand-line *history* text)
            (if expansion-error
                (with-reset-rendered-prompt-state-and-prompt-cont
                 (format t "~%nshell: ~a~%" expansion-error)
                 (setf *last-exit-code* 2
                       *last-command-duration-ms* nil
                       *input-state* (make-repl-input-state)))
                (nshell.domain.parsing:with-parsed-command-line-case
                 (result ast expanded-text)
                 (:complete
                  (%execute-complete-command ast expanded-text))
                 (:error
                  (%execute-parse-error result))
                 (:incomplete
                  (%execute-incomplete-command result))))))
    (error (condition)
           (with-reset-rendered-prompt-state-and-prompt-cont
            (format t "~%nshell error: ~a~%" condition)
            (setf *last-exit-code* 1
                  *last-command-duration-ms* nil
                  *input-state* (make-repl-input-state))))))

  (defun %process-execute-output-event ()
    (clear-rendered-completions)
    (%execute-command-line (input-state-buffer *input-state*)))

  (define-output-event-handler %process-complete-output-event
                               with-cleared-rendered-completions-and-prompt-cont
                               (if (%completion-session-valid-p *input-state*)
                                   (let ((candidates (input-state-last-candidates *input-state*))
                                         (selected-index (input-state-completion-index *input-state*)))
                                     (setf *completion-rendered-lines*
                                           (%render-completions-below-prompt
                                            candidates
                                            :selected-index selected-index)))
                                   (multiple-value-bind (refreshed-state candidates)
                                       (%refresh-completion-session-state *input-state*)
                                     (setf *input-state* refreshed-state)
                                     (when candidates
                                       (setf *completion-rendered-lines*
                                             (%render-completions-below-prompt candidates))))))

(define-output-event-handler %process-suggest-update-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (history-kit:history-reset-navigation *history*)
    (refresh-current-input-state-suggestion))

(define-output-event-handler %process-history-search-output-event
    with-cleared-rendered-completions-and-prompt-cont
    (let* ((query (input-state-search-query *input-state*))
           (entries (nshell.application:interactive-history-search-use-case
                     *history* query))
           (texts (history-kit:history-entry-texts entries)))
      (setf *input-state*
            (apply-history-search-results-to-input-state *input-state* texts))))

(define-output-event-handler %process-history-prev-output-event
    with-cleared-rendered-completions-and-prompt-cont
  (let ((entry (history-kit:history-previous
                 *history*
                 (input-state-buffer *input-state*))))
    (when entry
      (setf *input-state*
            (make-repl-input-state :buffer entry :cursor-pos (length entry)))
      (refresh-current-input-state-suggestion))))

(define-output-event-handler %process-history-next-output-event
    with-cleared-rendered-completions-and-prompt-cont
  (let ((entry (history-kit:history-next *history*)))
    (when entry
      (setf *input-state*
            (make-repl-input-state :buffer entry :cursor-pos (length entry)))
      (refresh-current-input-state-suggestion))))

  (define-output-event-handler %process-clear-screen-output-event
                               with-reset-rendered-prompt-state-and-prompt-cont
                               (nshell.infrastructure.terminal:ansi-clear-screen)
                               (nshell.infrastructure.terminal:ansi-move-cursor 1 1)
                               (reset-rendered-completion-state))

  (define-output-event-handler %process-insert-last-argument-output-event
                               with-cleared-rendered-completions-and-prompt-cont
                               (when (eq (insert-history-last-argument) :suggest-update)
                                 (refresh-current-input-state-suggestion)))

  (defun %split-editor-command (command)
    (let ((tokens '())
          (current (make-string-output-stream))
          (quoted-p nil)
          (escaped-p nil)
          (token-started-p nil))
      (labels ((finish-token ()
                             (when token-started-p
                               (push (get-output-stream-string current) tokens)
                               (setf current (make-string-output-stream)
                                     token-started-p nil))))
        (loop for character across command
              do (cond
                  (escaped-p
                   (write-char character current)
                   (setf escaped-p nil
                         token-started-p t))
                  ((char= character #\\)
                   (setf escaped-p t
                         token-started-p t))
                  ((and quoted-p (char= character quoted-p))
                   (setf quoted-p nil
                         token-started-p t))
                  ((and (not quoted-p)
                        (or (char= character #\') (char= character #\")))
                   (setf quoted-p character
                         token-started-p t))
                  ((and (not quoted-p)
                        (or (char= character #\Space)
                            (char= character #\Tab)
                            (char= character #\Newline)))
                   (finish-token))
                  (t
                   (write-char character current)
                   (setf token-started-p t))))
        (when escaped-p
          (write-char #\\ current))
        (finish-token)
        (nreverse tokens))))

  (defun %editor-command-argv ()
    (let* ((environment (ensure-environment))
           (command (or (loop for name in '("NSHELL_EDITOR" "VISUAL" "EDITOR")
                              for value =
                              (nshell.domain.environment:env-get environment name)
                              when (and value (plusp (length value)))
                              return value)
                        "vi"))
           (argv (%split-editor-command command)))
      (if (and argv (plusp (length (first argv))))
          argv
          '("vi"))))

  (defun %write-editor-buffer (path text)
    (with-open-file (stream path :direction :output :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string text stream)
      (terpri stream)))

  (defun %read-editor-buffer (path)
    (let ((text (host-kit:read-file-string path)))
      (if (and (plusp (length text))
               (char= (char text (1- (length text))) #\Newline))
          (subseq text 0 (1- (length text)))
          text)))

  (defun %run-external-editor (argv path)
    (nshell.infrastructure.terminal:ansi-disable-sgr-mouse)
    (nshell.infrastructure.terminal:ansi-disable-bracketed-paste)
    (nshell.infrastructure.terminal:restore-terminal-mode)
    (unwind-protect
     (progn
       (finish-output)
       (sync-exported-environment)
       (nshell.infrastructure.acl:run-external-exec
        (first argv) (append (rest argv) (list path))))
     (ignore-errors (nshell.infrastructure.terminal:enable-raw-mode))
     (ignore-errors (nshell.infrastructure.terminal:ansi-enable-bracketed-paste))
     (ignore-errors (nshell.infrastructure.terminal:ansi-enable-sgr-mouse))))

  (define-output-event-handler %process-edit-command-output-event
                             with-cleared-rendered-completions-and-prompt-cont
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
