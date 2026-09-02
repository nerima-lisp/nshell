(in-package #:nshell.domain.parsing)

(defstruct (%fd-redirect-token-text
            (:constructor %make-fd-redirect-token-text (value advance-count)))
  (value "" :type string :read-only t)
  (advance-count 0 :type fixnum :read-only t))

(defparameter +tokenizer-special-reader-dispatch-characters+
  '(#\( #\) #\# #\' #\")
  "Non-operator characters that route through tokenizer special handlers.")

(defstruct (%tokenizer-special-dispatch-route
            (:constructor %make-tokenizer-special-dispatch-route (character kind)))
  (character nil :read-only t)
  (kind nil :type (or null keyword) :read-only t))

(defstruct (%tokenizer-ampersand-route
            (:constructor %make-tokenizer-ampersand-route (token-type value)))
  (token-type :ampersand :type keyword :read-only t)
  (value "&" :type string :read-only t))

(defstruct (%tokenizer-pipe-route
            (:constructor %make-tokenizer-pipe-route (token-type value)))
  (token-type :pipe :type keyword :read-only t)
  (value "|" :type string :read-only t))

(defstruct (%tokenizer-right-angle-route
            (:constructor %make-tokenizer-right-angle-route (kind value)))
  (kind :redirect :type keyword :read-only t)
  (value ">" :type (or null string) :read-only t))

(defstruct (%tokenizer-left-angle-route
            (:constructor %make-tokenizer-left-angle-route (kind value)))
  (kind :redirect :type keyword :read-only t)
  (value "<" :type (or null string) :read-only t))

(defstruct (%tokenizer-left-paren-route
            (:constructor %make-tokenizer-left-paren-route (kind end)))
  (kind :literal :type keyword :read-only t)
  (end nil :read-only t))
