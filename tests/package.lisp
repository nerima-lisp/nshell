;;; nshell test package definitions

(in-package #:cl-user)

(defpackage #:nshell/test
  (:use #:cl #:fiveam)
  (:shadow #:gen-integer
           #:gen-in-range
           #:gen-string
           #:gen-shell-word
           #:gen-logic-atom
           #:gen-shell-command
           #:gen-shell-variable-name
           #:gen-shell-operator-only-input
           #:gen-shell-pipeline
           #:gen-prompt-text
           #:shrink-prompt-text
           #:shrink-shell-word
           #:gen-terminal-width
           #:check-property
           #:for-all-property
           #:with-event-capture)
  (:export #:run-tests))
