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

(defconstant +tiocgwinsz+
  #+darwin #x40087468
  #+linux #x5413
  #-(or darwin linux) 0)

(defconstant +tiocswinsz+
  #+darwin #x80087467
  #+linux #x5414
  #-(or darwin linux) 0)

(defconstant +tiocsctty+
  #+darwin #x20007461
  #+linux #x540E
  #-(or darwin linux) 0)
