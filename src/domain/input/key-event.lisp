;;; Domain model for decoded input events.

(in-package #:nshell.domain.input)

(define-value-struct key-event
    ((type :char :type keyword)
     (char nil :type (or null character) :optional t)
     (number nil :type (or null integer) :optional t)
     (data nil :optional t))
  :documentation "Decoded shell input event.

TYPE is a keyword such as :CHAR, :PASTE, :ENTER, :TAB, :LEFT, :CTRL-C, or :SHIFT-TAB.
CHAR is populated for printable character events. NUMBER and DATA carry optional
structured payloads for terminal protocols such as mouse reporting or
bracketed paste.")

(defun make-key-event (type &optional char number data)
  (%make-key-event type char number data))
