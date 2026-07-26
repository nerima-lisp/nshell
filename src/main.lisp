(in-package #:nshell)


(defun tty-p ()
  "Return T if standard input is a terminal (interactive mode)."
  #+sbcl (= 1 (sb-unix:unix-isatty 0))
  #-sbcl nil)

(defun %command-line-arguments ()
  "Return the command-line arguments passed to nshell."
  #+sbcl (rest sb-ext:*posix-argv*)
  #-sbcl nil)

(defun %flag-argument-p (argument)
  "Return T when ARGUMENT looks like an option flag (starts with a dash)."
  (and (stringp argument)
       (plusp (length argument))
       (char= (char argument 0) #\-)))

;;; The flag-led surface (`--help`/`-h`, `--version`/`-V`, `-c COMMAND [ARGS…]`,
;;; no-args) is parsed by cl-cli.  We keep nshell's own help/version text and
;;; exit codes, so the app suppresses cl-cli's built-in help (`:auto-help nil`)
;;; and omits `:version`, declaring flags with non-reserved keys instead.  The
;;; `-c` option uses `:stop-parsing-p` so every token after COMMAND — including
;;; flag-like ones — becomes a literal argument for $argv.
(defun %build-cli-app ()
  "Build the cl-cli application spec describing nshell's command line."
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
    (cl-cli:make-option :key :command :name "command" :short #\c :kind :value
                        :stop-parsing-p t
                        :description
                        "Execute COMMAND once in batch mode; ARGS become $argv."))
   :positionals
   ;; Only reached via the `-c` stop-parsing tail; a leading SCRIPT is handled
   ;; before parsing (see MAIN) to preserve its arguments verbatim.
   (list (cl-cli:make-positional :key :command-args :rest-p t))))

(defun %print-usage (&optional (stream *standard-output*))
  (format stream "Usage: nshell [--help] [--version] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]~%")
  (format stream "~%")
  (format stream "Without arguments, nshell starts an interactive shell when~%")
  (format stream "stdin is a terminal and reads batch input from stdin otherwise.~%")
  (format stream
          "With -c/--command, nshell executes COMMAND once in batch mode (ARGS are $argv).~%")
  (format stream "With a SCRIPT file argument, nshell runs the script (ARGS are $argv).~%"))

(defun %print-version (&optional (stream *standard-output*))
  (format stream "nshell v0.4.0 - fish-inspired shell in Common Lisp (SBCL ~a)~%"
          (lisp-implementation-version)))

(defun %fatal-error (error)
  (format *error-output* "Fatal error: ~a~%" error)
  1)

(defun %run-parsed-invocation (invocation)
  "Dispatch a parsed cl-cli INVOCATION to the matching nshell entry point."
  (cond
    ((cl-cli:option-value invocation :show-help)
     (%print-usage) 0)
    ((cl-cli:option-value invocation :show-version)
     (%print-version) 0)
    ((cl-cli:option-value invocation :command)
     ;; `-c` consumed COMMAND; the rest positional holds the literal tail.
     (nshell.presentation:run-repl-batch
      :line (cl-cli:option-value invocation :command)
      :script-args (cl-cli:positional-value invocation :command-args)))
    (t
     ;; No flags and no -c: interactive when stdin is a tty, batch otherwise.
     (if (tty-p)
         (progn
           (%print-version)
           (nshell.presentation:run-repl)
           0)
         (nshell.presentation:run-repl-batch)))))

(defun main ()
  "Entry point for the nshell binary."
  (let* ((arguments (%command-line-arguments))
         (exit-code
           (handler-case
               ;; A leading non-flag token names a SCRIPT to run; the remaining
               ;; arguments become $argv verbatim (including flag-like ones), so
               ;; short-circuit before cl-cli, which would parse them as options.
               (if (and arguments (not (%flag-argument-p (first arguments))))
                   (nshell.presentation:run-repl-script
                    (first arguments) (rest arguments))
                   (handler-case
                       (%run-parsed-invocation
                        (cl-cli:parse-argv (%build-cli-app)
                                           (cl-cli:current-process-argv)))
                     ;; Unknown flag / missing -c value / unexpected argument.
                     (cl-cli:cli-usage-error ()
                       (%print-usage *error-output*)
                       1)))
             (error (error)
               (%fatal-error error)))))
    (sb-ext:quit :unix-status (or exit-code 0))))
