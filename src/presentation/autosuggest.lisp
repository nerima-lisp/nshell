(in-package #:nshell.presentation)


(defun autosuggest-token-prefix (input)
  (let ((context (nshell.domain.completion:completion-context-for input)))
    (if (nshell.domain.completion:completion-context-command-position-p context)
        (nshell.domain.completion:completion-context-command context)
        (nshell.domain.completion:completion-context-argument-prefix context))))

(defun %autosuggest-closed-quoted-token-p (input start end)
  (and (< start end)
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
              (let* ((token-bounds (nshell.presentation::%completion-token-bounds
                                     input
                                     (length input)))
                     (token-start (nshell.presentation::completion-token-slice-start
                                    token-bounds))
                     (token-end (nshell.presentation::completion-token-slice-end
                                  token-bounds))
                     (quote-context (nshell.presentation::%completion-quote-context
                                      input token-start token-end))
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
