;;; REPL state initialization
(in-package #:nshell.presentation)

(defparameter *history-persistence-enabled-p* t
  "Whether commands entered during this session are added to in-memory and persisted history.")
(defparameter *history-loading-enabled-p* nil
  "Whether a running REPL refreshes history from disk.")
(defvar *history-seen-command-texts* (make-hash-table :test #'equal))

(defvar *assistant-session-sequence* 0)

(defun %new-assistant-session-id ()
  (format nil "~d-~d-~d-~d"
          (get-universal-time)
          (get-internal-real-time)
          (nshell.infrastructure.acl:current-process-id)
          (incf *assistant-session-sequence*)))

(defun session-greeting-text ()
  "The greeting line for this session, or NIL for silence. NSHELL_GREETING
overrides the default version banner. An empty value disables the greeting.
The variable is read after the configured startup file runs, so that file can
set it."
  (let ((greeting (nshell.domain.environment:env-get (ensure-environment)
                                                     "NSHELL_GREETING")))
    (cond
      ((null greeting)
       (with-output-to-string (stream)
         (nshell.feature.command-line:print-version stream)))
      ((string= greeting "") nil)
      (t (format nil "~a~%" greeting)))))

(defun print-session-greeting ()
  (let ((greeting (session-greeting-text)))
    (when greeting
      (write-string greeting)
      (finish-output))))

(defun %config-source-name (path)
  (namestring
   (pathname
    (or path
        (nshell.infrastructure.persistence:config-file-path)))))

(defun %load-interactive-config (&key (enabled-p t) path)
  (when enabled-p
    (handler-case
        (dolist
            (source
             (if path
                 (nshell.infrastructure.persistence:load-config-sources path)
                 (nshell.infrastructure.persistence:load-config-sources)))
          (let* ((source-path (car source))
                 (lines (cdr source))
                 (source-name (%config-source-name source-path)))
            (when *running*
              (handler-case
                  (multiple-value-bind (output code)
                      (%with-repl-shell-context (context)
                        (nshell.application:source-lines-to-stream
                         context
                         lines
                         source-name))
                    (declare (ignore output))
                    (unless (zerop code)
                      (format *error-output*
                              "nshell: ~a exited with status ~a~%"
                              source-name
                              code)))
                (error (condition)
                  (format *error-output* "nshell: ~a: ~a~%"
                          source-name
                          condition))))))
      (error (condition)
        (format *error-output* "nshell: ~a: ~a~%"
                (%config-source-name path)
                condition)))))

(defun %east-asian-locale-wide-p (environment)
  (loop for name in '("LC_ALL" "LC_CTYPE" "LANG")
        for locale = (nshell.domain.environment:env-get environment name)
        when (and locale (plusp (length locale)))
          do (return
               (some (lambda (language)
                       (and (>= (length locale) 2)
                            (string-equal locale language :end1 2 :end2 2)
                            (or (= (length locale) 2)
                                (member (char locale 2) '(#\_ #\. #\@)))))
                     '("ja" "zh" "ko")))))

(defun %configured-east-asian-width (environment)
  (let ((value (nshell.domain.environment:env-get
                environment "NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH")))
    (handler-case
        (nshell.domain.configuration:parse-east-asian-ambiguous-width
         (or value :auto))
      (type-error (condition)
        (format *error-output*
                "nshell: invalid NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH value: ~a~%"
                condition)
        :auto))))

(defun %apply-east-asian-ambiguous-width (&key (interactive-p t))
  (let* ((configured (%configured-east-asian-width *environment*))
         (wide-p
           (case configured
             (:wide t)
             (:narrow nil)
             (:auto
              (if (and interactive-p
                       *interactive-terminal-installed-p*
                       (nshell.infrastructure.terminal:interactive-terminal-p))
                  (case (nshell.infrastructure.terminal:detect-east-asian-ambiguous-wide-p)
                    (:wide t)
                    (:narrow nil)
                    (otherwise (%east-asian-locale-wide-p *environment*)))
                  (%east-asian-locale-wide-p *environment*))))))
    (setf *config*
          (nshell.domain.configuration:make-config
           :theme (nshell.domain.configuration:config-theme *config*)
           :east-asian-ambiguous-width configured))
    (setf cl-tty-kit:*east-asian-ambiguous-wide* (not (null wide-p)))
    wide-p))
(defun %merge-history-records (history records)
  "Add unseen persisted records to HISTORY in oldest-first order."
  (let ((new-records nil)
        (new-texts (make-hash-table :test #'equal)))
    (history-kit:map-history
     (lambda (entry)
       (setf (gethash (history-kit:history-entry-text entry)
                      *history-seen-command-texts*)
             t))
     history)
    (dolist (record records)
      (let ((text (nshell.infrastructure.persistence:history-record-text record)))
        (unless (or (gethash text *history-seen-command-texts*)
                    (gethash text new-texts))
          (setf (gethash text new-texts) t)
          (push record new-records))))
    (when new-records
      (setf new-records (nreverse new-records)
            history
            (nth-value
             0
             (nshell.infrastructure.persistence:history-record-add-batch
              history new-records)))
      (dolist (record new-records)
        (setf (gethash
               (nshell.infrastructure.persistence:history-record-text record)
               *history-seen-command-texts*)
              t))
      (history-kit:history-reset-navigation history)
      t)))

(defvar *history-file-stamp* nil
  "History file stamp at the last merge; a refresh with the same stamp skips
reading the file.")

(defun %merge-history-file-into (history)
  ;; The stamp is taken before reading, so a write that lands during the read
  ;; leaves a stamp that differs from the file's next one. A failed read keeps
  ;; the old stamp so the unchanged file is read again at the next refresh.
  (let ((stamp (nshell.infrastructure.persistence:history-file-stamp)))
    (unless (and stamp (equal stamp *history-file-stamp*))
      (multiple-value-bind (records read-p)
          (nshell.infrastructure.persistence:load-history-file)
        (prog1 (%merge-history-records history records)
          (when read-p
            (setf *history-file-stamp* stamp)))))))

(defun %seed-history-from-file (history)
  "Load persisted entries oldest first so the newest record is most recent in HISTORY."
  (setf *history-file-stamp* nil)
  (%merge-history-file-into history))

(defun %refresh-history-from-file ()
  "Merge records other sessions appended. Called before a command runs and when
a new prompt is drawn, never from key handling, so navigation and Ctrl-R see
external appends from the next prompt on."
  (when (and *history-loading-enabled-p* *history*)
    (when (%merge-history-file-into *history*)
      (%note-suggestion-history-changed))))

(defun %vi-mode-flag-enabled-p (flag)
  (and flag
       (not (member flag
                    (list "" "0" "false" "no")
                    :test (function string-equal)))))

(defparameter +safe-mode-assistant-reason+ "disabled in safe mode"
  "Reason the assistant model boundary reports for every call in safe mode.")

(defun %make-safe-mode-assistant-boundary ()
  "Return a model boundary that refuses every turn without spawning a sidecar."
  (nshell.feature.assistant:make-assistant-model-boundary
   :start-fn (lambda () (values nil +safe-mode-assistant-reason+))
   :request-fn (lambda (generation payload)
                 (declare (ignore generation payload))
                 (values nil +safe-mode-assistant-reason+))
   :poll-fn (lambda (generation)
              (declare (ignore generation))
              (values nil nil))
   :stop-fn (lambda () t)
   :status-fn (lambda ()
                (list :state :unavailable
                      :reason +safe-mode-assistant-reason+))))

(defun initialize-repl-state (&key (load-config-p t) config-path (history-p t)
                                   private-p)
  "Initialize an interactive session with explicit startup policy.

CONFIG-PATH overrides the startup file when LOAD-CONFIG-P is true. HISTORY-P
controls history reads and writes. PRIVATE-P prevents this session's commands
and assistant state from being written. When HISTORY-P is true, existing
history remains available in private mode. In safe mode
(NSHELL.APPLICATION:*SAFE-MODE-P*) the startup files and the AI sidecar are
skipped, while history still follows HISTORY-P."
  (%stop-suggestion-worker)
  (setf *boundaries* (make-real-boundary-context)
        *repl-filesystem* (nshell.infrastructure.acl:make-host-filesystem)
        *running* t
        *last-exit-code* 0
        *pipefail* nil
        *last-command-duration-ms* nil
        *last-command-output* nil
        *last-command-text* nil
        *capture-command-output-p* nil
        *rerun-confirmation-pending-p* nil
        *rerun-command-assessment* nil
        *failure-explain-available-p* nil
        *history-persistence-enabled-p* (and history-p (not private-p))
        *history-seen-command-texts* (make-hash-table :test #'equal)
        *history-file-stamp* nil
        *history* (history-kit:make-history)
        *config* (nshell.domain.configuration:default-config)
        *kb* (nshell.domain.completion:make-empty-knowledge-base)
        *input-state* (make-repl-input-state)
        *assistant-turn-generation* 0
        *assistant-turn-started-at* nil
        *assistant-last-event-at* nil
        *assistant-last-cancel-at* nil
        *last-assistant-model-event* nil
        *assistant-model-event-handler* nil
        *assistant-request-kind* nil
        *assistant-explain-candidates* nil
        *assistant-explain-candidate-index* 0
        *agent-session* nil
        *assistant-session-id* (unless private-p (%new-assistant-session-id))
        *assistant-pending-transcript* nil
        nshell.application:*agent-start-handler* #'start-agent-session
        nshell.application:*ai-reset-handler* #'reset-ai-session
        nshell.feature.assistant:*assistant-boundaries*
          (nshell.feature.assistant:make-assistant-boundary-context
           (if nshell.application:*safe-mode-p*
               (%make-safe-mode-assistant-boundary)
               (nshell.feature.assistant:make-assistant-sidecar-boundary)))
        *completion-rendered-lines* 0
        *prompt-rendered-lines* 0
        *prompt-rendered-cursor-row* 0
        *prompt-rendered-terminal-width* +default-terminal-width+
        *prompt-rendered-prompt-width* 0
        *prompt-rendered-origin-row* 1
        *prompt-rendered-origin-column* 1
        *prompt-rendered-origin-known-p* nil
        *prompt-hook-pending-p* t
        *interactive-terminal-installed-p* nil
        *environment* (nshell.application:seed-shell-status-environment
                       (nshell.domain.environment:inject-os-environment
                        (nshell.domain.environment:make-default-environment)
                        (nshell.infrastructure.acl:current-environment-entries)
                        (function nshell.infrastructure.acl:current-working-directory))))
  (nshell.feature.assistant:reset-assistant-usage)
  (nshell.feature.assistant:reset-assistant-settings)
  (progn
    (%reset-repl-state-tables)
    (setf *osc133-state* :none))
  (nshell.infrastructure.terminal:reset-terminal-color-depth)
  (setf nshell.domain.prompting:*git-status-resolver*
        (function nshell.infrastructure.acl:get-git-status)
        nshell.application:*theme-apply-handler* (function apply-repl-theme)
        nshell.application:*bind-table-handler* (function bind-dispatch-handler)
        nshell.application::*vi-mode-handler*
          (lambda (enabled)
            (setf *vi-mode-enabled* (not (null enabled))))
        nshell.application:*prompt-format-apply-handler* (function apply-prompt-format)
        nshell.application:*prompt-format-query-handler* (function current-prompt-format)
        nshell.application:*prompt-preview-handler* (function preview-prompt-format))
  (setf *vi-mode-enabled*
        (%vi-mode-flag-enabled-p
         (nshell.infrastructure.acl:current-environment-value "NSHELL_VI_MODE")))
  (progn
    (%load-interactive-config
     :enabled-p (and load-config-p (not nshell.application:*safe-mode-p*))
     :path config-path))
  (%apply-east-asian-ambiguous-width)
  (when history-p
    (%seed-history-from-file *history*))
  (seed-repl-completion-knowledge-base *kb*)
  (%refresh-suggestion-history-snapshot))
