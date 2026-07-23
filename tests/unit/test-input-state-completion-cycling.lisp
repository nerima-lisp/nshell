(in-package #:nshell/test)

(describe "input-state-tests"
  (it "pbt-input-state-tab-cycling-preserves-suffix-after-cursor-token"
    "Completion cycling at a middle cursor preserves text after the completed token."
    (check-property (:trials 50)
        ((command (gen-shell-word :min-length 1 :max-length 10)
                  #'shrink-prompt-text)
         (prefix (gen-shell-word :min-length 1 :max-length 6)
                 #'shrink-prompt-text)
         (suffix (gen-shell-word :min-length 1 :max-length 10)
                 #'shrink-prompt-text)
         (first-candidate (gen-shell-word :min-length 1 :max-length 10)
                          #'shrink-prompt-text)
         (second-candidate (gen-shell-word :min-length 1 :max-length 10)
                           #'shrink-prompt-text))
      (let* ((buffer (format nil "~a ~a ~a" command prefix suffix))
             (cursor (+ (length command) 1 (length prefix)))
             (state (input-state
                     :buffer buffer
                     :cursor-pos cursor
                     :completion-index -1
                     :last-candidates (list first-candidate second-candidate))))
        (with-reduced-input-states state
            (((first-state) :tab)
             ((second-state) :tab))
          (and (string= (format nil "~a ~a ~a"
                                command first-candidate suffix)
                        (nshell.presentation:input-state-buffer first-state))
               (string= (format nil "~a ~a ~a"
                                 command second-candidate suffix)
                        (nshell.presentation:input-state-buffer second-state))
               (= (+ (length command) 1 (length second-candidate))
                  (nshell.presentation:input-state-cursor-pos second-state)))))))

  (it "pbt-input-state-tab-cycling-preserves-structured-candidate-metadata"
    "Completion cycling uses candidate text without discarding candidate metadata."
    (check-property (:trials 50)
        ((command (gen-shell-word :min-length 1 :max-length 10)
                  #'shrink-prompt-text)
         (prefix (gen-shell-word :min-length 1 :max-length 6)
                 #'shrink-prompt-text)
         (first-candidate-text (gen-shell-word :min-length 1 :max-length 10)
                               #'shrink-prompt-text)
         (second-candidate-text (gen-shell-word :min-length 1 :max-length 10)
                                #'shrink-prompt-text)
         (first-description (gen-shell-word :min-length 1 :max-length 12)
                            #'shrink-prompt-text)
         (second-description (gen-shell-word :min-length 1 :max-length 12)
                             #'shrink-prompt-text))
      (let* ((buffer (format nil "~a ~a" command prefix))
             (first-candidate
               (nshell.domain.completion:make-candidate
                first-candidate-text
                :kind :command
                :description first-description
                :score 20))
             (second-candidate
               (nshell.domain.completion:make-candidate
                second-candidate-text
                :kind :option
                :description second-description
                :score 10))
             (candidates (list first-candidate second-candidate))
             (state (input-state
                     :buffer buffer
                     :cursor-pos (length buffer)
                     :completion-index -1
                     :last-candidates candidates)))
        (with-reduced-input-states state
            (((first-state) :tab)
             ((second-state) :tab))
          (let ((stored (nshell.presentation:input-state-last-candidates second-state)))
            (and (eq candidates stored)
                 (string= (format nil "~a ~a" command first-candidate-text)
                          (nshell.presentation:input-state-buffer first-state))
                 (string= (format nil "~a ~a" command second-candidate-text)
                          (nshell.presentation:input-state-buffer second-state))
                 (string= first-description
                          (nshell.domain.completion:candidate-description (first stored)))
                 (string= second-description
                          (nshell.domain.completion:candidate-description (second stored)))))))))

  (it "pbt-input-state-common-prefix-extension-matches-candidates"
    "Common-prefix completion extends the token to the exact shared candidate prefix."
    (check-property (:trials 50)
        ((stem (gen-shell-word :min-length 2 :max-length 8)
               #'shrink-prompt-text)
         (left-tail (gen-shell-word :min-length 1 :max-length 6)
                    #'shrink-prompt-text)
         (right-tail (gen-shell-word :min-length 1 :max-length 6)
                     #'shrink-prompt-text))
      (let* ((typed (subseq stem 0 1))
             (candidates (list (concatenate 'string stem left-tail)
                               (concatenate 'string stem right-tail)))
             (common (nshell.presentation::completion-common-prefix candidates))
             (state (input-state
                     :buffer typed
                     :cursor-pos (length typed))))
        (multiple-value-bind (new-state extended-p)
            (nshell.presentation::maybe-extend-completion-common-prefix state
                                                                        candidates)
          (and extended-p
               (string= common
                        (nshell.presentation:input-state-buffer new-state))
               (= (length common)
                  (nshell.presentation:input-state-cursor-pos new-state))))))))
