(in-package #:nshell/test)

(in-suite completion-rules-tests)

(test pbt-path-command-completion-is-prefixed-and-deduped
  (let ((kb (nshell.domain.completion:make-knowledge-base)))
    (nshell.domain.completion:kb-add-command kb "git")
    (with-path-command-adapters
        ((lambda (directory)
           (declare (ignore directory))
           (list #p"/bin/git" #p"/usr/bin/git" #p"/bin/grep" #p"/bin/awk"))
         (constantly t))
      (check-property (:trials 50)
          ((prefix (gen-command-prefix :min-length 0 :max-length 3)))
        (let* ((texts (completion-texts
                       (nshell.domain.completion:complete kb prefix :path "/bin:/usr/bin")))
               (unique-texts (remove-duplicates texts :test #'string=)))
          (and (every (lambda (text) (completion-prefix-p prefix text)) texts)
	               (= (length texts) (length unique-texts))))))))

(test pbt-rule-prover-fact-round-trips-generated-values
  (check-property (:trials 50)
      ((command (gen-shell-word :min-length 1 :max-length 8) #'shrink-prompt-text)
       (completion (gen-shell-word :min-length 1 :max-length 8) #'shrink-prompt-text))
    (let ((kb (make-empty-rule-kb)))
      (nshell.domain.completion:assert-fact!
       kb
       (nshell.domain.completion:make-fact :predicate 'completes
                                           :args (list command completion)))
      (let ((solutions
              (nshell.domain.completion:prove-all
               kb
               `(completes ,command ?completion))))
        (and (= 1 (length solutions))
             (string= completion
                      (solution-binding '?completion (first solutions))))))))

(test pbt-knowledge-base-description-preserves-command-completion
  (check-property (:trials 50)
      ((suffix (gen-shell-word :min-length 1 :max-length 8) #'shrink-prompt-text)
       (description (gen-prompt-text :min-length 0 :max-length 24) #'shrink-prompt-text))
    (let* ((command (concatenate 'string "zz-nshell-" suffix))
           (kb (nshell.domain.completion:make-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb command :description description)
      (let ((candidates (nshell.domain.completion:complete kb command)))
        (and (= 1 (length candidates))
             (string= command
                      (nshell.domain.completion:candidate-text (first candidates)))
             (string= description
                      (nshell.domain.completion:candidate-description (first candidates))))))))

(test pbt-command-completion-ranks-exact-match-first
  (check-property (:trials 50)
      ((suffix (gen-command-prefix :min-length 1 :max-length 8) nil))
    (let* ((command (concatenate 'string "zz-nshell-" suffix))
           (longer (concatenate 'string command "-extra"))
           (kb (nshell.domain.completion:make-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb longer)
      (nshell.domain.completion:kb-add-command kb command)
      (let ((candidates (nshell.domain.completion:complete kb command)))
        (and (<= 2 (length candidates))
             (string= command
                      (nshell.domain.completion:candidate-text
                       (first candidates))))))))

(test pbt-command-completion-ranks-case-sensitive-prefix-first
  (check-property (:trials 50)
      ((suffix (gen-command-prefix :min-length 1 :max-length 8) nil))
    (let* ((prefix (concatenate 'string "zzcase-" suffix))
           (typed-case (concatenate 'string prefix "-typed"))
           (folded-case (concatenate 'string (string-upcase prefix) "-folded"))
           (kb (nshell.domain.completion:make-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb folded-case)
      (nshell.domain.completion:kb-add-command kb typed-case)
      (let ((texts (completion-texts
                    (nshell.domain.completion:complete kb prefix))))
        (< (position typed-case texts :test #'string=)
           (position folded-case texts :test #'string=))))))

(test pbt-completion-ranking-prefers-higher-score
  (check-property (:trials 50)
      ((prefix (gen-command-prefix :min-length 1 :max-length 4) nil)
       (low-tail (gen-shell-word :min-length 1 :max-length 8) #'shrink-prompt-text)
       (high-tail (gen-shell-word :min-length 1 :max-length 8) #'shrink-prompt-text)
       (base-score (gen-in-range 0 100) nil)
       (score-delta (gen-in-range 1 100) nil))
    (let* ((low-text (concatenate 'string prefix "-z-" low-tail))
           (high-text (concatenate 'string prefix "-a-" high-tail))
           (low (nshell.domain.completion:make-candidate low-text :score base-score))
           (high (nshell.domain.completion:make-candidate high-text
                                                          :score (+ base-score score-delta)))
           (ranked (nshell.domain.completion::rank-candidates prefix (list low high))))
      (and (string= high-text (nshell.domain.completion:candidate-text (first ranked)))
           (string= low-text (nshell.domain.completion:candidate-text (second ranked)))))))

(test pbt-completion-ranking-breaks-score-ties-lexically
  (check-property (:trials 50)
      ((prefix (gen-command-prefix :min-length 1 :max-length 4) nil)
       (early-tail (gen-shell-word :min-length 1 :max-length 8) #'shrink-prompt-text)
       (late-tail (gen-shell-word :min-length 1 :max-length 8) #'shrink-prompt-text)
       (score (gen-in-range 0 100) nil))
    (let* ((early-text (concatenate 'string prefix "-a-" early-tail))
           (late-text (concatenate 'string prefix "-z-" late-tail))
           (early (nshell.domain.completion:make-candidate early-text :score score))
           (late (nshell.domain.completion:make-candidate late-text :score score))
           (ranked (nshell.domain.completion::rank-candidates prefix (list late early))))
      (and (string= early-text (nshell.domain.completion:candidate-text (first ranked)))
           (string= late-text (nshell.domain.completion:candidate-text (second ranked)))))))

(test pbt-completion-merge-keeps-higher-scored-duplicate
  (check-property (:trials 50)
      ((text (gen-shell-word :min-length 1 :max-length 10) #'shrink-prompt-text)
       (low-score (gen-in-range 0 50) nil)
       (score-delta (gen-in-range 1 50) nil)
       (description (gen-prompt-text :min-length 1 :max-length 16) #'shrink-prompt-text))
    (let* ((expected-score (+ low-score score-delta))
           (low (nshell.domain.completion:make-candidate text
                                                         :description ""
                                                         :score low-score))
           (high (nshell.domain.completion:make-candidate text
                                                          :description description
                                                          :score expected-score))
           (merged (nshell.domain.completion::merge-candidates (list low) (list high))))
      (and (= 1 (length merged))
           (= expected-score (nshell.domain.completion:candidate-score (first merged)))
           (string= description
                    (nshell.domain.completion:candidate-description (first merged)))))))

(test pbt-completion-merge-keeps-described-duplicate-on-score-tie
  (check-property (:trials 50)
      ((text (gen-shell-word :min-length 1 :max-length 10) #'shrink-prompt-text)
       (score (gen-in-range 0 100) nil)
       (description (gen-prompt-text :min-length 1 :max-length 16) #'shrink-prompt-text))
    (let* ((plain (nshell.domain.completion:make-candidate text
                                                           :description ""
                                                           :score score))
           (described (nshell.domain.completion:make-candidate text
                                                               :description description
                                                               :score score))
           (merged (nshell.domain.completion::merge-candidates (list plain)
                                                               (list described))))
      (and (= 1 (length merged))
           (= score (nshell.domain.completion:candidate-score (first merged)))
           (string= description
                    (nshell.domain.completion:candidate-description (first merged)))))))

(test completion-merge-handles-large-duplicate-set-with-best-candidate
  (let* ((low (nshell.domain.completion:make-candidate "zz-large-tool"
                                                       :description ""
                                                       :score 1))
         (unique-candidates
           (loop for i below 2000
                 collect (nshell.domain.completion:make-candidate
                          (format nil "zz-large-tool-~4,'0d" i)
                          :score 1)))
         (high (nshell.domain.completion:make-candidate "zz-large-tool"
                                                        :description "fast path"
                                                        :score 100))
         (merged (nshell.domain.completion::merge-candidates
                  (cons low unique-candidates)
                  (list high)))
         (winner (completion-candidate-by-text "zz-large-tool" merged)))
    (is (= 2001 (length merged)))
    (is (not (null winner)))
    (is (= 100 (nshell.domain.completion:candidate-score winner)))
    (is (string= "fast path"
                 (nshell.domain.completion:candidate-description winner)))))

(test knowledge-base-argument-completion-handles-large-duplicate-flag-set
  (let ((kb (nshell.domain.completion:make-knowledge-base))
        (flags '()))
    (dotimes (i 2000)
      (push "--shared" flags)
      (push (format nil "--unique-~4,'0d" i) flags))
    (nshell.domain.completion:kb-add-command
     kb
     "zz-large-args"
     :flags (nreverse flags))
    (let ((texts (completion-texts
                  (nshell.domain.completion:complete kb "zz-large-args --"))))
      (is (= 2001 (length texts)))
      (is (= 1 (count "--shared" texts :test #'string=)))
      (is (string= "--shared" (first texts)))
      (is (string= "--unique-1999" (car (last texts)))))))

(test knowledge-base-option-value-completion-handles-large-duplicate-value-set
  (let ((kb (nshell.domain.completion:make-knowledge-base))
        (values '()))
    (dotimes (i 2000)
      (push "shared" values)
      (push (format nil "unique-~4,'0d" i) values))
    (nshell.domain.completion:kb-add-command
     kb
     "zz-large-option-values"
     :flags '("--mode")
     :option-values (list (cons "--mode" (nreverse values))))
    (let ((attached-texts
            (completion-texts
             (nshell.domain.completion:complete
              kb
              "zz-large-option-values --mode=")))
          (separate-texts
            (completion-texts
             (nshell.domain.completion:complete
              kb
              "zz-large-option-values --mode "))))
      (is (= 2001 (length attached-texts)))
      (is (= 1 (count "--mode=shared" attached-texts :test #'string=)))
      (is (string= "--mode=shared" (first attached-texts)))
      (is (string= "--mode=unique-1999" (car (last attached-texts))))
      (is (= 2001 (length separate-texts)))
      (is (= 1 (count "shared" separate-texts :test #'string=)))
      (is (string= "shared" (first separate-texts)))
      (is (string= "unique-1999" (car (last separate-texts)))))))

(test pbt-argument-completion-is-shell-token-aware
  (check-property (:trials 50)
      ((suffix (gen-command-prefix :min-length 1 :max-length 8) nil)
       (left (gen-shell-word :min-length 1 :max-length 8) #'shrink-prompt-text)
       (right (gen-shell-word :min-length 1 :max-length 8) #'shrink-prompt-text)
       (stem (gen-command-prefix :min-length 1 :max-length 4) nil))
    (let* ((command (concatenate 'string "zz-nshell-" suffix))
           (prefix (concatenate 'string "--" stem))
           (flag (concatenate 'string prefix "-flag"))
           (kb (nshell.domain.completion:make-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb command :flags (list flag))
      (labels ((completion-has-only-prefixed-flag-p (line)
                 (let ((texts (completion-texts
                               (nshell.domain.completion:complete kb line))))
                   (and (member flag texts :test #'string=)
                        (every (lambda (text)
                                 (completion-prefix-p prefix text))
                               texts)))))
        (and (completion-has-only-prefixed-flag-p
              (format nil "~a \"~a ~a\" ~a" command left right prefix))
             (completion-has-only-prefixed-flag-p
              (format nil "~a ~a\\ ~a ~a" command left right prefix)))))))

