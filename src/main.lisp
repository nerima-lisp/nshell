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

(defun %cli-action (arguments)
  "Classify top-level CLI arguments."
  (if (null arguments)
      :run
      (let ((first-argument (first arguments)))
        (cond ((or (string= first-argument "--help")
                   (string= first-argument "-h"))
               :help)
              ((or (string= first-argument "--version")
                   (string= first-argument "-V"))
               :version)
              ((and (>= (length arguments) 2)
                    (or (string= first-argument "-c")
                        (string= first-argument "--command")))
               :command)
              ;; A leading non-flag argument names a script file to execute; any
              ;; remaining arguments become the script's $argv.
              ((not (%flag-argument-p first-argument))
               :script)
              (t
               :invalid)))))

(defun %cli-command (arguments)
  "Return the command string for command mode."
  (second arguments))

(defun %cli-command-arguments (arguments)
  "Return trailing arguments for command mode."
  (cddr arguments))

(defun %print-usage (&optional (stream *standard-output*))
  (format stream "Usage: nshell [--help] [--version] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]~%")
  (format stream "~%")
  (format stream "Without arguments, nshell starts an interactive shell when~%")
  (format stream "stdin is a terminal and reads batch input from stdin otherwise.~%")
  (format stream "With -c/--command, nshell executes COMMAND once in batch mode (ARGS are $argv).~%")
  (format stream "With a SCRIPT file argument, nshell runs the script (ARGS are $argv).~%"))

(defun %print-version (&optional (stream *standard-output*))
  (format stream "nshell v0.4.0 - fish-inspired shell in Common Lisp (SBCL ~a)~%"
          (lisp-implementation-version)))

(defun %fatal-error (error)
  (format *error-output* "Fatal error: ~a~%" error)
  1)

(defun main ()
  "Entry point for the nshell binary."
  (let* ((arguments (%command-line-arguments))
         (exit-code
           (handler-case
               (case (%cli-action arguments)
                 (:help
                  (%print-usage)
                  0)
                 (:version
                  (%print-version)
                  0)
                 (:command
                  (nshell.presentation::run-repl-batch
                   :line (%cli-command arguments)
                   :script-args (%cli-command-arguments arguments)))
                 (:script
                  (nshell.presentation::run-repl-script
                   (first arguments) (rest arguments)))
                 (:invalid
                  (%print-usage *error-output*)
                  1)
                 (:run
                  (if (tty-p)
                      (progn
                        (%print-version)
                        (nshell.presentation:run-repl)
                        0)
                      (nshell.presentation::run-repl-batch))))
             (error (error)
               (%fatal-error error)))))
    (sb-ext:quit :unix-status (or exit-code 0))))
