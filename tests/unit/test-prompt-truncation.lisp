(in-package #:nshell/test)

(in-suite prompt-tests)

(test right-prompt-truncates-to-available-width
  "Right prompt truncation uses visible segment width."
  (let* ((segments (list (nshell.domain.prompting:make-prompt-segment "abcdef" :git)
                         (nshell.domain.prompting:make-prompt-segment "12" :exit-error)))
         (truncated (nshell.presentation::%truncate-segments segments 4)))
    (is (= 4 (nshell.presentation::%segments-visible-width truncated)))
    (is (string= "abcd" (nshell.domain.prompting:prompt-segment-text (first truncated))))
    (is (eq :git (nshell.domain.prompting:prompt-segment-kind (first truncated))))
    (is (null (rest truncated)))))

(test right-prompt-width-counts-cjk-as-two-columns
  "Prompt visible width and truncation use terminal display columns."
  (let* ((segments (list (nshell.domain.prompting:make-prompt-segment "あb" :git)))
         (truncated (nshell.presentation::%truncate-segments segments 2)))
    (is (= 3 (nshell.presentation::%segments-visible-width segments)))
    (is (= 2 (nshell.presentation::%segments-visible-width truncated)))
    (is (string= "あ" (nshell.domain.prompting:prompt-segment-text (first truncated))))))
