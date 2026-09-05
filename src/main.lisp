(in-package #:nshell)

(defun tty-p ()
  "Return T if standard input is a terminal (interactive mode)."
  (nshell.infrastructure.terminal:interactive-terminal-p))

(defun %flag-argument-p (argument)
  "Return T when ARGUMENT looks like an option flag (starts with a dash)."
  (nshell.feature.command-line:flag-argument-p argument))

(defun %build-cli-app ()
  "Build the cl-cli specification at the executable composition root.

The command-line feature owns shell policy and presentation.  The executable
owns the concrete parser because this is the only caller that needs cl-cli's
result representation."
  (cl-cli:make-app
   :name "nshell"
   :summary "fish-inspired shell in Common Lisp"
   :auto-help nil
   :global-options
    (list
    (cl-cli:make-option :key :show-help :name "help" :short #\h :kind :flag
                        :description "Show usage and exit.")
    (cl-cli:make-option :key :show-version :name "version" :short #\V :kind :flag
                        :description "Show version and exit.")
    (cl-cli:make-option :key :interactive :name "interactive" :short #\i :kind :flag
                        :description "Force the interactive line editor.")
    (cl-cli:make-option :key :no-config :name "no-config" :kind :flag
                        :description "Do not load the interactive startup file.")
    (cl-cli:make-option :key :config :name "config" :kind :value
                        :description "Load PATH instead of ~/.nshellrc.")
    (cl-cli:make-option :key :no-history :name "no-history" :kind :flag
                        :description "Do not read or write interactive history.")
    (cl-cli:make-option :key :command :name "command" :short #\c :kind :value
                        :stop-parsing-p t
                        :description
                        "Execute COMMAND once in batch mode; ARGS become $argv."))
   :positionals
   ;; The same rest positional carries -c arguments or a script path and its
   ;; arguments. A leading non-flag script is still handled before parsing so
   ;; script arguments that look like options remain literal.
   (list (cl-cli:make-positional :key :command-args :rest-p t))))

(defun %current-process-arguments ()
  "Return the command-line arguments of the current process."
  (rest (cl-cli:current-process-argv)))

(defun %parse-cli-arguments (arguments)
  "Parse ARGUMENTS and return the invocation plus a usage-error flag.

The second value is true when cl-cli rejected the arguments as a usage error.
The condition is handled at this composition boundary so shell policy and
presentation do not depend on cl-cli's condition hierarchy."
  (handler-case
      (values (cl-cli:parse-argv (%build-cli-app) (cons "nshell" arguments)) nil)
    (cl-cli:cli-usage-error ()
      (values nil t))))

(defun %print-usage (&optional (stream *standard-output*))
  (nshell.feature.command-line:print-usage stream))

(defun %print-version (&optional (stream *standard-output*))
  (nshell.feature.command-line:print-version stream))

(defun %fatal-error (error)
  (format *error-output* "Fatal error: ~a~%" error)
  1)

(defun %run-interactive (&key config-path load-config-p history-p)
  "Run the interactive entry point while preserving the no-option call path."
  (if (and load-config-p (null config-path) history-p)
      (nshell.presentation:run-repl)
      (nshell.presentation:run-repl
       :load-config-p load-config-p
       :config-path config-path
       :history-p history-p)))

(defun %run-default-invocation (&key (interactive-p nil)
                                     (load-config-p t)
                                     config-path
                                     (history-p t))
  "Dispatch nshell's default invocation and explicit startup policy."
  (if (or interactive-p (tty-p))
      (progn
        (when (and (tty-p)
                   (not interactive-p)
                   load-config-p
                   (null config-path)
                   history-p)
          (%print-version))
        (%run-interactive
         :config-path config-path
         :load-config-p load-config-p
         :history-p history-p))
    (nshell.presentation:run-repl-batch)))

(defun %parsed-startup-options (invocation)
  (values (not (null (cl-cli:option-value invocation :interactive)))
          (not (null (cl-cli:option-value invocation :no-config)))
          (cl-cli:option-value invocation :config)
          (not (null (cl-cli:option-value invocation :no-history)))))

(defun %print-startup-option-error (message)
  (format *error-output* "nshell: ~a~%" message)
  (%print-usage *error-output*)
  1)

(defun %run-parsed-invocation (invocation)
  "Dispatch a parsed command-line INVOCATION to the matching entry point."
  (cond
    ((cl-cli:option-value invocation :show-help)
     (%print-usage) 0)
    ((cl-cli:option-value invocation :show-version)
     (%print-version) 0)
    (t
     (multiple-value-bind (interactive-p no-config-p config-path no-history-p)
         (%parsed-startup-options invocation)
       (cond
         ((and no-config-p config-path)
          (%print-startup-option-error
           "--config and --no-config cannot be used together"))
         ((and (cl-cli:option-value invocation :command)
               interactive-p)
          (%print-startup-option-error
           "--interactive cannot be combined with --command"))
         ((cl-cli:option-value invocation :command)
          ;; `-c` consumes COMMAND; the rest positional holds the literal tail.
          (nshell.presentation:run-repl-batch
           :line (cl-cli:option-value invocation :command)
           :script-args
           (cl-cli:positional-value invocation :command-args)))
         ((and (cl-cli:positional-value invocation :command-args)
               (first (cl-cli:positional-value invocation :command-args)))
          (let ((arguments (cl-cli:positional-value invocation :command-args)))
            (nshell.presentation:run-repl-script
             (first arguments)
             (rest arguments))))
         (t
          (%run-default-invocation
           :interactive-p interactive-p
           :load-config-p (not no-config-p)
           :config-path config-path
           :history-p (not no-history-p))))))))

(defparameter *main-exit-function*
  (lambda (&key unix-status)
    (sb-ext:quit :unix-status unix-status))
  "Process termination function used by MAIN.")

(defun main ()
  "Entry point for the nshell binary."
  (let* ((arguments (%current-process-arguments))
         (exit-code
           (handler-case
               ;; A leading non-flag token names a SCRIPT to run; the remaining
               ;; arguments become $argv verbatim (including flag-like ones), so
               ;; short-circuit before the feature parser, which would parse them
               ;; as options.
               (cond
                 ((null arguments)
                  ;; The common stdin batch path does not need a CLI specification.
                  (%run-default-invocation))
                 ((not (%flag-argument-p (first arguments)))
                  (nshell.presentation:run-repl-script
                   (first arguments) (rest arguments)))
                 (t
                  (multiple-value-bind
                        (invocation usage-error-p)
                      (%parse-cli-arguments arguments)
                    (if usage-error-p
                        (progn
                          ;; Unknown flag / missing -c value / unexpected argument.
                          (%print-usage *error-output*)
                          1)
                        (%run-parsed-invocation invocation)))))
             (error (error)
               (%fatal-error error)))))
    (funcall *main-exit-function* :unix-status (or exit-code 0))))
