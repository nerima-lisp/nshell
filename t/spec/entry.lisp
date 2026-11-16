(in-package #:nshell/spec)
(defun run (&key (reporter :spec))
    (format *standard-output* "PATH=~a~%" (%required-single-bin-path))
    (run-all :reporter reporter))