(in-package #:nshell.domain.parsing)

(define-value-struct %here-doc-delimiter-scan
  ((reversed-delimiters '() :type list)))

(define-value-struct %here-doc-line
  ((text "" :type string)
   (next-position nil)
   (newline-p nil :type boolean)))

(define-value-struct %here-doc-body
  ((body "" :type string)
   (next-position nil)
   (missing-delimiter-p nil :type boolean)))

(define-value-struct %here-doc-consumption
  ((bodies '() :type list)
   (next-position nil)
   (incomplete-p nil :type boolean)))

(define-value-struct %here-doc-consumption-state
  ((reversed-bodies '() :type list)
   (next-position nil)
   (incomplete-p nil :type boolean)))
