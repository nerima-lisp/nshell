(in-package #:nshell.domain.completion)

(defstruct (%completion-help-command-facts
            (:constructor %make-completion-help-command-facts
                (subcommands flags option-values option-value-kinds))
            (:conc-name %completion-help-command-facts-))
  (subcommands nil :type list :read-only t)
  (flags nil :type list :read-only t)
  (option-values nil :type list :read-only t)
  (option-value-kinds nil :type list :read-only t))

(defstruct (%completion-help-scan-state
            (:constructor %make-completion-help-scan-state ())
            (:conc-name %completion-help-scan-state-))
  (subcommands nil :type list)
  (flags nil :type list)
  (option-values nil :type list)
  (option-value-kinds nil :type list)
  (collecting-subcommands-p nil :type boolean))

(defstruct (%completion-help-line-facts
            (:constructor %make-completion-help-line-facts
                (kind options values option-value-kinds subcommand-name))
            (:conc-name %completion-help-line-facts-))
  (kind :other :type (member :heading :blank :subcommand :other :stop-subcommands)
   :read-only t)
  (options nil :type list :read-only t)
  (values nil :type list :read-only t)
  (option-value-kinds nil :type list :read-only t)
  (subcommand-name nil :type (or null string) :read-only t))

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
