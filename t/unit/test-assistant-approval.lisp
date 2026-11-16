(in-package #:nshell/test)

;;; D-P1-5 3.1: the proposal origin travels with the input state, and an
;;; approval is a one-shot (TEXT . LEVEL) record checked again at the gate.

(defun %approval-origin (state)
  (nshell.presentation::input-state-proposal-origin state))

(defun %approval-reduce-keys (state &rest events)
  (dolist (event events state)
    (setf state (nth-value 0 (nshell.presentation:reduce-input-state state event)))))

(defun %approval-proposal-state (buffer &rest initargs)
  (apply #'input-state
         (append initargs
                 (list :buffer buffer :cursor-pos (length buffer)
                       :proposal-origin t))))

(defun %approval-send-keys (&rest events)
  (with-temporary-function
      ('nshell.presentation::process-output-event
       (lambda (event) (declare (ignore event)) nil))
    (dolist (event events)
      (nshell.presentation::%process-input-event event))))

(defun %approval-add-history (text origin)
  (nshell.infrastructure.persistence:history-record-add
   nshell.presentation::*history* text :origin origin))

(defmacro with-approval-execution ((executed-var &key panel-var) &body body)
  "Run BODY with each evaluated submission recorded in EXECUTED-VAR, newest
first, as (SOURCE ORIGIN APPROVAL)."
  (let ((panel (or panel-var (gensym "PANEL"))))
    `(let ((,executed-var nil)
           (,panel nil)
           (nshell.presentation::*history-persistence-enabled-p* nil)
           (nshell.presentation::*history-loading-enabled-p* nil))
       (declare (ignorable ,panel))
       (with-temporary-functions
           (('nshell.application:evaluate-reader-result-in-context
             (lambda (context reader-result)
               (declare (ignore context))
               (push (list (nshell.domain.parsing:reader-result-source reader-result)
                           nshell.application:*execution-origin*
                           nshell.application:*execution-approval*)
                     ,executed-var)
               (values nil 0)))
            ('nshell.presentation::render-transient-panel
             (lambda (content &rest arguments)
               (declare (ignore arguments))
               (setf ,panel content)))
            ('nshell.presentation::render-prompt-cont
             (lambda () nil)))
         ,@body))))

(defmacro with-approval-gate-execution ((&key panel-var) &body body)
  "Run BODY with the real evaluator, so the execution gate sees the expanded line."
  (let ((panel (or panel-var (gensym "PANEL"))))
    `(let ((,panel nil)
           (nshell.presentation::*history-persistence-enabled-p* nil)
           (nshell.presentation::*history-loading-enabled-p* nil))
       (declare (ignorable ,panel))
       (with-temporary-functions
           (('nshell.presentation::render-transient-panel
             (lambda (content &rest arguments)
               (declare (ignore arguments))
               (setf ,panel content)))
            ('nshell.presentation::render-prompt-cont
             (lambda () nil)))
         ,@body))))

(defun %approval-press-enter ()
  (capture-process-output-event :execute))

(defun %approval-buffer ()
  (nshell.presentation:input-state-buffer nshell.presentation::*input-state*))

(describe "assistant-proposal-origin-transitions"
  (it "keeps-the-origin-through-insertion-and-deletion"
    (let ((state (%approval-reduce-keys (%approval-proposal-state "ls")
                                        (input-key-event :char #\x)
                                        (input-key-event :backspace)
                                        (input-key-event :backspace))))
      (expect "l" :to-equal (nshell.presentation:input-state-buffer state))
      (expect t :to-be (%approval-origin state))))

  (it "clears-the-origin-when-ctrl-u-empties-the-buffer"
    (let ((state (%approval-reduce-keys (%approval-proposal-state "rm -rf target")
                                        (input-key-event :ctrl-u))))
      (expect "" :to-equal (nshell.presentation:input-state-buffer state))
      (expect nil :to-be (%approval-origin state))))

  (it "keeps-the-origin-when-ctrl-u-leaves-text-after-the-cursor"
    (let ((state (%approval-reduce-keys
                  (%approval-proposal-state "rm -rf target" :cursor-pos 3)
                  (input-key-event :ctrl-u))))
      (expect "-rf target" :to-equal (nshell.presentation:input-state-buffer state))
      (expect t :to-be (%approval-origin state))))

  (it "restores-the-origin-of-a-killed-proposal-on-yank"
    (let ((state (%approval-reduce-keys (%approval-proposal-state "rm -rf target")
                                        (input-key-event :ctrl-u)
                                        (input-key-event :char #\l)
                                        (input-key-event :char #\s)
                                        (input-key-event :char #\Space)
                                        (input-key-event :ctrl-y))))
      (expect "ls rm -rf target" :to-equal (nshell.presentation:input-state-buffer state))
      (expect t :to-be (%approval-origin state))))

  (it "keeps-a-typed-origin-when-yanking-typed-text"
    (let ((state (%approval-reduce-keys (input-state :buffer "echo hi" :cursor-pos 7)
                                        (input-key-event :ctrl-w)
                                        (input-key-event :ctrl-y))))
      (expect "echo hi" :to-equal (nshell.presentation:input-state-buffer state))
      (expect nil :to-be (%approval-origin state))))

  (it "keeps-a-proposal-origin-when-yanking-typed-text-into-it"
    (let ((state (%approval-reduce-keys
                  (input-state :buffer "ls" :cursor-pos 2
                               :proposal-origin t :kill-ring (list " -l"))
                  (input-key-event :ctrl-y))))
      (expect "ls -l" :to-equal (nshell.presentation:input-state-buffer state))
      (expect t :to-be (%approval-origin state))))

  (it "clears-the-origin-on-ctrl-c-and-restores-it-on-undo"
    (let* ((cleared (%approval-reduce-keys (%approval-proposal-state "rm -rf target")
                                           (input-key-event :char #\x)
                                           (input-key-event :ctrl-c)))
           (undone (%approval-reduce-keys cleared (input-key-event :ctrl-underscore))))
      (expect "" :to-equal (nshell.presentation:input-state-buffer cleared))
      (expect nil :to-be (%approval-origin cleared))
      (expect "rm -rf target" :to-equal (nshell.presentation:input-state-buffer undone))
      (expect t :to-be (%approval-origin undone))))

  (it "restores-a-typed-origin-on-undo-and-the-proposal-origin-on-redo"
    (with-repl-test-state
      (with-repl-input-state (:mode :insert :buffer "question" :cursor-pos 8)
        (nshell.presentation::%install-assistant-proposal "rm file")
        (let* ((proposal nshell.presentation::*input-state*)
               (undone (%approval-reduce-keys proposal (input-key-event :ctrl-underscore)))
               (redone (%approval-reduce-keys undone (input-key-event :alt-r))))
          (expect t :to-be (%approval-origin proposal))
          (expect "question" :to-equal (nshell.presentation:input-state-buffer undone))
          (expect nil :to-be (%approval-origin undone))
          (expect "rm file" :to-equal (nshell.presentation:input-state-buffer redone))
          (expect t :to-be (%approval-origin redone))))))

  (it "restores-the-origin-on-vi-undo-after-ctrl-c"
    (with-vi-command-state (state (%approval-proposal-state "rm -rf target" :cursor-pos 0))
      (let* ((cleared (%approval-reduce-keys state
                                             (input-key-event :char #\x)
                                             (input-key-event :ctrl-c)))
             (undone (let ((nshell.presentation::*vi-mode-enabled* t))
                       (%approval-reduce-keys cleared
                                              (input-key-event :escape)
                                              (input-key-event :char #\u)))))
        (expect nil :to-be (%approval-origin cleared))
        (expect "rm -rf target" :to-equal (nshell.presentation:input-state-buffer undone))
        (expect t :to-be (%approval-origin undone)))))

  (it "restores-the-origin-of-a-vi-deleted-proposal-on-put"
    (with-vi-command-state (state (%approval-proposal-state "rm -rf target" :cursor-pos 0))
      (let ((put (let ((nshell.presentation::*vi-mode-enabled* t))
                   (%approval-reduce-keys state
                                          (input-key-event :char #\d)
                                          (input-key-event :char #\w)
                                          (input-key-event :ctrl-c)
                                          (input-key-event :escape)
                                          (input-key-event :char #\P)))))
        (expect "rm" :to-equal (nshell.presentation:input-state-buffer put))
        (expect t :to-be (%approval-origin put)))))

  (it "takes-the-origin-of-the-history-entry-on-history-navigation"
    (with-repl-test-state
      (let ((nshell.presentation::*history-loading-enabled-p* nil))
        (%approval-add-history "rm proposed-file" :proposal)
        (%approval-add-history "rm typed-file" :typed)
        (with-repl-input-state (:mode :insert :buffer "" :cursor-pos 0)
          (capture-standard-output
            (nshell.presentation::%process-history-prev-output-event))
          (expect "rm typed-file" :to-equal (%approval-buffer))
          (expect nil :to-be (%approval-origin nshell.presentation::*input-state*))
          (capture-standard-output
            (nshell.presentation::%process-history-prev-output-event))
          (expect "rm proposed-file" :to-equal (%approval-buffer))
          (expect t :to-be (%approval-origin nshell.presentation::*input-state*))))))

  (it "restores-the-in-progress-origin-when-history-navigation-returns"
    (with-repl-test-state
      (let ((nshell.presentation::*history-loading-enabled-p* nil))
        (%approval-add-history "rm typed-file" :typed)
        ;; History navigation matches entries by the line as a prefix.
        (let ((nshell.presentation::*input-state* (%approval-proposal-state "rm")))
          (capture-standard-output
            (nshell.presentation::%process-history-prev-output-event))
          (expect "rm typed-file" :to-equal (%approval-buffer))
          (expect nil :to-be (%approval-origin nshell.presentation::*input-state*))
          (capture-standard-output
            (nshell.presentation::%process-history-next-output-event))
          (expect "rm" :to-equal (%approval-buffer))
          (expect t :to-be (%approval-origin nshell.presentation::*input-state*))))))

  (it "takes-the-origin-of-the-history-entry-chosen-by-history-search"
    (with-repl-test-state
      (let ((nshell.presentation::*history-loading-enabled-p* nil))
        (%approval-add-history "rm proposed-file" :proposal)
        (let ((nshell.presentation::*input-state*
                (input-state :mode :search :buffer "rm proposed-file"
                             :cursor-pos 16 :search-query "rm"
                             :search-original-buffer "" :search-original-cursor 0)))
          (%approval-send-keys (input-key-event :right))
          (expect "rm proposed-file" :to-equal (%approval-buffer))
          (expect :insert :to-be (nshell.presentation:input-state-mode
                                  nshell.presentation::*input-state*))
          (expect t :to-be (%approval-origin nshell.presentation::*input-state*))))))

  (it "keeps-the-origin-when-the-buffer-goes-through-the-external-editor"
    (with-repl-test-state
      (let ((nshell.presentation::*input-state* (%approval-proposal-state "rm file")))
        (with-temporary-functions
            (('nshell.presentation::%run-external-editor
              (lambda (argv path) (declare (ignore argv path)) 0))
             ('nshell.presentation::%read-editor-buffer
              (lambda (path) (declare (ignore path)) "rm file"))
             ('nshell.presentation::render-prompt-cont (lambda () nil)))
          (capture-standard-output
            (nshell.presentation::%process-edit-command-output-event)))
        (expect "rm file" :to-equal (%approval-buffer))
        (expect t :to-be (%approval-origin nshell.presentation::*input-state*))))))

(describe "assistant-approval-record"
  (it "does-not-approve-a-proposal-when-it-is-installed"
    (with-repl-test-state
      (with-repl-input-state (:mode :insert :buffer "question" :cursor-pos 8)
        (nshell.presentation::%install-assistant-proposal "ls")
        (expect "ls" :to-equal (%approval-buffer))
        (expect t :to-be (%approval-origin nshell.presentation::*input-state*))
        (expect nil :to-be nshell.presentation::*assistant-command-approval*))))

  (it "runs-a-safe-proposal-on-one-enter-and-consumes-the-record"
    (with-repl-test-state
      (let ((nshell.presentation::*input-state* (%approval-proposal-state "ls")))
        (with-approval-execution (executed)
          (%approval-press-enter)
          (expect '(("ls" :proposal :safe)) :to-equal executed)
          (expect nil :to-be nshell.presentation::*assistant-command-approval*)
          (expect nil :to-be (%approval-origin nshell.presentation::*input-state*))))))

  (it "asks-for-a-second-enter-and-approves-at-the-confirm-level"
    (with-repl-test-state
      (let ((nshell.presentation::*input-state* (%approval-proposal-state "rm file")))
        (with-approval-execution (executed :panel-var panel)
          (%approval-press-enter)
          (expect nil :to-be executed)
          (expect '("rm file" . :pending) :to-equal
                  nshell.presentation::*assistant-command-approval*)
          (expect (search "confirmation" (first panel)) :to-be-truthy)
          (%approval-press-enter)
          (expect '(("rm file" :proposal :confirm)) :to-equal executed)
          (expect nil :to-be nshell.presentation::*assistant-command-approval*)))))

  (it "does-not-reuse-an-approval-for-the-same-text-proposed-again"
    (with-repl-test-state
      (let ((nshell.presentation::*input-state* (%approval-proposal-state "rm file")))
        (with-approval-execution (executed)
          (%approval-press-enter)
          (%approval-press-enter)
          (expect 1 :to-equal (length executed))
          (nshell.presentation::%install-assistant-proposal "rm file")
          (%approval-press-enter)
          (expect 1 :to-equal (length executed))
          (expect '("rm file" . :pending) :to-equal
                  nshell.presentation::*assistant-command-approval*)))))

  (it "refuses-a-blocked-ai-line-at-every-enter"
    (with-repl-test-state
      (let ((nshell.presentation::*input-state* (%approval-proposal-state "rm -rf /")))
        (with-approval-execution (executed :panel-var panel)
          (%approval-press-enter)
          (%approval-press-enter)
          (expect nil :to-be executed)
          (expect nil :to-be nshell.presentation::*assistant-command-approval*)
          (expect (search "blocked" (first panel)) :to-be-truthy)
          (expect "rm -rf /" :to-equal (%approval-buffer))))))

  (it "drops-a-pending-approval-when-the-text-changes"
    (with-repl-test-state
      (let ((nshell.presentation::*input-state* (%approval-proposal-state "rm file")))
        (with-approval-execution (executed)
          (%approval-press-enter)
          (%approval-send-keys (input-key-event :char #\2))
          (%approval-press-enter)
          (expect nil :to-be executed)
          (expect '("rm file2" . :pending) :to-equal
                  nshell.presentation::*assistant-command-approval*)))))

  ;; The alias target is a missing command: classified confirm, and running
  ;; it only reports "command not found" (exit 127).
  ;; Enter classifies in the context the line runs in, so it sees the alias
  ;; as the gate does and asks for the second Enter before running anything.
  (it "asks-for-confirmation-when-an-alias-turns-a-safe-proposal-into-confirm"
    (with-repl-test-state
      (repl-test-define-alias "ls" "nshell-approval-test-missing-command -r somedir")
      (let ((nshell.presentation::*input-state* (%approval-proposal-state "ls")))
        (with-approval-gate-execution ()
          (setf nshell.presentation::*last-exit-code* 0)
          (%approval-press-enter)
          (expect 0 :to-equal nshell.presentation::*last-exit-code*)
          (expect '("ls" . :pending) :to-equal
                  nshell.presentation::*assistant-command-approval*)
          (expect "ls" :to-equal (%approval-buffer))
          (expect t :to-be (%approval-origin nshell.presentation::*input-state*))
          (%approval-press-enter)
          (expect 127 :to-equal nshell.presentation::*last-exit-code*)
          (expect nil :to-be nshell.presentation::*assistant-command-approval*)
          (expect "" :to-equal (%approval-buffer))))))

  ;; The alias target is a fixture script that drains its input and exits 42.
  ;; A missing command would not do: a pipeline that spawns one fails, and
  ;; whether the echo stage or the spawn fails first depends on timing.
  (it "asks-for-confirmation-when-an-alias-in-a-pipeline-turns-confirm"
    (host-kit:with-temporary-directory (directory)
      (let ((target (merge-pathnames "approval-test-pipeline-target" directory)))
        (with-open-file (stream target :direction :output :if-exists :supersede)
          (format stream "#!/bin/sh~%while read -r _; do :; done~%exit 42~%"))
        (sb-posix:chmod (namestring target) #o700)
        (with-repl-test-state
          (repl-test-define-alias "ls" (namestring target))
          (let ((nshell.presentation::*input-state*
                  (%approval-proposal-state "echo hi | ls")))
            (with-approval-gate-execution ()
              (setf nshell.presentation::*last-exit-code* 0)
              (%approval-press-enter)
              (expect 0 :to-equal nshell.presentation::*last-exit-code*)
              (expect '("echo hi | ls" . :pending) :to-equal
                      nshell.presentation::*assistant-command-approval*)
              (%approval-press-enter)
              (expect 42 :to-equal nshell.presentation::*last-exit-code*)
              (expect nil :to-be
                      nshell.presentation::*assistant-command-approval*)))))))

  ;; Passes once the closed-world ls spec allows --color=auto (D-P1-5 2.6).
  (it "does-not-stop-a-safe-proposal-at-the-gate-for-an-ls-color-alias"
    (with-repl-test-state
      (repl-test-define-alias "ls" "ls --color=auto")
      (let ((nshell.presentation::*input-state* (%approval-proposal-state "ls")))
        (with-approval-gate-execution ()
          (%approval-press-enter)
          (expect 0 :to-equal nshell.presentation::*last-exit-code*)
          (expect nil :to-be nshell.presentation::*assistant-command-approval*)
          (expect "" :to-equal (%approval-buffer))))))

  (it "runs-a-typed-command-on-one-enter-after-ctrl-u-empties-a-proposal"
    (with-repl-test-state
      (let ((nshell.presentation::*input-state* (%approval-proposal-state "rm -rf target")))
        (%approval-send-keys (input-key-event :ctrl-u)
                             (input-key-event :char #\r)
                             (input-key-event :char #\m)
                             (input-key-event :char #\Space)
                             (input-key-event :char #\x))
        (with-approval-execution (executed)
          (%approval-press-enter)
          (expect '(("rm x" :typed nil)) :to-equal executed)))))

  (it "runs-a-typed-history-entry-on-one-enter-after-leaving-a-proposal"
    (with-repl-test-state
      (let ((nshell.presentation::*history-loading-enabled-p* nil)
            (nshell.presentation::*input-state* (%approval-proposal-state "rm")))
        (%approval-add-history "rm typed-file" :typed)
        (capture-standard-output
          (nshell.presentation::%process-history-prev-output-event))
        (with-approval-execution (executed)
          (%approval-press-enter)
          (expect '(("rm typed-file" :typed nil)) :to-equal executed)))))

  (it "gates-a-proposal-recalled-from-history"
    (with-repl-test-state
      (let ((nshell.presentation::*history-loading-enabled-p* nil)
            (nshell.presentation::*input-state* (input-state :buffer "" :cursor-pos 0)))
        (%approval-add-history "rm proposed-file" :proposal)
        (capture-standard-output
          (nshell.presentation::%process-history-prev-output-event))
        (with-approval-execution (executed)
          (%approval-press-enter)
          (expect nil :to-be executed)
          (%approval-press-enter)
          (expect '(("rm proposed-file" :proposal :confirm)) :to-equal executed)))))

  (it "gates-a-killed-proposal-yanked-back-after-ctrl-u"
    (with-repl-test-state
      (let ((nshell.presentation::*input-state* (%approval-proposal-state "rm -rf target")))
        (%approval-send-keys (input-key-event :ctrl-u) (input-key-event :ctrl-y))
        (with-approval-execution (executed)
          (%approval-press-enter)
          (expect nil :to-be executed)
          (expect '("rm -rf target" . :pending) :to-equal
                  nshell.presentation::*assistant-command-approval*)))))

  (it "gates-a-proposal-restored-by-undo-after-ctrl-c"
    (with-repl-test-state
      (let ((nshell.presentation::*input-state* (%approval-proposal-state "rm -rf target")))
        (%approval-send-keys (input-key-event :char #\x)
                             (input-key-event :ctrl-c)
                             (input-key-event :ctrl-underscore))
        (expect "rm -rf target" :to-equal (%approval-buffer))
        (with-approval-execution (executed)
          (%approval-press-enter)
          (expect nil :to-be executed)
          (%approval-press-enter)
          (expect '(("rm -rf target" :proposal :confirm)) :to-equal executed))))))

(describe "assistant-execution-gate-approval-levels"
  (it "stops-a-confirm-command-approved-only-at-the-safe-level"
    (let ((context (nshell.application:make-shell-context
                    :environment (nshell.domain.environment:make-environment)))
          (ast (nshell.domain.parsing:make-command-node "rm" (list "file")))
          (executed 0))
      (with-temporary-function
          ('nshell.application::execute-command-node-in-context
           (lambda (ignored-context ignored-ast)
             (declare (ignore ignored-context ignored-ast))
             (incf executed)
             (values "executed" 0)))
        (let ((nshell.application:*execution-origin* :proposal)
              (nshell.application:*execution-approval* :safe)
              (nshell.application:*execution-gate-stopped-p* nil))
          (multiple-value-bind (output code)
              (nshell.application:execute-ast-in-context context ast)
            (expect 3 :to-equal code)
            (expect (search "requires confirmation" output) :to-be-truthy)
            (expect t :to-be nshell.application:*execution-gate-stopped-p*)))
        (let ((nshell.application:*execution-origin* :proposal)
              (nshell.application:*execution-approval* :confirm)
              (nshell.application:*execution-gate-stopped-p* nil))
          (multiple-value-bind (output code)
              (nshell.application:execute-ast-in-context context ast)
            (expect "executed" :to-equal output)
            (expect 0 :to-equal code)
            (expect nil :to-be nshell.application:*execution-gate-stopped-p*)))
        (expect 1 :to-equal executed)))))

;;; The interactive REPL runs submissions through the reader executor, so the
;;; gate has to run there too, after words, aliases and functions are expanded.
;;; The commands below do not exist: confirm by classification, and running one
;;; only reports "command not found" (127).

(defparameter +approval-missing-command+ "nshell-approval-test-missing-command")

(defun %approval-reader-run (context source reader-context
                             &key (origin :proposal) approval)
  "Evaluate SOURCE on the reader path; return its status and whether the gate stopped."
  (let ((nshell.application:*execution-origin* origin)
        (nshell.application:*execution-approval* approval)
        (nshell.application:*execution-gate-stopped-p* nil)
        (status nil))
    (capture-standard-output
      (let ((*error-output* (make-string-output-stream)))
        (dolist (reader-result (nshell.domain.parsing:read-submission
                                source :reader-context reader-context))
          (setf status
                (nth-value 1 (nshell.presentation:call-with-command-failure-restarts
                              (lambda ()
                                (nshell.application:evaluate-reader-result-in-context
                                 context reader-result))))))))
    (values status nshell.application:*execution-gate-stopped-p*)))

(describe "reader-path-execution-gate"
  (it "does-not-gate-typed-commands"
    (multiple-value-bind (status stopped-p)
        (%approval-reader-run (make-test-shell-context) +approval-missing-command+
                              :bare-line :origin :typed)
      (expect 127 :to-equal status)
      (expect nil :to-be stopped-p)))

  (it "runs-a-confirm-command-only-with-a-confirm-approval"
    (let ((context (make-test-shell-context)))
      (multiple-value-bind (status stopped-p)
          (%approval-reader-run context +approval-missing-command+ :bare-line
                                :approval :safe)
        (expect 3 :to-equal status)
        (expect t :to-be stopped-p))
      (multiple-value-bind (status stopped-p)
          (%approval-reader-run context +approval-missing-command+ :bare-line
                                :approval :confirm)
        (expect 127 :to-equal status)
        (expect nil :to-be stopped-p))))

  (it "gates-every-stage-of-a-pipeline"
    (multiple-value-bind (status stopped-p)
        (%approval-reader-run (make-test-shell-context)
                              (format nil "echo hi | ~a" +approval-missing-command+)
                              :bare-line :approval :safe)
      (expect 3 :to-equal status)
      (expect t :to-be stopped-p)))

  (it "gates-forced-external-sexp-commands"
    (let ((context (make-test-shell-context))
          (source (format nil "(^~a)" +approval-missing-command+)))
      (multiple-value-bind (status stopped-p)
          (%approval-reader-run context source :sexp :approval :safe)
        (expect 3 :to-equal status)
        (expect t :to-be stopped-p))
      (multiple-value-bind (status stopped-p)
          (%approval-reader-run context source :sexp :approval :confirm)
        (expect 127 :to-equal status)
        (expect nil :to-be stopped-p))))

  (it "does-not-let-the-outer-approval-run-a-substituted-command"
    (multiple-value-bind (status stopped-p)
        (%approval-reader-run (make-test-shell-context)
                              (format nil "echo $(~a)" +approval-missing-command+)
                              :bare-line :approval :confirm)
      (declare (ignore status))
      (expect t :to-be stopped-p)))

  (it "does-not-let-the-outer-approval-run-a-function-body"
    (let ((context (make-test-shell-context))
          (body-status nil))
      (nshell.application::register-shell-function
       (nshell.application:context-shell-function-registry context)
       "approval-test-function"
       (nshell.application:make-shell-function-binding
        (lambda (&rest arguments)
          (declare (ignore arguments))
          (setf body-status
                (nth-value 1 (nshell.application:execute-reader-ast-in-context
                              context
                              (nshell.domain.parsing:make-command-node
                               +approval-missing-command+ nil)
                              (lambda (stage-context command-node)
                                (nshell.application::evaluate-command-stage-in-context
                                 stage-context command-node)))))
          (values nil 0))
        nil "approval-test-function" nil nil))
      (multiple-value-bind (status stopped-p)
          (%approval-reader-run context "approval-test-function" :bare-line
                                :approval :confirm)
        (declare (ignore status))
        (expect 3 :to-equal body-status)
        (expect t :to-be stopped-p)))))

(describe "reader-path-execution-gate-user-functions"
  (it "does-not-let-the-outer-approval-run-the-body-of-a-called-defun"
    (let ((context (make-test-shell-context)))
      (%approval-reader-run
       context
       ;; The status comparison keeps the refused or missing command from
       ;; signalling a command failure out of the body.
       (format nil "(defun approval-test-defun () (= (^~a) 0))"
               +approval-missing-command+)
       :sexp :origin :typed)
      (multiple-value-bind (status stopped-p)
          (%approval-reader-run context "(approval-test-defun)" :sexp
                                :approval :confirm)
        (declare (ignore status))
        (expect t :to-be stopped-p)))))

(defun %approval-env (context name)
  (nshell.domain.environment:env-get
   (nshell.application:shell-context-environment context) name))

(describe "execution-gate-assignment-only-nodes"
  (it "does-not-run-an-eval-assignment-on-the-outer-approval-on-the-reader-path"
    (let ((context (make-test-shell-context)))
      (multiple-value-bind (status stopped-p)
          (%approval-reader-run context "eval 'PATH=/tmp/x'" :bare-line
                                :approval :confirm)
        (declare (ignore status))
        (expect t :to-be stopped-p)
        (expect nil :to-be (equal "/tmp/x" (%approval-env context "PATH"))))))

  (it "does-not-run-an-eval-assignment-on-the-outer-approval-on-the-ast-path"
    (let ((context (make-test-shell-context))
          (ast (nshell.domain.parsing:parse-result-ast
                (nshell.domain.parsing:parse-command-line "eval 'PATH=/tmp/x'"))))
      (let ((nshell.application:*execution-origin* :proposal)
            (nshell.application:*execution-approval* :confirm)
            (nshell.application:*execution-gate-stopped-p* nil))
        (nshell.application:execute-ast-in-context context ast)
        (expect t :to-be nshell.application:*execution-gate-stopped-p*))
      (expect nil :to-be (equal "/tmp/x" (%approval-env context "PATH")))))

  (it "runs-an-eval-assignment-of-a-harmless-name-on-the-ast-path"
    (let ((context (make-test-shell-context))
          (ast (nshell.domain.parsing:parse-result-ast
                (nshell.domain.parsing:parse-command-line "eval 'TZ=UTC'"))))
      (let ((nshell.application:*execution-origin* :proposal)
            (nshell.application:*execution-approval* :confirm)
            (nshell.application:*execution-gate-stopped-p* nil))
        (nshell.application:execute-ast-in-context context ast)
        (expect nil :to-be nshell.application:*execution-gate-stopped-p*))
      (expect "UTC" :to-equal (%approval-env context "TZ"))))

  (it "runs-an-eval-assignment-of-a-harmless-name"
    (let ((context (make-test-shell-context)))
      (multiple-value-bind (status stopped-p)
          (%approval-reader-run context "eval 'TZ=UTC'" :bare-line
                                :approval :confirm)
        (expect 0 :to-equal status)
        (expect nil :to-be stopped-p)
        (expect "UTC" :to-equal (%approval-env context "TZ"))))))

;;; A quoted word, a forced (^...) command, and a quoted word after an
;;; assignment all run a command: none of them is an assignment-only line.
(describe "assignment-only-lines-are-decided-by-the-ast"
  (dolist (source '("\"LANG=C\"" "'LANG=C'" "(^LANG=C)" "(^LANG=C \"TZ=UTC\")"
                    "LANG=C \"TZ=UTC\""))
    (let ((source source))
      (it (format nil "does-not-treat-~a-as-an-assignment" source)
        (expect nil :to-be
                (eq :safe (nshell.presentation::%assistant-proposal-level source)))
        (multiple-value-bind (status stopped-p)
            (%approval-reader-run (make-test-shell-context) source
                                  (nshell.presentation::%repl-reader-context-for-source
                                   source)
                                  :approval :safe)
          (expect 3 :to-equal status)
          (expect t :to-be stopped-p))))))

;;; An alias that expands to a NAME=value word still runs that word as a
;;; command, so the gate must not read the expanded node as an assignment.
;;; (On the reader path the same alias fails in stage evaluation for any
;;; origin, so nothing runs there.)
(describe "alias-expanded-assignment-words-are-commands"
  (it "stops-a-safe-approval-on-the-ast-path"
    (let ((context (make-test-shell-context)))
      (setf (gethash "ls" (nshell.application:shell-context-alias-table context))
            "LANG=C")
      (let ((nshell.application:*execution-origin* :proposal)
            (nshell.application:*execution-approval* :safe)
            (nshell.application:*execution-gate-stopped-p* nil))
        (multiple-value-bind (output code)
            (nshell.application:execute-ast-in-context
             context (nshell.domain.parsing:make-command-node "ls" nil))
          (declare (ignore output))
          (expect 3 :to-equal code)
          (expect t :to-be nshell.application:*execution-gate-stopped-p*))))))
