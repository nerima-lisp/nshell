(in-package #:nshell/test)
(in-suite e2e-tests)

(test e2e-end-accepts-autosuggestion-tail
  (let* ((events (read-key-events-from-string (esc-sequence "[F")))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "git"
                  :cursor-pos 3
                  :suggestion " status")
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status" line))
    (with-complete-command-line (result ast line)
      (is (string= "git" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("status")
                 (nshell.domain.parsing:command-node-arg-values ast))))))

(test e2e-ctrl-e-accepts-autosuggestion-tail
  (let* ((events (read-key-events-from-string (string (code-char 5))))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "git"
                  :cursor-pos 3
                  :suggestion " status")
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status" line))
    (with-complete-command-line (result ast line)
      (is (string= "git" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("status")
                 (nshell.domain.parsing:command-node-arg-values ast))))))

(test e2e-right-and-ctrl-f-accept-autosuggestion-tail
  "Decoded Right and Ctrl-F both accept the complete autosuggestion tail at line end."
  (let* ((right-events (read-key-events-from-string (esc-sequence "[C")))
         (ctrl-f-events (read-key-events-from-string (string (code-char 6))))
         (right-state (apply-key-events-to-input-state
                       (input-state
                        :buffer "git"
                        :cursor-pos 3
                        :suggestion " status")
                       right-events))
         (ctrl-f-state (apply-key-events-to-input-state
                        (input-state
                        :buffer "git"
                        :cursor-pos 3
                        :suggestion " status")
                        ctrl-f-events)))
    (is (string= (nshell.presentation:input-state-buffer right-state)
                 (nshell.presentation:input-state-buffer ctrl-f-state)))
    (is (string= "git status"
                 (nshell.presentation:input-state-buffer right-state)))
    (is (= (nshell.presentation:input-state-cursor-pos right-state)
           (nshell.presentation:input-state-cursor-pos ctrl-f-state)))
    (is (null (nshell.presentation:input-state-suggestion right-state)))
    (is (null (nshell.presentation:input-state-suggestion ctrl-f-state)))))

(test e2e-alt-right-accepts-autosuggestion-operator-then-command
  (let* ((events (read-key-events-from-string
                  (concatenate 'string (esc-sequence "f") (esc-sequence "f"))))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "git status"
                  :cursor-pos 10
                  :suggestion " | grep modified")
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status | grep" line))
    (is (string= " modified"
                 (nshell.presentation:input-state-suggestion state)))
    (with-complete-command-line (result ast line)
      (let ((commands (nshell.domain.parsing:pipeline-node-commands ast)))
        (is (= 2 (length commands)))
        (is (string= "git"
                     (nshell.domain.parsing:command-node-command (first commands))))
        (is (equal '("status")
                   (nshell.domain.parsing:command-node-arg-values (first commands))))
        (is (string= "grep"
                     (nshell.domain.parsing:command-node-command (second commands))))))))

(test e2e-ctrl-right-accepts-autosuggestion-word
  (let* ((events (read-key-events-from-string (esc-sequence "[1;5C")))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "git"
                  :cursor-pos 3
                  :suggestion " status --short")
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status" line))
    (is (string= " --short"
                 (nshell.presentation:input-state-suggestion state)))
    (with-complete-command-line (result ast line)
      (is (string= "git" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("status")
                 (nshell.domain.parsing:command-node-arg-values ast))))))

(test e2e-alt-right-accepts-attached-redirection-target
  (let* ((events (read-key-events-from-string (esc-sequence "f")))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "echo hi"
                  :cursor-pos 7
                  :suggestion " >out.txt && cat out.txt")
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo hi >out.txt" line))
    (is (string= " && cat out.txt"
                 (nshell.presentation:input-state-suggestion state)))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hi" ">" "out.txt")
                 (nshell.domain.parsing:command-node-arg-values ast))))))

(test e2e-control-h-backspace-input-cycle
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "git statusx" 'list)
                                  (list (code-char 8)))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status" line))
    (with-complete-command-line (result ast line)
      (is (string= "git" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("status")
                 (nshell.domain.parsing:command-node-arg-values ast))))))

