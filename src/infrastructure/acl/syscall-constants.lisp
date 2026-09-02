(in-package #:nshell.infrastructure.acl)

(defconstant +tiocswinsz+
  #+darwin #x80087467
  #+linux #x5414
  #-(or darwin linux) 0)

(defconstant +tiocsctty+
  #+darwin #x20007461
  #+linux #x540E
  #-(or darwin linux) 0)
