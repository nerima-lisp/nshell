;;; Shared syntax-highlighting package.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage #:nshell.highlight
    (:documentation
     "Syntax-highlight data and rendering shared by application and presentation.")
    (:use #:cl)
    (:import-from #:nshell.util #:define-value-struct)
    (:export #:highlight-line
             #:highlight-span-start #:highlight-span-end
             #:highlight-span-role
             #:highlight->ansi #:theme-color->ansi)))
