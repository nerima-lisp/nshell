(in-package #:nshell.feature.command-line)

(defun print-usage (&optional (stream *standard-output*))
  "Print the command-line usage text to STREAM."
  (format stream "~a~%" (usage-synopsis))
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
  (format stream "  -l, --login        Load the login environment.~%")
  (format stream "  -c, --shell-command  Delegate COMMAND and ARGS to /bin/sh.~%")
  (format stream "      --command      Execute COMMAND in nshell batch mode.~%")
  (format stream "      --no-config    Do not load the interactive startup file.~%")
  (format stream "      --config PATH  Load PATH instead of the XDG nshell/init.lisp default.~%")
  (format stream "      --no-history   Disable history reads and writes; private mode still suppresses assistant state.~%")
  (format stream "      --private      Read history without saving this session's commands.~%")
  (format stream "      --mcp          Run the stdio MCP server.~%")
  (format stream "  -h, --help         Show usage and exit.~%")
  (format stream "  -V, --version      Show version and exit.~%"))

(defun print-version (&optional (stream *standard-output*))
  "Print nshell's version banner to STREAM."
  (format
   stream
   "nshell v~a - fish-inspired shell in Common Lisp (SBCL ~a)~%"
   (asdf:component-version (asdf:find-system "nshell"))
   (lisp-implementation-version)))
