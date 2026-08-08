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
  (nshell.feature.command-line:flag-argument-p argument))

;;; The flag-led surface (`--help`/`-h`, `--version`/`-V`, `-c COMMAND [ARGS…]`,
;;; no-args) is parsed by cl-cli.  We keep nshell's own help/version text and
;;; exit codes, so the app suppresses cl-cli's built-in help (`:auto-help nil`)
;;; and omits `:version`, declaring flags with non-reserved keys instead.  The
;;; `-c` option uses `:stop-parsing-p` so every token after COMMAND — including
;;; flag-like ones — becomes a literal argument for $argv.
(defun %build-cli-app ()
  "Build the cl-cli application spec describing nshell's command line."
  (nshell.feature.command-line:build-cli-app))

(defun %print-usage (&optional (stream *standard-output*))
  (nshell.feature.command-line:print-usage stream))

(defun %print-version (&optional (stream *standard-output*))
  (nshell.feature.command-line:print-version stream))

(defun %fatal-error (error)
  (format *error-output* "Fatal error: ~a~%" error)
  1)

(defun %run-default-invocation ()
  "Dispatch nshell's no-argument invocation without constructing a CLI parser."
  (if (tty-p) (progn
      (%print-version)
      (nshell.presentation:run-repl)
      0)
    (nshell.presentation:run-repl-batch)))

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
     (%run-default-invocation))))

(defparameter *main-exit-function*
  (lambda (&key unix-status)
    (sb-ext:quit :unix-status unix-status))
  "Process termination function used by MAIN.")

(defun main ()
  "Entry point for the nshell binary."
  (let* ((arguments (%command-line-arguments))
         (exit-code
           (handler-case
               ;; A leading non-flag token names a SCRIPT to run; the remaining
               ;; arguments become $argv verbatim (including flag-like ones), so
               ;; short-circuit before cl-cli, which would parse them as options.
               (cond
                 ((null arguments)
                  ;; The common stdin batch path does not need a CLI specification.
                  (%run-default-invocation))
                 ((not (%flag-argument-p (first arguments)))
                  (nshell.presentation:run-repl-script
                   (first arguments) (rest arguments)))
                 (t
                  (handler-case
                      (%run-parsed-invocation
                       (cl-cli:parse-argv (%build-cli-app)
                                          (cl-cli:current-process-argv)))
                    ;; Unknown flag / missing -c value / unexpected argument.
                    (cl-cli:cli-usage-error ()
                      (%print-usage *error-output*)
                      1))))
             (error (error)
               (%fatal-error error)))))
    (funcall *main-exit-function* :unix-status (or exit-code 0))))
