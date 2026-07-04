(in-package #:nshell/test)

(in-suite prompt-tests)

(test pbt-prompt-truncation-never-exceeds-width
  "Generated prompt segments truncated to a terminal width never exceed that width."
  (check-property (:trials 50)
      ((seg-text (gen-prompt-text) #'shrink-prompt-text)
       (term-width (gen-terminal-width) nil))
    (let* ((segment (list (nshell.domain.prompting:make-prompt-segment seg-text :git)))
           (truncated (nshell.presentation::%truncate-segments segment term-width)))
      (<= (nshell.presentation::%segments-visible-width truncated) term-width))))

(test pbt-prompt-multi-segment-truncation
  "Generated multi-segment prompts truncated to terminal width never exceed that width."
  (check-property (:trials 50)
      ((text-a (gen-prompt-text) #'shrink-prompt-text)
       (text-b (gen-prompt-text) #'shrink-prompt-text)
       (term-width (gen-terminal-width) nil))
    (let* ((segments (list (nshell.domain.prompting:make-prompt-segment text-a :git)
                           (nshell.domain.prompting:make-prompt-segment text-b :exit-error)))
           (truncated (nshell.presentation::%truncate-segments segments term-width)))
      (<= (nshell.presentation::%segments-visible-width truncated) term-width))))

(test pbt-prompt-cjk-truncation-respects-char-width
  "Generated CJK-mixed prompt text truncation never exceeds specified width."
  (check-property (:trials 50)
      ((cjk-text (gen-prompt-text :cjk-probability 0.7) #'shrink-prompt-text)
       (term-width (gen-terminal-width) nil))
    (let* ((segment (list (nshell.domain.prompting:make-prompt-segment cjk-text :git)))
           (truncated (nshell.presentation::%truncate-segments segment term-width))
           (visible-width (nshell.presentation::%segments-visible-width truncated)))
      (and (<= visible-width term-width)
           (if (< (nshell.presentation::%segments-visible-width segment) term-width)
               (string= cjk-text
                        (nshell.domain.prompting:prompt-segment-text (first truncated)))
               t)))))
