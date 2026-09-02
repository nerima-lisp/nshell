(in-package #:nshell.infrastructure.acl)

(sb-alien:define-alien-routine ("tcsetpgrp" %tcsetpgrp) sb-alien:int
  (fd sb-alien:int)
  (pgid sb-alien:int))

(sb-alien:define-alien-routine ("tcgetpgrp" %tcgetpgrp) sb-alien:int
  (fd sb-alien:int))

(sb-alien:define-alien-routine ("ioctl" %ioctl) sb-alien:int
  (fd sb-alien:int)
  (request sb-alien:unsigned-long)
  (arg sb-sys:system-area-pointer))
