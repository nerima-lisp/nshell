(in-package #:nshell/test)

(def-suite input-state-tests
  :description "Pure REPL input-state reducer tests"
  :in nshell-tests)

(in-suite input-state-tests)

(test input-state-raw-constructor-is-internal-boundary
  (let ((state (nshell.presentation:make-input-state :buffer "abc" :cursor-pos 2)))
    (is (nshell.presentation:input-state-p state))
    (is (string= "abc" (nshell.presentation:input-state-buffer state)))
    (is (= 2 (nshell.presentation:input-state-cursor-pos state)))
    (is (eq :insert (nshell.presentation:input-state-mode state)))
    (is (fboundp 'nshell.presentation::%make-input-state))))
