(in-package #:nshell.presentation)

(declaim (ftype (function (function) (values t integer &rest t))
                call-with-command-failure-restarts))