(test e2e-ctrl-d-deletes-character-under-cursor
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "echo hxello" 'list)
                                  (make-list 5 :initial-element (code-char 2))
                                  (list (code-char 4)))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo hello" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hello")
                 (nshell.domain.parsing:command-node-arg-values ast))))))

(test e2e-ctrl-d-on-empty-input-requests-quit
  (let* ((events (read-key-events-from-string (string (code-char 4))))
         (event (first events)))
    (multiple-value-bind (state output)
        (nshell.presentation:reduce-input-state (input-state) event)
      (is-input-state state
                      :buffer ""
                      :cursor-pos 0)
      (is (eq :quit output)))))

(test e2e-ctrl-l-clears-screen-without-losing-editing-session
  (with-repl-test-state
    (let ((state (input-state
                  :buffer "git"
                  :cursor-pos 3
                  :completion-index 0
                  :completion-base-buffer "git"
                  :completion-base-cursor 3
                  :last-candidates '("git" "grep")
                  :suggestion " status")))
      (multiple-value-bind (next-state output)
          (nshell.presentation:reduce-input-state
           state
           (input-key-event :ctrl-l))
        (is (eq :clear-screen output))
        (is-input-state next-state
                        :buffer "git"
                        :cursor-pos 3
                        :completion-index 0
                        :completion-base-buffer "git"
                        :completion-base-cursor 3
                        :last-candidates '("git" "grep")
                        :suggestion " status")
        (setf nshell.presentation::*input-state* next-state)
        (let ((rendered (capture-process-output-event output)))
          (is (search "[2J" rendered))
          (is (search "[1;1H" rendered))))
      (is-input-state nshell.presentation::*input-state*
                      :buffer "git"
                      :cursor-pos 3
                      :completion-index 0
                      :completion-base-buffer "git"
                      :completion-base-cursor 3
                      :last-candidates '("git" "grep")
                      :suggestion " status"))))

(test e2e-ctrl-underscore-undo-input-cycle
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "git statusx" 'list)
                                  (list (code-char 31)))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status" line))
    (with-complete-command-line (result ast line)
      (is (string= "git" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("status")
                 (nshell.domain.parsing:command-node-arg-values ast))))))

(test e2e-alt-y-yank-pop-input-cycle
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "echo first second" 'list)
                                  (list (code-char 23)
                                        (code-char 23)
                                        (code-char 25))
                                  (coerce (esc-sequence "y") 'list))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo second" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("second")
                 (nshell.domain.parsing:command-node-arg-values ast))))))

(test e2e-multiline-quoted-command-cycle
  (let* ((history (nshell.domain.history:make-command-history))
         (line (format nil "echo \"hello~%world\"")))
    (with-complete-command-line (result ast line)
      (is (nshell.domain.parsing:command-node-p ast))
      (is (equal (list (format nil "hello~%world"))
                 (nshell.domain.parsing:command-node-arg-values ast))))
    (nshell.domain.history:history-add history line)
    (is (= 1 (nshell.domain.history:history-size history)))))

(test e2e-newline-sequence-executes-both-commands
  (with-complete-command-line (result ast (format nil "echo one~%echo two"))
    (is (null (nshell.domain.parsing:parse-errors result)))
    (multiple-value-bind (output-text code)
        (call-repl-execute-ast ast)
      (is (= 0 code))
      (is (string= (format nil "one~%two~%") output-text)))))

(test e2e-here-document-tail-command-executes
  (with-complete-command-line (result ast
                                      (format nil "cat << EOF~%hello~%EOF~%echo done"))
    (is (null (nshell.domain.parsing:parse-errors result)))
    (multiple-value-bind (output-text code)
        (call-repl-execute-ast ast)
      (is (= 0 code))
      (is (string= (format nil "hello~%done~%") output-text)))))
