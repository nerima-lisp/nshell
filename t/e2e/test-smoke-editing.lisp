(in-package #:nshell/test)

(describe "e2e-tests"
  (it "e2e-end-accepts-autosuggestion-tail"
    (let* ((events (read-key-events-from-string (esc-sequence "[F")))
           (state (apply-key-events-to-input-state
                   (input-state
                    :buffer "git"
                    :cursor-pos 3
                    :suggestion " status")
                   events))
           (line (nshell.presentation:input-state-buffer state)))
      (expect "git status" :to-equal line)
      (with-complete-command-line (result ast line)
        (expect "git" :to-equal (nshell.domain.parsing:command-node-command ast))
        (expect '("status") :to-equal (nshell.domain.parsing:command-node-arg-values ast)))))

  (it "e2e-ctrl-e-accepts-autosuggestion-tail"
    (let* ((events (read-key-events-from-string (string (code-char 5))))
           (state (apply-key-events-to-input-state
                   (input-state
                    :buffer "git"
                    :cursor-pos 3
                    :suggestion " status")
                   events))
           (line (nshell.presentation:input-state-buffer state)))
      (expect "git status" :to-equal line)
      (with-complete-command-line (result ast line)
        (expect "git" :to-equal (nshell.domain.parsing:command-node-command ast))
        (expect '("status") :to-equal (nshell.domain.parsing:command-node-arg-values ast)))))

  (it "e2e-right-and-ctrl-f-accept-autosuggestion-tail"
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
      (expect (nshell.presentation:input-state-buffer right-state) :to-equal (nshell.presentation:input-state-buffer ctrl-f-state))
      (expect "git status" :to-equal (nshell.presentation:input-state-buffer right-state))
      (expect (nshell.presentation:input-state-cursor-pos right-state) :to-equal (nshell.presentation:input-state-cursor-pos ctrl-f-state))
      (expect (nshell.presentation:input-state-suggestion right-state) :to-be-null)
      (expect (nshell.presentation:input-state-suggestion ctrl-f-state) :to-be-null)))

  (it "e2e-alt-right-accepts-autosuggestion-operator-then-command"
    (let* ((events (read-key-events-from-string
                    (concatenate 'string (esc-sequence "f") (esc-sequence "f"))))
           (state (apply-key-events-to-input-state
                   (input-state
                    :buffer "git status"
                    :cursor-pos 10
                    :suggestion " | grep modified")
                   events))
           (line (nshell.presentation:input-state-buffer state)))
      (expect "git status | grep" :to-equal line)
      (expect " modified" :to-equal (nshell.presentation:input-state-suggestion state))
      (with-complete-command-line (result ast line)
        (let ((commands (nshell.domain.parsing:pipeline-node-commands ast)))
          (expect 2 :to-equal (length commands))
          (expect "git" :to-equal (nshell.domain.parsing:command-node-command (first commands)))
          (expect '("status") :to-equal (nshell.domain.parsing:command-node-arg-values (first commands)))
          (expect "grep" :to-equal (nshell.domain.parsing:command-node-command (second commands)))))))

  (it "e2e-ctrl-right-accepts-autosuggestion-word"
    (let* ((events (read-key-events-from-string (esc-sequence "[1;5C")))
           (state (apply-key-events-to-input-state
                   (input-state
                    :buffer "git"
                    :cursor-pos 3
                    :suggestion " status --short")
                   events))
           (line (nshell.presentation:input-state-buffer state)))
      (expect "git status" :to-equal line)
      (expect " --short" :to-equal (nshell.presentation:input-state-suggestion state))
      (with-complete-command-line (result ast line)
        (expect "git" :to-equal (nshell.domain.parsing:command-node-command ast))
        (expect '("status") :to-equal (nshell.domain.parsing:command-node-arg-values ast)))))

  (it "e2e-alt-right-accepts-attached-redirection-target"
    (let* ((events (read-key-events-from-string (esc-sequence "f")))
           (state (apply-key-events-to-input-state
                   (input-state
                    :buffer "echo hi"
                    :cursor-pos 7
                    :suggestion " >out.txt && cat out.txt")
                   events))
           (line (nshell.presentation:input-state-buffer state)))
      (expect "echo hi >out.txt" :to-equal line)
      (expect " && cat out.txt" :to-equal (nshell.presentation:input-state-suggestion state))
      (with-complete-command-line (result ast line)
        (expect "echo" :to-equal (nshell.domain.parsing:command-node-command ast))
        (expect '("hi" ">" "out.txt") :to-equal (nshell.domain.parsing:command-node-arg-values ast)))))

  (it "e2e-control-h-backspace-input-cycle"
    (let* ((events (read-key-events-from-string
                    (coerce (append (coerce "git statusx" 'list)
                                    (list (code-char 8)))
                            'string)))
           (state (apply-key-events-to-input-state
                   (input-state)
                   events))
           (line (nshell.presentation:input-state-buffer state)))
      (expect "git status" :to-equal line)
      (with-complete-command-line (result ast line)
        (expect "git" :to-equal (nshell.domain.parsing:command-node-command ast))
        (expect '("status") :to-equal (nshell.domain.parsing:command-node-arg-values ast)))))

  (it "e2e-ctrl-d-deletes-character-under-cursor"
    (let* ((events (read-key-events-from-string
                    (coerce (append (coerce "echo hxello" 'list)
                                    (make-list 5 :initial-element (code-char 2))
                                    (list (code-char 4)))
                            'string)))
           (state (apply-key-events-to-input-state
                   (input-state)
                   events))
           (line (nshell.presentation:input-state-buffer state)))
      (expect "echo hello" :to-equal line)
      (with-complete-command-line (result ast line)
        (expect "echo" :to-equal (nshell.domain.parsing:command-node-command ast))
        (expect '("hello") :to-equal (nshell.domain.parsing:command-node-arg-values ast)))))

  (it "e2e-ctrl-d-on-empty-input-requests-quit"
    (let* ((events (read-key-events-from-string (string (code-char 4))))
           (event (first events)))
      (multiple-value-bind (state output)
          (nshell.presentation:reduce-input-state (input-state) event)
        (is-input-state state
                        :buffer ""
                        :cursor-pos 0)
        (expect :quit :to-be output))))

  (it "e2e-ctrl-l-clears-screen-without-losing-editing-session"
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
          (expect :clear-screen :to-be output)
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
            (expect (search "[2J" rendered) :to-be-truthy)
            (expect (search "[1;1H" rendered) :to-be-truthy)))
        (is-input-state nshell.presentation::*input-state*
                        :buffer "git"
                        :cursor-pos 3
                        :completion-index 0
                        :completion-base-buffer "git"
                        :completion-base-cursor 3
                        :last-candidates '("git" "grep")
                        :suggestion " status"))))

  (it "e2e-ctrl-underscore-undo-input-cycle"
    (let* ((events (read-key-events-from-string
                    (coerce (append (coerce "git statusx" 'list)
                                    (list (code-char 31)))
                            'string)))
           (state (apply-key-events-to-input-state
                   (input-state)
                   events))
           (line (nshell.presentation:input-state-buffer state)))
      (expect "git status" :to-equal line)
      (with-complete-command-line (result ast line)
        (expect "git" :to-equal (nshell.domain.parsing:command-node-command ast))
        (expect '("status") :to-equal (nshell.domain.parsing:command-node-arg-values ast)))))

  (it "e2e-alt-y-yank-pop-input-cycle"
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
      (expect "echo second" :to-equal line)
      (with-complete-command-line (result ast line)
        (expect "echo" :to-equal (nshell.domain.parsing:command-node-command ast))
        (expect '("second") :to-equal (nshell.domain.parsing:command-node-arg-values ast)))))

  (it "e2e-multiline-quoted-command-cycle"
    (let* ((history (history-kit:make-history))
           (line (format nil "echo \"hello~%world\"")))
      (with-complete-command-line (result ast line)
        (expect (nshell.domain.parsing:command-node-p ast) :to-be-truthy)
        (expect (list (format nil "hello~%world")) :to-equal (nshell.domain.parsing:command-node-arg-values ast)))
      (history-kit:history-add history line)
      (expect 1 :to-equal (history-kit:history-count history))))

  (it "e2e-newline-sequence-executes-both-commands"
    (with-complete-command-line (result ast (format nil "echo one~%echo two"))
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (multiple-value-bind (output-text code)
          (call-repl-execute-ast ast)
        (expect 0 :to-equal code)
        (expect (format nil "one~%two~%") :to-equal output-text))))

  (it "e2e-here-document-tail-command-executes"
    (with-complete-command-line (result ast
                                        (format nil "cat << EOF~%hello~%EOF~%echo done"))
      (expect (nshell.domain.parsing:parse-errors result) :to-be-null)
      (multiple-value-bind (output-text code)
          (call-repl-execute-ast ast)
        (expect 0 :to-equal code)
        (expect (format nil "hello~%done~%") :to-equal output-text)))))
