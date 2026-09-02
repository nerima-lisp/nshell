(in-package #:nshell.infrastructure.acl)

(defstruct pty-process
  pid
  pgid
  master-fd
  stream)
