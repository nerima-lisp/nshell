(in-package #:nshell.domain.signals)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct (os-signal (:constructor %allocate-signal (name number))
                        (:copier nil)
                        (:predicate signal-p))
    "A POSIX signal as a domain value object."
    (name nil :type keyword :read-only t)
    (number 1 :type (integer 1 64) :read-only t)))

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
(defvar +sigquit+ (load-time-value (make-signal :sigquit 3)))
(defvar +sigkill+ (load-time-value (make-signal :sigkill 9)))
(defvar +sigterm+ (load-time-value (make-signal :sigterm 15)))
(defvar +sigtstp+ (load-time-value (make-signal :sigtstp 20)))
(defvar +sigcont+ (load-time-value (make-signal :sigcont 18)))
(defvar +sigchld+ (load-time-value (make-signal :sigchld 17)))
(defvar +sigwinch+ (load-time-value (make-signal :sigwinch 28)))
