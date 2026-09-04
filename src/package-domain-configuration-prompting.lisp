;;; Package definitions for configuration and prompt domain values.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpackage #:nshell.domain.configuration
    (:documentation
     "Domain: user configuration and colour themes as values, including the
defaults used when the config file is absent. Parsing and writing the file is
nshell.infrastructure.persistence's job.")
    (:use #:cl)
    (:import-from #:nshell.util #:define-value-struct)
    (:export #:make-theme #:theme-color #:theme-name #:theme-set-color
             #:theme-p #:config-p
             #:make-config #:config-theme
             #:default-theme #:default-config))

  (defpackage #:nshell.domain.prompting
    (:documentation
     "Domain: the prompt as a model -- hostname, directory, last exit code,
duration -- and the rules that turn it into left and right segment lists. Git
status and the clock arrive through the *GIT-STATUS-RESOLVER* and
*PROMPT-TIME-RESOLVER* hooks so that rendering a prompt stays deterministic.")
    (:use #:cl)
    (:import-from #:nshell.util #:define-value-struct)
    (:export #:make-prompt-model #:prompt-model-hostname #:prompt-model-cwd
             #:prompt-model-directory #:prompt-model-exit-code
             #:prompt-model-duration-ms #:prompt-model-segments
             #:prompt-model-right-segments #:prompt-segment
             #:make-prompt-segment #:prompt-segment-text
             #:prompt-segment-kind #:*git-status-resolver*
             #:*prompt-time-resolver*
             #:render-prompt-model #:render-right-prompt-model)))
