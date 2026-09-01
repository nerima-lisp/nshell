(in-package #:nshell.presentation)

(defun trampoline (thunk)
  "Run THUNK and repeatedly invoke each returned continuation until NIL."
  (loop for continuation = (funcall thunk)
        then (funcall continuation)
        while continuation))

(defmacro with-cps-trampoline (&body body)
  "Evaluate BODY as the initial step of a continuation trampoline.

BODY must return either NIL or a zero-argument continuation.  Keeping the
initial step lexical makes CPS call sites read like a boundary declaration and
leaves the continuation loop in TRAMPOLINE, where it can be tested once."
  `(trampoline (lambda () ,@body)))
