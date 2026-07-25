(in-package #:nshell.domain.signals)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (define-value-struct os-signal
      ((name nil :type keyword)
       (number 1 :type (integer 1 64)))
    :documentation "A POSIX signal as a domain value object."
    :constructor %allocate-signal
    :predicate signal-p))

(defun %make-signal (name number)
  (check-type name keyword)
  (check-type number (integer 1 64))
  (%allocate-signal name number))

(defun make-signal (name number)
  (%make-signal name number))

(defun signal-name (sig) (os-signal-name sig))
(defun signal-number (sig) (os-signal-number sig))

(defun signal= (a b)
  (and (signal-p a) (signal-p b)
       (eq (signal-name a) (signal-name b))
       (= (signal-number a) (signal-number b))))

(defvar +sigint+  (load-time-value (make-signal :sigint 2)))
(defvar +sigterm+ (load-time-value (make-signal :sigterm 15)))
(defvar +sigcont+ (load-time-value (make-signal :sigcont 18)))
(defvar +sigchld+ (load-time-value (make-signal :sigchld 17)))
