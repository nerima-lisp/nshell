(in-package #:nshell/test)
(in-suite e2e-tests)

(test e2e-abbreviation-expands-on-enter-before-execution
  (with-repl-test-state
    (setf (gethash "say" nshell.presentation::*abbreviations*) "echo hello")
    (setf nshell.presentation::*input-state*
          (nshell.presentation::make-repl-input-state :buffer "say"))
    (multiple-value-bind (state output)
        (reduce-once nshell.presentation::*input-state* :enter)
      (setf nshell.presentation::*input-state* state)
      (is-input-state state :buffer "echo hello" :cursor-pos 10)
      (is (eq :execute output))
      (let ((rendered (capture-process-output-event output)))
        (is (search "hello" rendered))
        (is (= 0 nshell.presentation::*last-exit-code*))
        (is (string= ""
                     (nshell.presentation:input-state-buffer
                      nshell.presentation::*input-state*)))))))

(test e2e-command-position-abbreviation-expands-only-at-command-position
  (with-repl-test-state
    (setf (gethash "gco" nshell.presentation::*abbreviations*)
          (nshell.domain.abbreviation:make-abbreviation
           :expansion "echo command"
           :position :command))
    (setf nshell.presentation::*input-state*
          (nshell.presentation::make-repl-input-state :buffer "echo gco"))
    (multiple-value-bind (state output)
        (reduce-once nshell.presentation::*input-state* :enter)
      (is-input-state state :buffer "echo gco" :cursor-pos 8)
      (is (eq :execute output)))
    (setf nshell.presentation::*input-state*
          (nshell.presentation::make-repl-input-state :buffer "gco"))
    (multiple-value-bind (state output)
        (reduce-once nshell.presentation::*input-state* :enter)
      (is-input-state state :buffer "echo command" :cursor-pos 12)
      (is (eq :execute output)))))

(test e2e-meta-s-input-cycle
  (let* ((events (read-key-events-from-string
                  (concatenate 'string "apt update" (esc-sequence "s"))))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "sudo apt update" line))
    (with-complete-command-line (result ast line)
      (is (string= "sudo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("apt" "update")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-t-input-cycle
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "gti status" 'list)
                                  (make-list 8 :initial-element (code-char 2))
                                  (list (code-char 20)))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "git status" line))
    (with-complete-command-line (result ast line)
      (is (string= "git" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("status")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-alt-t-input-cycle
  (let* ((events (read-key-events-from-string
                  (concatenate 'string "echo world hello" (esc-sequence "t"))))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo hello world" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hello" "world")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-alt-u-input-cycle
  (let* ((events (read-key-events-from-string
                  (concatenate 'string "echo hello" (esc-sequence "u"))))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo HELLO" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("HELLO")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-bracketed-paste-normalizes-newlines-and-undos-once
  (let* ((raw-paste (format nil "echo one~C~Cecho two~C"
                            #\Return #\Newline #\Return))
         (expected (format nil "echo one~%echo two~%"))
         (events (read-key-events-from-string
                  (concatenate 'string
                               (esc-sequence "[200~")
                               raw-paste
                               (esc-sequence "[201~"))))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events)))
    (is-input-state state
                    :buffer expected
                    :cursor-pos (length expected))
    (multiple-value-bind (undone output)
        (reduce-once state :ctrl-underscore)
      (is-input-state undone :buffer "" :cursor-pos 0)
      (is (eq :suggest-update output)))))

(test e2e-alt-t-preserves-quoted-word-cycle
  (let* ((events (read-key-events-from-string
                  (concatenate 'string
                               "echo tail \"hello world\""
                               (esc-sequence "t"))))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo \"hello world\" tail" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hello world" "tail")
                 (nshell.domain.parsing:command-node-arg-values ast))))))

(test e2e-alt-d-preserves-quoted-word-cycle
  (let* ((events (read-key-events-from-string (esc-sequence "d")))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "echo \"hello world\" tail"
                  :cursor-pos 4)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo tail" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("tail")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-k-replaces-line-suffix
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "echo hello world" 'list)
                                  (make-list 5 :initial-element (code-char 2))
                                  (list (code-char 11))
                                  (coerce "shell" 'list))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo hello shell" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hello" "shell")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-u-yank-restores-killed-line
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "echo hello world" 'list)
                                  (list (code-char 21)
                                        (code-char 25)))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo hello world" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hello" "world")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-w-yank-restores-escaped-word
  (let* ((events (read-key-events-from-string
                  (coerce (append (coerce "echo hello\\ world" 'list)
                                  (list (code-char 23)
                                        (code-char 25)))
                          'string)))
         (state (apply-key-events-to-input-state
                 (input-state)
                 events))
         (line (nshell.presentation:input-state-buffer state)))
    (is (string= "echo hello\\ world" line))
    (with-complete-command-line (result ast line)
      (is (string= "echo" (nshell.domain.parsing:command-node-command ast)))
      (is (equal '("hello world")
                 (nshell.domain.parsing:command-node-args ast))))))

(test e2e-ctrl-g-cancels-completion-session
  (let* ((events (read-key-events-from-string (string (code-char 7))))
         (state (apply-key-events-to-input-state
                 (input-state
                  :buffer "g"
                  :cursor-pos 1
                  :completion-index 0
                  :completion-base-buffer "g"
                  :completion-base-cursor 1
                  :last-candidates '("git" "grep")
                  :suggestion "it")
                 events)))
    (is-input-state state
                    :buffer "g"
                    :cursor-pos 1
                    :completion-index -1
                    :completion-base-buffer nil
                    :completion-base-cursor nil
                    :last-candidates nil
                    :suggestion nil)))

