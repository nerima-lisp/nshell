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
   "With -c/--command, nshell executes COMMAND once in batch mode (ARGS are $argv).~%")
  (format
   stream
   "With a SCRIPT file argument, nshell runs the script (ARGS are $argv).~%"))

(defun print-version (&optional (stream *standard-output*))
  "Print nshell's version banner to STREAM."
  (format
   stream
   "nshell v0.4.0 - fish-inspired shell in Common Lisp (SBCL ~a)~%"
   (lisp-implementation-version)))
