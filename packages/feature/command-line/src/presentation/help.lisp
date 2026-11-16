(in-package #:nshell.feature.command-line)

(defun print-usage (&optional (stream *standard-output*))
  "Print the command-line usage text to STREAM."
  (format stream "~a~%" (usage-synopsis))
  (format stream "       nshell SUBCOMMAND [ARGS...]~%")
  (format stream "~%")
  (format stream "Without arguments, nshell starts an interactive shell when~%")
  (format
   stream
   "stdin is a terminal and reads batch input from stdin otherwise.~%")
  (format
   stream
   "With -c/--shell-command, nshell delegates COMMAND and ARGS to /bin/sh.~%")
  (format
   stream
   "With --command, nshell executes COMMAND once in nshell; ARGS become $argv.~%")
  (format
   stream
   "With a SCRIPT file argument, nshell runs the script (ARGS become $argv).~%")
  (format stream "~%Options:~%")
  (format stream "  -i, --interactive  Force the interactive line editor.~%")
  (format stream "  -e, --errexit      Exit after a command failure.~%")
  (format stream "  -l, --login        Load the login environment.~%")
  (format stream "  -c, --shell-command  Delegate COMMAND and ARGS to /bin/sh.~%")
  (format stream "      --command      Execute COMMAND in nshell batch mode.~%")
  (format stream "      --json         With --command, print the result as one JSON envelope.~%")
  (format stream "      --timeout SEC  With --json, stop the whole run after SEC seconds (default 120).~%")
  (format stream "      --safe         Run without startup files, AI, function autoloading,~%")
  (format stream "                     or NSHELL_PROMPT.~%")
  (format stream "                     NSHELL_SAFE=1 does the same.~%")
  (format stream "      --no-config    Do not load the interactive startup file.~%")
  (format stream "      --config PATH  Load PATH instead of the XDG nshell/init.lisp default.~%")
  (format stream "      --no-history   Disable history reads and writes; private mode still suppresses assistant state.~%")
  (format stream "      --private      Read history without saving this session's commands.~%")
  (format stream "      --mcp          Run the stdio MCP server.~%")
  (format stream "  -h, --help         Show usage and exit.~%")
  (format stream "  -V, --version      Show version and exit.~%")
  (print-subcommands stream))

(defun print-subcommands (stream)
  "Print the registered subcommands and how to run a script of the same name."
  (let* ((summaries (subcommand-summaries))
         (width (reduce #'max summaries
                        :key (lambda (entry) (length (first entry)))
                        :initial-value 0)))
    (when summaries
      (format stream "~%Subcommands:~%")
      (loop for (name summary) in summaries
            do (format stream "  ~va  ~a~%" width name summary))
      (format stream "~%A subcommand takes precedence over a script of the same name.~%")
      (format stream "Run such a script as nshell ./NAME or nshell -- NAME.~%"))))

(defun print-version (&optional (stream *standard-output*))
  "Print nshell's version banner to STREAM."
  (format
   stream
   "nshell v~a - fish-inspired shell in Common Lisp (SBCL ~a)~%"
   (asdf:component-version (asdf:find-system "nshell"))
   (lisp-implementation-version)))
