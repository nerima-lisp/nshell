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

(test input-state-copy-groups-use-private-values-before-initargs
  (flet ((present-p (name)
           (multiple-value-bind (symbol status)
               (find-symbol name '#:nshell.presentation)
             (and status symbol (or (fboundp symbol)
                                    (find-class symbol nil))))))
    (dolist (old-name '("%COPY-INPUT-STATE-COMPLETION-PLIST"
                        "%COPY-INPUT-STATE-TRANSIENT-PLIST"
                        "%COPY-INPUT-STATE-SESSION-PLIST"))
      (is (not (present-p old-name))))
    (dolist (new-name '("%COPY-INPUT-STATE-COMPLETION-VALUES"
                        "%COPY-INPUT-STATE-TRANSIENT-VALUES"
                        "%COPY-INPUT-STATE-SESSION-VALUES"
                        "%COPY-INPUT-STATE-COMPLETION-INITARGS"
                        "%COPY-INPUT-STATE-TRANSIENT-INITARGS"
                        "%COPY-INPUT-STATE-SESSION-INITARGS"
                        "%INPUT-STATE-COMPLETION-COPY"
                        "%INPUT-STATE-TRANSIENT-COPY"
                        "%INPUT-STATE-SESSION-COPY"))
      (is (present-p new-name)))))

(test input-edit-snapshot-is-private-value
  (let* ((state (nshell.presentation:make-input-state :buffer "abc"
                                                      :cursor-pos 2))
         (snapshot (nshell.presentation::input-edit-snapshot state)))
    (is (nshell.presentation::%input-edit-snapshot-p snapshot))
    (is (not (listp snapshot)))
    (is (string= "abc"
                 (nshell.presentation::%input-edit-snapshot-buffer snapshot)))
    (is (= 2
           (nshell.presentation::%input-edit-snapshot-cursor-pos snapshot)))))
