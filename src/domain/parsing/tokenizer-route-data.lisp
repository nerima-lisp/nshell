(in-package #:nshell.domain.parsing)

(define-value-struct %fd-redirect-token-text
  ((value "" :type string)
   (advance-count 0 :type fixnum)))

(defparameter +tokenizer-special-reader-dispatch-characters+
  '(#\( #\) #\# #\' #\")
  "Non-operator characters that route through tokenizer special handlers.")

(define-value-struct %tokenizer-special-dispatch-route
  ((character nil)
   (kind nil :type (or null keyword))))

(define-value-struct %tokenizer-ampersand-route
  ((token-type :ampersand :type keyword)
   (value "&" :type string)))

(define-value-struct %tokenizer-pipe-route
  ((token-type :pipe :type keyword)
   (value "|" :type string)))

(define-value-struct %tokenizer-right-angle-route
  ((kind :redirect :type keyword)
   (value ">" :type (or null string))))

(define-value-struct %tokenizer-left-angle-route
  ((kind :redirect :type keyword)
   (value "<" :type (or null string))))

(define-value-struct %tokenizer-left-paren-route
  ((kind :literal :type keyword)
   (end nil)))
