(defpackage #:nshell/benchmark (:use #:cl)
  (:import-from
    #:nshell.domain.completion
    #:make-empty-knowledge-base
    #:kb-add-command
    #:kb-add-option
    #:complete
    #:candidate-text
    #:candidate-kind)
  (:export #:run-completion-benchmark))
