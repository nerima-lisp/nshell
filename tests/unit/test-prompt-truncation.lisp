(in-package #:nshell/test)

(describe "prompt-tests"
  (it "right-prompt-truncates-to-available-width"
    "Right prompt truncation uses visible segment width."
    (let* ((segments (list (nshell.domain.prompting:make-prompt-segment "abcdef" :git)
                           (nshell.domain.prompting:make-prompt-segment "12" :exit-error)))
           (truncated (nshell.presentation::%truncate-segments segments 4)))
      (expect 4 :to-equal (nshell.presentation::%segments-visible-width truncated))
      (expect "abcd" :to-equal (nshell.domain.prompting:prompt-segment-text (first truncated)))
      (expect :git :to-be (nshell.domain.prompting:prompt-segment-kind (first truncated)))
      (expect (rest truncated) :to-be-null)))

  (it "right-prompt-width-counts-cjk-as-two-columns"
    "Prompt visible width and truncation use terminal display columns."
    (let* ((segments (list (nshell.domain.prompting:make-prompt-segment "あb" :git)))
           (truncated (nshell.presentation::%truncate-segments segments 2)))
      (expect 3 :to-equal (nshell.presentation::%segments-visible-width segments))
      (expect 2 :to-equal (nshell.presentation::%segments-visible-width truncated))
      (expect "あ" :to-equal (nshell.domain.prompting:prompt-segment-text (first truncated))))))
