;;; Domain packages for signals, input events, and abbreviations.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage #:nshell.domain.signals
    (:use #:cl)
    (:import-from #:nshell.util #:define-value-struct)
    (:export #:make-signal #:signal-name #:signal-number #:signal-p #:signal=
             #:+sigint+ #:+sigterm+ #:+sigcont+ #:+sigchld+))
  (defpackage #:nshell.domain.input
    (:use #:cl)
    (:import-from #:nshell.util #:define-value-struct)
    (:export #:key-event #:key-event-p #:make-key-event #:key-event-type
             #:key-event-char #:key-event-number #:key-event-data))
  (defpackage #:nshell.domain.abbreviation
    (:use #:cl)
    (:import-from #:nshell.util #:define-value-struct)
    (:export #:abbreviation-boundary-p #:abbreviation-target-before-cursor
             #:abbreviation-command-position-p #:abbreviation-p
             #:make-abbreviation #:abbreviation-expansion #:abbreviation-position
             #:expand-abbreviation)))
