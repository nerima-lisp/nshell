(in-package #:nshell.presentation)


(defun autosuggest-token-prefix (input)
  (let ((context (nshell.domain.completion:completion-context-for input)))
    (if (nshell.domain.completion:completion-context-command-position-p context)
        (nshell.domain.completion:completion-context-command context)
        (nshell.domain.completion:completion-context-argument-prefix context))))

(defun %autosuggest-closed-quoted-token-p (input start end)
  ;; A closed quoted token needs at least two characters: an opening quote and a
  ;; matching closing quote.  A lone quote (end - start = 1) is still open.
  (and (< (1+ start) end)
       (member (char input start) '(#\" #\') :test #'char=)
       (char= (char input start) (char input (1- end)))))

(defun completion-suggestion (knowledge-base input &key path)
  (when (and knowledge-base
             (not (nshell.domain.parsing:shell-input-blank-p input)))
    (handler-case
        (let* ((prefix (autosuggest-token-prefix input))
               (candidates (nshell.domain.completion:complete knowledge-base
                                                              input
                                                              :path path))
               (text (if (or (null candidates)
                             (some (lambda (candidate)
                                     (member (nshell.domain.completion:candidate-kind candidate)
                                             '(:file :directory)
                                             :test #'eq))
                                   candidates))
                         (nshell.domain.completion:candidate-text (first candidates))
                         (nshell.presentation::completion-common-prefix candidates))))
          (when text
            (when (and (<= (length prefix) (length text))
                       (string-equal prefix text :end2 (length prefix))
                       (< (length prefix) (length text)))
              (let* ((context (nshell.presentation::%completion-token-context
                               input
                               (length input)))
                     (token-bounds (nshell.presentation::completion-token-context-bounds
                                    context))
                     (token-start (nshell.presentation::completion-token-slice-start
                                   token-bounds))
                     (token-end (nshell.presentation::completion-token-slice-end
                                 token-bounds))
                     (quote-context (nshell.presentation::completion-token-context-quote-context
                                     context))
                     (escaped-prefix (nshell.presentation::%completion-insertion-text
                                      prefix
                                      :quote-context quote-context))
                     (escaped-text (nshell.presentation::%completion-insertion-text
                                    text
                                    :quote-context quote-context)))
                  (unless (%autosuggest-closed-quoted-token-p input token-start token-end)
                    (subseq escaped-text (length escaped-prefix)))))))
      (error () nil))))

(defun compute-suggestion (history input &key knowledge-base path)
  (unless (nshell.domain.parsing:shell-input-blank-p input)
    (or (nshell.application:history-suggestion history input)
        (completion-suggestion knowledge-base input :path path))))

(defun accept-suggestion (input suggestion)
  (concatenate 'string input suggestion))
