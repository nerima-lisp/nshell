;;; The evaluation package must exist before the production reader loads.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage #:nshell.user
    (:documentation
     "Persistent user evaluation package. Common Lisp names are available, and
user modules are loaded by the application layer.")
    (:use #:cl)
    (:import-from #:nshell.application #:command-failed)
    (:export |to-json| |from-json| |to-tsv| |from-tsv| |to-lines| |from-lines|
             |regex-match-p| |regex-find| |regex-replace|
             |split-string| |join-strings| |replace-string|)))

(deftype nshell.user::|command-failed| () 'nshell.application:command-failed)
