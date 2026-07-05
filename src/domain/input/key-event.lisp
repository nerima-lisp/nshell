;;; Domain model for decoded input events.

(in-package #:nshell.domain.input)

(defstruct (key-event
             (:constructor %make-key-event (type &optional char number data))
             (:copier nil))
  "Decoded shell input event.

TYPE is a keyword such as :CHAR, :PASTE, :ENTER, :TAB, :LEFT, :CTRL-C, or :SHIFT-TAB.
CHAR is populated for printable character events. NUMBER and DATA carry optional
structured payloads for terminal protocols such as mouse reporting or
bracketed paste."
  (type :char :type keyword :read-only t)
  (char nil :type (or null character) :read-only t)
  (number nil :type (or null integer) :read-only t)
  (data nil :read-only t))

(defun make-key-event (type &optional char number data)
  (%make-key-event type char number data))
