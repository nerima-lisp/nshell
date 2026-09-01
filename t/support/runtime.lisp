(in-package #:nshell/test)

(defparameter +nshell-runtime-dependencies+
  '(:cl-prolog-kit :cl-parser-kit :cl-dataflow-kit :cl-boundary-kit :cl-cli
    :cl-tty-kit :cl-process-kit :cl-history-kit :cl-host-kit :cl-log-kit
    :cl-concurrent-kit)
  "ASDF systems whose source directories a fresh nshell subprocess needs.
The list includes transitive dependencies because subprocess bootstrap uses an
explicit central registry rather than inheriting the parent's registry.")
