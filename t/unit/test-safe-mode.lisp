;;; Tests for --safe / NSHELL_SAFE (task P0-5, design decision D-52).
(in-package #:nshell/test)

(defun %safe-test-write-file (path &rest lines)
  (ensure-directories-exist path)
  (with-open-file (stream path :direction :output
                               :if-exists :supersede
                               :if-does-not-exist :create)
    (dolist (line lines)
      (write-line line stream)))
  path)

(defun %safe-test-config-directory (config-home)
  (merge-pathnames #P"nshell/" (uiop:ensure-directory-pathname config-home)))

(defmacro with-safe-test-process-environment ((&rest bindings) &body body)
  "Run BODY with the process environment variables in BINDINGS, a list of
(NAME VALUE) forms, set; restore the previous values afterwards."
  (let ((saved (loop repeat (length bindings) collect (gensym "SAVED-"))))
    `(let ,(loop for (name) in bindings
                 for variable in saved
                 collect `(,variable (host-kit:getenv ,name)))
       (unwind-protect
            (progn
              ,@(loop for (name value) in bindings
                      collect `(sb-posix:setenv ,name ,value 1))
              ,@body)
         ,@(loop for (name) in bindings
                 for variable in saved
                 collect `(if ,variable
                              (sb-posix:setenv ,name ,variable 1)
                              (sb-posix:unsetenv ,name)))))))

(defmacro with-process-safe-mode ((value) &body body)
  "Set the process-wide NSHELL.APPLICATION:*SAFE-MODE-P* to VALUE around BODY
and restore the previous value afterwards. The value is assigned, not bound:
a LET binding is thread-local, so pipeline worker threads would not see it and
a test using one would hide a loader that runs on a worker thread."
  (let ((saved (gensym "SAVED-")))
    `(let ((,saved nshell.application:*safe-mode-p*))
       (unwind-protect
            (progn
              (setf nshell.application:*safe-mode-p* ,value)
              ,@body)
         (setf nshell.application:*safe-mode-p* ,saved)))))

(defmacro with-safe-session-state (() &body body)
  "Isolate the globals INITIALIZE-REPL-STATE assigns, so a safe-mode session
started by one test does not leak into the next."
  `(with-repl-test-state
     (let ((nshell.presentation::*boundaries* nil)
           (nshell.presentation::*history-seen-command-texts*
             (make-hash-table :test #'equal))
           (nshell.infrastructure.persistence::*config-file-path-override* nil)
           (nshell.infrastructure.persistence:*history-file-path-override* nil)
           (nshell.presentation::*prompt-left-format* nil)
           (nshell.presentation::*prompt-right-format* nil))
       ,@body)))

(defun %safe-test-initialize (&rest arguments)
  "Run INITIALIZE-REPL-STATE with ARGUMENTS and return its standard error."
  (with-output-to-string (*error-output*)
    (let ((*standard-output* (make-broadcast-stream)))
      (apply #'nshell.presentation::initialize-repl-state arguments))))

(defun %safe-test-invoke-main (arguments &key (stdin "") tty-p)
  "Run MAIN with ARGUMENTS as the process arguments and STDIN as standard
input, and return the exit status it passes to *MAIN-EXIT-FUNCTION*."
  (let* ((status nil)
         (nshell::*main-exit-function*
           (lambda (&key unix-status &allow-other-keys)
             (setf status unix-status))))
    (with-temporary-functions
        (('nshell::%current-process-arguments (lambda () arguments))
         ('nshell::tty-p (lambda () tty-p)))
      ;; String streams, not broadcast streams: with broadcast streams the
      ;; external command a probe function runs exits with status 127.
      (let ((*standard-input* (make-string-input-stream stdin))
            (*standard-output* (make-string-output-stream))
            (*error-output* (make-string-output-stream)))
        (nshell::main)))
    status))

(defvar *safe-test-probe-count* 0)

(defun %safe-test-call-with-autoload-probe (function)
  "Call FUNCTION with a new function name NAME, an XDG config home whose
functions directory defines NAME, the marker file NAME creates, and the
temporary root directory.

An autoloaded or typed defun stays defined in NSHELL.USER, and head resolution
finds it there without autoloading again. So each call uses a new name and
afterwards removes every NSHELL.USER symbol whose name starts with NAME."
  (let ((name (format nil "p05_probe_~d" (incf *safe-test-probe-count*))))
    (host-kit:with-temporary-directory (root)
      (let ((config-home (merge-pathnames "config/" root))
            (marker (merge-pathnames "autoloaded" root)))
        (%safe-test-write-file
         (merge-pathnames (format nil "functions/~a.nsh" name)
                          (%safe-test-config-directory config-home))
         (format nil "(defun ~a () (touch ~s))" name (namestring marker)))
        (unwind-protect
             (funcall function name config-home marker root)
          (let ((package (find-package "NSHELL.USER"))
                (symbols nil))
            (do-symbols (symbol package)
              (when (and (eq package (symbol-package symbol))
                         (<= (length name) (length (symbol-name symbol)))
                         (string-equal name (symbol-name symbol)
                                       :end2 (length name)))
                (push symbol symbols)))
            (dolist (symbol symbols)
              (unintern symbol package))))))))

(describe "safe-mode-command-line"
  (it "safe-flag-is-parsed-as-a-startup-option"
    (multiple-value-bind (invocation usage-error-p)
        (nshell::%parse-cli-arguments '("--safe"))
      (expect nil :to-be usage-error-p)
      (expect t :to-be
              (nth-value 6 (nshell::%parsed-startup-options invocation))))
    (expect (search "--safe" (with-output-to-string (stream)
                               (nshell::%print-usage stream)))
            :to-be-truthy))

  (it "nshell-safe-environment-follows-the-boolean-flag-convention"
    (flet ((requested-p (flag-p value)
             (with-temporary-function
                 ('host-kit:getenv
                  (lambda (name)
                    (and (string= name "NSHELL_SAFE") value)))
               (nshell::%safe-mode-requested-p flag-p))))
      (expect (requested-p nil "1") :to-be-truthy)
      (expect (requested-p nil "yes") :to-be-truthy)
      (expect (requested-p nil nil) :to-be-falsy)
      (expect (requested-p nil "") :to-be-falsy)
      (expect (requested-p nil "0") :to-be-falsy)
      (expect (requested-p nil "FALSE") :to-be-falsy)
      (expect (requested-p nil "no") :to-be-falsy)
      ;; The flag has no negative form, so NSHELL_SAFE=0 cannot cancel it.
      (expect (requested-p t "0") :to-be-truthy)
      (expect (requested-p t nil) :to-be-truthy)))

  (it "safe-and-config-are-a-usage-error-in-either-order"
    (dolist (arguments '(("--safe" "--config" "custom.lisp")
                         ("--config" "custom.lisp" "--safe")))
      (let ((dispatched-p nil)
            (status nil))
        (with-temporary-functions
            (('nshell::%run-default-invocation
              (lambda (&rest ignored)
                (declare (ignore ignored))
                (setf dispatched-p t)
                0)))
          (let ((error-output
                  (with-output-to-string (*error-output*)
                    (with-process-safe-mode (nil)
                      (setf status
                            (nshell::%run-parsed-invocation
                             (nth-value 0 (nshell::%parse-cli-arguments arguments))))))))
            (expect 1 :to-equal status)
            (expect nil :to-be dispatched-p)
            (expect (search "nshell: --safe and --config cannot be used together"
                            error-output)
                    :to-be-truthy)
            ;; Same display as the other usage errors: the message, then usage.
            (expect (search +usage-synopsis-line+ error-output) :to-be-truthy))))))

  (it "nshell-safe-environment-and-config-are-a-usage-error"
    (let ((status nil))
      (with-temporary-functions
          (('host-kit:getenv
            (lambda (name) (and (string= name "NSHELL_SAFE") "1")))
           ('nshell::%run-default-invocation
            (lambda (&rest ignored)
              (declare (ignore ignored))
              (error "a usage error must not dispatch"))))
        (let ((error-output
                (with-output-to-string (*error-output*)
                  (with-process-safe-mode (nil)
                    (setf status
                          (nshell::%run-parsed-invocation
                           (nth-value 0 (nshell::%parse-cli-arguments
                                         '("--config" "custom.lisp")))))))))
          (expect 1 :to-equal status)
          (expect (search "nshell: NSHELL_SAFE and --config cannot be used together"
                          error-output)
                  :to-be-truthy)
          (expect (search +usage-synopsis-line+ error-output) :to-be-truthy)))))

  (it "safe-flag-and-nshell-safe-are-set-before-the-repl-starts"
    ;; Each call records the process-wide value RUN-REPL starts with, then
    ;; its arguments, which carry no safe-mode option.
    (let ((calls nil))
      (with-process-safe-mode (nil)
        (with-temporary-functions
            (('nshell::tty-p (lambda () t))
             ('nshell.presentation:run-repl
              (lambda (&rest arguments)
                (push (cons nshell.application:*safe-mode-p* arguments) calls)
                0)))
          ;; --safe, with NSHELL_SAFE=0 in the environment.
          (with-temporary-function
              ('host-kit:getenv
               (lambda (name) (and (string= name "NSHELL_SAFE") "0")))
            (%safe-test-invoke-main '("--safe") :tty-p t))
          ;; --safe with --no-config is redundant but allowed.
          (%safe-test-invoke-main '("--safe" "--no-config") :tty-p t)
          ;; NSHELL_SAFE=1 and no arguments: MAIN's argument-free path.
          (with-temporary-function
              ('host-kit:getenv
               (lambda (name) (and (string= name "NSHELL_SAFE") "1")))
            (%safe-test-invoke-main '() :tty-p t))
          ;; NSHELL_SAFE=0 leaves safe mode off and the call path untouched.
          (with-temporary-function
              ('host-kit:getenv
               (lambda (name) (and (string= name "NSHELL_SAFE") "0")))
            (%safe-test-invoke-main '() :tty-p t))))
      (destructuring-bind (unsafe from-environment with-no-config from-flag)
          calls
        (expect t :to-be (first from-flag))
        (expect t :to-be (first with-no-config))
        (expect nil :to-be (getf (rest with-no-config) :load-config-p))
        (expect t :to-be (first from-environment))
        (expect '(nil :load-config-p t :config-path nil :history-p t :greeting-p t)
                :to-equal unsafe))))

  (it "safe-flag-is-set-before-the-interactive-shell-command-startup"
    (let ((captured nil))
      (with-process-safe-mode (nil)
        (with-temporary-function
            ('nshell.presentation:run-repl-shell-command
             (lambda (command arguments &rest options)
               (setf captured (list* nshell.application:*safe-mode-p*
                                     command arguments options))
               0))
          (%safe-test-invoke-main '("--safe" "-i" "-c" "true"))))
      (expect '(t "true" nil :load-config-p t :config-path nil)
              :to-equal captured))))

(describe "safe-mode-session-startup"
  (it "safe-mode-skips-init-lisp-and-conf-d"
    (host-kit:with-temporary-directory (config-home)
      (let ((config-directory (%safe-test-config-directory config-home)))
        (%safe-test-write-file (merge-pathnames "init.lisp" config-directory)
                               "set -x NSHELL_SAFE_TEST_INIT loaded")
        (%safe-test-write-file (merge-pathnames "conf.d/10-probe.lisp" config-directory)
                               "set -x NSHELL_SAFE_TEST_CONF_D loaded")
        (with-safe-test-process-environment (("XDG_CONFIG_HOME" (namestring config-home)))
          (with-safe-session-state ()
            ;; Control: the same files load without safe mode.
            (%safe-test-initialize :history-p nil)
            (expect "loaded" :to-equal (repl-test-env "NSHELL_SAFE_TEST_INIT"))
            (expect "loaded" :to-equal (repl-test-env "NSHELL_SAFE_TEST_CONF_D"))
            (with-process-safe-mode (t)
              (%safe-test-initialize :history-p nil))
            (expect nil :to-be (repl-test-env "NSHELL_SAFE_TEST_INIT"))
            (expect nil :to-be (repl-test-env "NSHELL_SAFE_TEST_CONF_D")))))))

  (it "safe-mode-starts-with-a-broken-init-lisp"
    (dolist (broken-line '("(defun broken-p0-5-init (" ; syntax error
                           "(loop)"                    ; infinite loop
                           "(nshell-p0-5-undefined-function-probe)"))
      (host-kit:with-temporary-directory (config-home)
        (%safe-test-write-file
         (merge-pathnames "init.lisp" (%safe-test-config-directory config-home))
         broken-line)
        (with-safe-test-process-environment (("XDG_CONFIG_HOME" (namestring config-home)))
          (with-safe-session-state ()
            (let ((read-p nil))
              (with-temporary-function
                  ('nshell.infrastructure.persistence:load-config-sources
                   (let ((original (symbol-function
                                    'nshell.infrastructure.persistence:load-config-sources)))
                     (lambda (&rest arguments)
                       (setf read-p t)
                       (apply original arguments))))
                (let ((error-output (with-process-safe-mode (t)
                                      (%safe-test-initialize :history-p nil))))
                  (expect nil :to-be read-p)
                  (expect "" :to-equal error-output)
                  (expect t :to-be nshell.presentation::*running*)))))))))

  (it "safe-mode-still-loads-history"
    (with-temporary-output-file (history-path :prefix "nshell-safe-history")
      (with-safe-session-state ()
        (let ((nshell.infrastructure.persistence:*history-file-path-override*
                (pathname history-path)))
          (nshell.infrastructure.persistence:append-history-entry "echo from-history")
          (unwind-protect
               (progn
                 (with-process-safe-mode (t)
                   (%safe-test-initialize :history-p t))
                 (expect '("echo from-history")
                         :to-equal
                         (mapcar #'history-kit:history-entry-text
                                 (history-kit:history-entries
                                  nshell.presentation::*history*))))
            (let ((lock-path (nshell.infrastructure.persistence::%history-lock-path
                              history-path)))
              (when (probe-file lock-path)
                (delete-file lock-path))))))))

  (it "safe-mode-does-not-create-the-ai-sidecar"
    (with-safe-session-state ()
      (let ((sidecar-calls 0))
        (with-temporary-function
            ('nshell.feature.assistant:make-assistant-sidecar-boundary
             (lambda (&rest ignored)
               (declare (ignore ignored))
               (incf sidecar-calls)
               nil))
          ;; Control: a normal session builds the sidecar boundary.
          (%safe-test-initialize :load-config-p nil :history-p nil)
          (expect 1 :to-equal sidecar-calls)
          (with-process-safe-mode (t)
            (%safe-test-initialize :load-config-p nil :history-p nil))
          (expect 1 :to-equal sidecar-calls))
        (let ((start (nshell.feature.assistant:assistant-model-start))
              (status (nshell.feature.assistant:assistant-model-status)))
          (expect :unavailable :to-be
                  (nshell.feature.assistant:assistant-boundary-status start))
          (expect "disabled in safe mode" :to-equal
                  (nshell.feature.assistant:assistant-boundary-message start))
          (expect :unavailable :to-be (getf status :state))
          (expect "disabled in safe mode" :to-equal (getf status :reason))))))

  (it "safe-mode-does-not-autoload-functions"
    (host-kit:with-temporary-directory (config-home)
      (%safe-test-write-file
       (merge-pathnames "functions/safe-autoload-probe.nsh"
                        (%safe-test-config-directory config-home))
       "(defun safe-autoload-probe () 1)")
      (labels ((environment ()
                 (nshell.domain.environment:env-set
                  (nshell.domain.environment:make-default-environment)
                  "XDG_CONFIG_HOME" (namestring config-home) t))
               (repl-lookup ()
                 (let ((nshell.presentation::*environment* (environment)))
                   (nth-value
                    1
                    (nshell.application:lookup-shell-function
                     (nshell.application:context-shell-function-registry
                      (nshell.presentation::%make-repl-shell-context))
                     "safe-autoload-probe"))))
               (derived-context-lookup ()
                 ;; Contexts built inside the application layer install their
                 ;; own autoload hook, so the check must not live only in the
                 ;; REPL's context factory.
                 (nth-value
                  1
                  (nshell.application:lookup-shell-function
                   (nshell.application:context-shell-function-registry
                    (nshell.application:make-shell-context :environment (environment)))
                   "safe-autoload-probe"))))
        (with-safe-session-state ()
          (with-process-safe-mode (t)
            (expect nil :to-be (repl-lookup))
            (expect nil :to-be (derived-context-lookup))))
        ;; Control: the same file autoloads without safe mode.
        (with-safe-session-state ()
          (expect t :to-be (repl-lookup))))))

  (it "safe-mode-ignores-nshell-prompt"
    (with-prompt-format-environment '(("NSHELL_PROMPT" . "env-prompt> ")
                                      ("NSHELL_RIGHT_PROMPT" . "env-right"))
      (with-process-safe-mode (nil)
        (let ((output (capture-render-prompt :terminal-width 200)))
          (expect (search "env-prompt> " output) :to-be-truthy)
          (expect (search "env-right" output) :to-be-truthy)))
      (with-process-safe-mode (t)
        (let ((output (capture-render-prompt :terminal-width 200)))
          (expect (search "env-prompt> " output) :to-be-falsy)
          (expect (search "env-right" output) :to-be-falsy)))))

  (it "safe-mode-prefixes-a-fixed-marker-outside-the-user-prompt-format"
    (flet ((render (safe-p &rest arguments)
             (with-process-safe-mode (safe-p)
               (multiple-value-bind (output results)
                   (apply #'call-render-prompt :terminal-width 200 arguments)
                 (values output (first results))))))
      ;; A format installed by the prompt builtin cannot remove the marker.
      (multiple-value-bind (output width) (render t :left-format "custom> ")
        (expect 0 :to-equal (search "[safe] " output))
        (expect (search "custom> " output) :to-be-truthy)
        (expect (length "[safe] custom> ") :to-equal width))
      (multiple-value-bind (output width) (render nil :left-format "custom> ")
        (expect (search "[safe] " output) :to-be-falsy)
        (expect (length "custom> ") :to-equal width))
      ;; The built-in layout gets the same prefix. The right prompt's padding
      ;; shrinks by the marker width, so check the left side and its width.
      (multiple-value-bind (plain plain-width) (render nil)
        (multiple-value-bind (safe safe-width) (render t)
          (expect 0 :to-equal (search "[safe] " safe))
          (expect (+ plain-width (length "[safe] ")) :to-equal safe-width)
          (expect (search "[safe] " plain) :to-be-falsy)
          (expect (search "/project" plain) :to-be-truthy)
          (expect (< (length "[safe] ") (search "/project" safe))
                  :to-be-truthy))))))

(describe "safe-mode-entry-points"
  (it "safe-mode-stops-function-autoloading-in-non-interactive-runs"
    (flet ((run (entry &key safe-flag-p (nshell-safe "0"))
             ;; Return (exit-status-zero-p autoloaded-p) for one MAIN run that
             ;; calls the probe function through ENTRY.
             (%safe-test-call-with-autoload-probe
              (lambda (name config-home marker root)
                (let* ((script (namestring
                                (%safe-test-write-file
                                 (merge-pathnames "probe.nsh" root) name)))
                       (arguments
                         (append (when safe-flag-p (list "--safe"))
                                 (ecase entry
                                   (:command (list "--command" name))
                                   (:script (list script))
                                   (:stdin nil))))
                       (stdin (if (eq entry :stdin) (format nil "~a~%" name) "")))
                  (with-safe-test-process-environment
                      (("XDG_CONFIG_HOME" (namestring config-home))
                       ("NSHELL_SAFE" nshell-safe))
                    (with-safe-session-state ()
                      (with-process-safe-mode (nil)
                        (let ((status (%safe-test-invoke-main arguments :stdin stdin)))
                          (list (eql 0 status)
                                (not (null (probe-file marker)))))))))))))
      (dolist (entry (list :command :script :stdin))
        ;; Control: the entry point autoloads the function without safe mode.
        (expect (list entry t t) :to-equal (list* entry (run entry)))
        (expect (list entry nil nil)
                :to-equal (list* entry (run entry :safe-flag-p t)))
        ;; NSHELL_SAFE=1 alone. Without options, MAIN runs a script or stdin
        ;; without parsing the command line.
        (expect (list entry nil nil)
                :to-equal (list* entry (run entry :nshell-safe "1"))))))

  (it "safe-mode-reaches-pipeline-worker-threads-in-an-interactive-session"
    (flet ((autoloaded-p (arguments)
             (%safe-test-call-with-autoload-probe
              (lambda (name config-home marker root)
                (declare (ignore root))
                (with-safe-test-process-environment
                    (("XDG_CONFIG_HOME" (namestring config-home))
                     ("NSHELL_SAFE" "0"))
                  (with-safe-session-state ()
                    (with-process-safe-mode (nil)
                      ;; Run the session through MAIN and RUN-REPL, but submit
                      ;; the lines here instead of reading a terminal.
                      (with-temporary-functions
                          (((quote nshell.presentation::install-interactive-terminal)
                            (lambda ()
                              ;; The outer function is a pipeline stage, so it
                              ;; runs on a worker thread, and so does the
                              ;; lookup of the probe function inside it.
                              (nshell.presentation::%run-batch-source-lines
                               (list (format nil "(defun ~a_outer () (~a))" name name)
                                     (format nil "~a_outer | /bin/cat" name)))
                              nil))
                           ((quote nshell.presentation::restore-interactive-terminal)
                            (lambda () nil)))
                        (%safe-test-invoke-main arguments))
                      (not (null (probe-file marker))))))))))
      ;; Control: without safe mode the worker thread autoloads the function.
      (expect t :to-be (autoloaded-p (list "-i" "--no-history")))
      (expect nil :to-be (autoloaded-p (list "--safe" "-i" "--no-history"))))))
