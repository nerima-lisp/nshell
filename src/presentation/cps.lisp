(in-package #:nshell.presentation)

(defconstant +repl-exit+
  :repl-exit)

(defun trampoline (thunk)
  "Run THUNK until it returns the explicit REPL exit value.

Invalid step results are reported and restart THUNK."
  (loop with step = thunk
        for result = (funcall step)
        do (cond
             ((eq result +repl-exit+) (return +repl-exit+))
             ((functionp result)
              (setf step result))
             (t
               (format *error-output*
                       "nshell: invalid REPL continuation result; returning to prompt.~%")
               (setf step thunk)))))

(defmacro with-cps-trampoline (&body body)
  "Evaluate BODY as the initial step of a continuation trampoline.

BODY should return the explicit REPL exit value or a zero-argument
continuation.  Other results are diagnosed before the initial step runs again."
  `(trampoline
    (lambda ()
      ,@body)))
