(in-package #:nshell.domain.completion)

(define-value-struct %completion-help-command-facts
  ((subcommands nil :type list)
   (flags nil :type list)
   (option-values nil :type list)
   (option-value-kinds nil :type list))
  :public-accessors nil
  :constructor %make-completion-help-command-facts)

(define-value-struct %completion-help-scan-state
  ((subcommands nil :type list)
   (flags nil :type list)
   (option-values nil :type list)
   (option-value-kinds nil :type list)
   (collecting-subcommands-p nil :type boolean))
  :public-accessors nil
  :constructor %make-completion-help-scan-state)

(define-value-struct %completion-help-line-facts
  ((kind :other :type (member :heading :blank :subcommand :other :stop-subcommands))
   (options nil :type list)
   (values nil :type list)
   (option-value-kinds nil :type list)
   (subcommand-name nil :type (or null string)))
  :public-accessors nil
  :constructor %make-completion-help-line-facts)

(defparameter *completion-help-section-headings*
  '("commands:" "command:" "subcommands:" "subcommand:"))

(defparameter *completion-help-option-delimiters*
  '(#\Space #\Tab #\, #\; #\) #\( #\[ #\] #\{ #\}))

(defparameter *completion-help-option-trim-chars*
  '(#\Space #\Tab #\, #\; #\. #\: #\) #\( #\[ #\] #\{ #\}
    #\< #\> #\' #\"))

(defparameter *completion-help-value-kind-tokens*
  '(("file" . :file)
    ("path" . :file)
    ("filename" . :file)
    ("file-path" . :file)
    ("filepath" . :file)
    ("directory" . :directory)
    ("dir" . :directory)
    ("folder" . :directory)))

(defparameter *completion-help-enum-delimiters*
  '(#\Space #\Tab #\Newline #\Return))
