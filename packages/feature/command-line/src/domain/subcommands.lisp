(in-package #:nshell.feature.command-line)

;;; Subcommands are reserved words (design decision D-53): when the first
;;; argument of nshell is a registered name, the subcommand runs even if a
;;; script with that name exists. Such a script runs as `nshell ./NAME` or
;;; `nshell -- NAME`. Each task that implements a subcommand registers it here
;;; with one REGISTER-SUBCOMMAND call; dispatch and the help text read only
;;; this table.

(defvar *subcommands* '()
  "Registered subcommands in registration order, each (NAME SUMMARY HANDLER).")

(defun register-subcommand (name summary handler)
  "Reserve NAME as a subcommand. HANDLER is a function designator called with
the arguments after NAME; it returns the exit status. SUMMARY is its one-line
help text. Registering NAME again replaces its entry in place."
  (check-type name string)
  (check-type summary string)
  (assert (and (plusp (length name)) (not (flag-argument-p name))
               (not (find #\/ name)))
          (name)
          "A subcommand name must be nonempty, must not start with -, and must not contain /: ~s"
          name)
  (let ((entry (assoc name *subcommands* :test #'string=)))
    (if entry
        (setf (rest entry) (list summary handler))
        (setf *subcommands*
              (append *subcommands* (list (list name summary handler))))))
  name)

(defun find-subcommand (argument)
  "Return the handler registered for ARGUMENT, or NIL. The match is exact, so
./NAME and other paths never match."
  (third (assoc argument *subcommands* :test #'equal)))

(defun subcommand-summaries ()
  "Return (NAME SUMMARY) for each registered subcommand, in registration order."
  (mapcar (lambda (entry) (list (first entry) (second entry))) *subcommands*))
