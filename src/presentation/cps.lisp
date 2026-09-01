(in-package #:nshell.presentation)

(defun trampoline (thunk)
  "Run THUNK and repeatedly invoke each returned continuation until NIL."
  (loop for continuation = (funcall thunk)
        then (funcall continuation)
        while continuation))
