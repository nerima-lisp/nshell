(in-package #:nshell/test)

(describe "input-state-ask-mode-tests"
  (it "enters-ask-mode-with-the-unbound-control-right-bracket-chord"
    (let ((state (input-state :buffer "git status"
                              :cursor-pos 10
                              :suggestion " --short"
                              :abbreviation-expander (lambda (token)
                                                       (declare (ignore token))
                                                       "expanded"))))
      (multiple-value-bind (ask-state output)
          (reduce-once state :ctrl-right-bracket)
        (expect :ask :to-be (nshell.presentation:input-state-mode ask-state))
        (expect :ask-start :to-be output)
        (expect nil :to-be (nshell.presentation:input-state-suggestion ask-state))
        (expect "git status" :to-equal
                (nshell.presentation:input-state-buffer ask-state)))))

  (it "keeps-natural-language-editing-free-of-suggestions-abbreviations-and-history-expansion"
    (let ((state (input-state :mode :ask
                              :buffer "!!"
                              :cursor-pos 2
                              :suggestion " command"
                              :abbreviation-expander (lambda (token)
                                                       (declare (ignore token))
                                                       "expanded"))))
      (multiple-value-bind (edited output)
          (reduce-once state :char #\!)
        (expect :redraw :to-be output)
        (expect "!!!" :to-equal (nshell.presentation:input-state-buffer edited))
        (expect nil :to-be (nshell.presentation:input-state-suggestion edited)))
      (multiple-value-bind (waiting output)
          (reduce-once state :enter)
        (expect :ask-waiting :to-be (nshell.presentation:input-state-mode waiting))
        (expect :ask-submit :to-be output))))

  (it "cancels-ask-input-with-control-g-and-cancels-a-waiting-turn-with-control-c"
    (let ((ask-state (input-state :mode :ask :buffer "question" :cursor-pos 8)))
      (multiple-value-bind (normal output)
          (reduce-once ask-state :ctrl-g)
        (expect :insert :to-be (nshell.presentation:input-state-mode normal))
        (expect :ask-cancel :to-be output)))
    (let ((waiting-state (input-state :mode :ask-waiting
                                      :buffer "question"
                                      :cursor-pos 8)))
      (multiple-value-bind (waiting output)
          (reduce-once waiting-state :ctrl-c)
        (expect :ask-waiting :to-be (nshell.presentation:input-state-mode waiting))
        (expect :ask-cancel-turn :to-be output))))

  (it "uses-the-same-chord-from-vi-normal-mode"
    (let ((*vi-mode-enabled* t))
      (let ((normal (reduce-once-state (input-state :buffer "echo hi"
                                                     :cursor-pos 7)
                                       :escape)))
        (multiple-value-bind (ask-state output)
            (reduce-once normal :ctrl-right-bracket)
          (expect :ask :to-be (nshell.presentation:input-state-mode ask-state))
          (expect :ask-start :to-be output))))))
