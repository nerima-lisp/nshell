(in-package #:nshell/test)

(describe "input-state-tests"
  (it "pbt-input-state-alt-right-eventually-accepts-suggestion"
    "Repeated word acceptance consumes the whole generated autosuggestion tail."
    (check-property (:trials 50)
        ((buffer (gen-prompt-text :max-length 16) #'shrink-prompt-text)
         (suggestion (gen-prompt-text :min-length 1 :max-length 16)
                     #'shrink-prompt-text))
      (let ((state (input-state
                    :buffer buffer
                    :cursor-pos (length buffer)
                    :suggestion suggestion)))
        (loop repeat (length suggestion)
              while (nshell.presentation:input-state-suggestion state)
              do (setf state (reduce-once-state state :alt-right)))
        (and (string= (concatenate 'string buffer suggestion)
                      (nshell.presentation:input-state-buffer state))
             (= (length (nshell.presentation:input-state-buffer state))
                (nshell.presentation:input-state-cursor-pos state))
             (null (nshell.presentation:input-state-suggestion state))))))

  (it "pbt-input-state-ctrl-right-matches-alt-right-suggestion-step-at-eol"
    "Ctrl-Right and Alt-Right accept the same single autosuggestion step at EOL."
    (check-property (:trials 50)
        ((buffer (gen-prompt-text :max-length 16) #'shrink-prompt-text)
         (suggestion (gen-prompt-text :min-length 1 :max-length 16)
                     #'shrink-prompt-text))
      (let ((state (input-state
                    :buffer buffer
                    :cursor-pos (length buffer)
                    :suggestion suggestion)))
        (multiple-value-bind (alt-state alt-output) (reduce-once state :alt-right)
          (multiple-value-bind (ctrl-state ctrl-output)
              (reduce-once state :ctrl-right)
            (and (eq alt-output ctrl-output)
                 (string= (nshell.presentation:input-state-buffer alt-state)
                          (nshell.presentation:input-state-buffer ctrl-state))
                 (= (nshell.presentation:input-state-cursor-pos alt-state)
                    (nshell.presentation:input-state-cursor-pos ctrl-state))
                 (equal (nshell.presentation:input-state-suggestion alt-state)
                        (nshell.presentation:input-state-suggestion ctrl-state))))))))

  (it "pbt-input-state-alt-right-accepts-escaped-space-suggestion-token"
    "Alt-Right treats a backslash-escaped separator as part of one suggestion token."
    (check-property (:trials 50)
        ((buffer (gen-prompt-text :max-length 16) #'shrink-prompt-text)
         (left (gen-shell-word :min-length 1 :max-length 8)
               #'shrink-prompt-text)
         (right (gen-shell-word :min-length 1 :max-length 8)
                #'shrink-prompt-text)
         (tail (gen-shell-word :min-length 1 :max-length 8)
               #'shrink-prompt-text))
      (let* ((accepted (format nil " ~a\\ ~a" left right))
             (remaining (format nil " ~a" tail))
             (state (input-state
                     :buffer buffer
                     :cursor-pos (length buffer)
                     :suggestion (concatenate 'string accepted remaining))))
        (multiple-value-bind (new-state output) (reduce-once state :alt-right)
          (and (eq :suggest-update output)
               (string= (concatenate 'string buffer accepted)
                        (nshell.presentation:input-state-buffer new-state))
               (= (length (nshell.presentation:input-state-buffer new-state))
                  (nshell.presentation:input-state-cursor-pos new-state))
               (string= remaining
                        (nshell.presentation:input-state-suggestion new-state)))))))

  (it "pbt-input-state-alt-right-accepts-shell-operators-before-next-word"
    "Alt-Right accepts parser operator tokens separately from following words."
    (check-property (:trials 50)
        ((buffer (gen-prompt-text :max-length 16) #'shrink-prompt-text)
         (operator-index (gen-in-range 0 6))
         (tail (gen-shell-word :min-length 1 :max-length 8)
               #'shrink-prompt-text))
      (let* ((operator (nth operator-index '("|" "&&" "||" ";" ">" ">>" "<")))
             (accepted (format nil " ~a" operator))
             (remaining (format nil " ~a" tail))
             (state (input-state
                     :buffer buffer
                     :cursor-pos (length buffer)
                     :suggestion (concatenate 'string accepted remaining))))
        (multiple-value-bind (new-state output) (reduce-once state :alt-right)
          (and (eq :suggest-update output)
               (string= (concatenate 'string buffer accepted)
                        (nshell.presentation:input-state-buffer new-state))
               (= (length (nshell.presentation:input-state-buffer new-state))
                  (nshell.presentation:input-state-cursor-pos new-state))
               (string= remaining
                        (nshell.presentation:input-state-suggestion new-state)))))))

  (it "pbt-input-state-ctrl-g-cancels-completion-session"
    "Ctrl-G cancels transient completion/suggestion state without changing text."
    (check-property (:trials 50)
        ((buffer (gen-prompt-text :max-length 16) #'shrink-prompt-text)
         (candidate (gen-shell-word :min-length 1 :max-length 12)
                    #'shrink-prompt-text)
         (suggestion (gen-prompt-text :min-length 1 :max-length 12)
                    #'shrink-prompt-text))
      (let* ((cursor (length buffer))
             (state (input-state
                     :buffer buffer
                     :cursor-pos cursor
                     :completion-index 0
                     :completion-base-buffer buffer
                     :completion-base-cursor cursor
                     :last-candidates (list candidate)
                     :suggestion suggestion)))
        (multiple-value-bind (new-state output) (reduce-once state :ctrl-g)
          (and (eq :redraw output)
               (string= buffer
                        (nshell.presentation:input-state-buffer new-state))
               (= cursor
                  (nshell.presentation:input-state-cursor-pos new-state))
               (= -1
                  (nshell.presentation:input-state-completion-index new-state))
               (null
                (nshell.presentation:input-state-completion-base-buffer new-state))
               (null
                (nshell.presentation:input-state-completion-base-cursor new-state))
               (null
                (nshell.presentation:input-state-suggestion new-state))
               (null
                (nshell.presentation:input-state-last-candidates new-state)))))))

  (it "pbt-input-state-tab-cycling-preserves-command-prefix"
    "Completion cycling replaces only the generated token after the command prefix."
    (check-property (:trials 50)
        ((command (gen-shell-word :min-length 1 :max-length 10)
                  #'shrink-prompt-text)
         (prefix (gen-shell-word :min-length 1 :max-length 6)
                 #'shrink-prompt-text)
         (first-candidate (gen-shell-word :min-length 1 :max-length 10)
                          #'shrink-prompt-text)
         (second-candidate (gen-shell-word :min-length 1 :max-length 10)
                           #'shrink-prompt-text))
      (let* ((buffer (format nil "~a ~a" command prefix))
             (state (input-state
                     :buffer buffer
                     :cursor-pos (length buffer)
                     :completion-index -1
                     :last-candidates (list first-candidate second-candidate))))
        (with-reduced-input-states state
            (((first-state) :tab)
             ((second-state) :tab))
          (and (string= (format nil "~a ~a" command first-candidate)
                        (nshell.presentation:input-state-buffer first-state))
               (string= (format nil "~a ~a" command second-candidate)
                        (nshell.presentation:input-state-buffer second-state))
               (= (length (nshell.presentation:input-state-buffer second-state))
                  (nshell.presentation:input-state-cursor-pos second-state)))))))

  (it "pbt-input-state-tab-shell-escapes-special-completion-candidates"
    "Completion cycling inserts shell-escaped text for raw candidates with separators."
    (check-property (:trials 50)
        ((command (gen-shell-word :min-length 1 :max-length 10)
                  #'shrink-prompt-text)
         (prefix (gen-shell-word :min-length 1 :max-length 6)
                 #'shrink-prompt-text)
         (tail (gen-shell-word :min-length 1 :max-length 10)
               #'shrink-prompt-text))
      (let* ((candidate (format nil "~a ~a#~a" prefix tail tail))
             (escaped (nshell.presentation::%completion-insertion-text candidate))
             (state (input-state
                     :buffer (format nil "~a ~a" command prefix)
                     :cursor-pos (+ (length command) 1 (length prefix))
                     :completion-index -1
                     :last-candidates (list candidate))))
        (multiple-value-bind (new-state) (reduce-once state :tab)
          (and (string= (format nil "~a ~a" command escaped)
                        (nshell.presentation:input-state-buffer new-state))
               (= (+ (length command) 1 (length escaped))
                  (nshell.presentation:input-state-cursor-pos new-state)))))))

  (it "pbt-input-state-tab-replaces-escaped-space-token"
    "Escaped token separators remain part of the current completion token."
    (check-property (:trials 50)
        ((command (gen-shell-word :min-length 1 :max-length 10)
                  #'shrink-prompt-text)
         (prefix (gen-shell-word :min-length 1 :max-length 6)
                 #'shrink-prompt-text)
         (tail (gen-shell-word :min-length 1 :max-length 6)
               #'shrink-prompt-text)
         (suffix (gen-shell-word :min-length 1 :max-length 6)
                 #'shrink-prompt-text))
      (let* ((typed-raw (format nil "~a ~a" prefix tail))
             (typed-escaped
               (nshell.presentation::%completion-insertion-text typed-raw))
             (candidate (concatenate 'string typed-raw suffix))
             (escaped-candidate
               (nshell.presentation::%completion-insertion-text candidate))
             (buffer (format nil "~a ~a" command typed-escaped))
             (state (input-state
                     :buffer buffer
                     :cursor-pos (length buffer)
                     :completion-index -1
                     :last-candidates (list candidate))))
        (multiple-value-bind (new-state) (reduce-once state :tab)
          (and (string= (format nil "~a ~a" command escaped-candidate)
                        (nshell.presentation:input-state-buffer new-state))
               (= (+ (length command) 1 (length escaped-candidate))
                  (nshell.presentation:input-state-cursor-pos new-state))))))))

