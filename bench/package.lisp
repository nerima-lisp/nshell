(defpackage #:nshell/benchmark (:use #:cl)
  (:import-from
    #:nshell.domain.completion
    #:make-empty-knowledge-base
    #:kb-add-command
    #:kb-add-option
    #:complete
    #:candidate-text
    #:candidate-kind
    #:*path-command-directory-files-fn*
    #:*path-command-executable-p-fn*
    #:*path-command-directory-map-fn*)
  (:export #:run-completion-benchmark))
