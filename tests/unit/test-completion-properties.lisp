(in-package #:nshell/test)

(describe "completion-rules-tests"
  (it "case-sensitive-prefix-p-matches-exact-case-leading-substring"
    "case-sensitive-prefix-p returns true only when prefix matches the start of text exactly."
    (flet ((pre (prefix text)
             (nshell.domain.completion::%case-sensitive-prefix-p prefix text)))
      (expect (pre "" "anything") :to-be-truthy)
      (expect (pre "check" "checkout") :to-be-truthy)
      (expect (pre "git" "git") :to-be-truthy)
      (expect (pre "Git" "git") :to-be-falsy)
      (expect (pre "checkout" "check") :to-be-falsy)))

  (it "candidate-description-present-p-tests-non-empty-description"
    "candidate-description-present-p returns true only when description is non-empty."
    (expect (nshell.domain.completion::%candidate-description-present-p
         (nshell.domain.completion:make-candidate "tool" :description "does stuff")) :to-be-truthy)
    (expect (nshell.domain.completion::%candidate-description-present-p
              (nshell.domain.completion:make-candidate "tool" :description "")) :to-be-falsy)
    (expect (nshell.domain.completion::%candidate-description-present-p
              (nshell.domain.completion:make-candidate "tool")) :to-be-falsy))

  (it "make-candidate-normalizes-optional-values"
    "make-candidate keeps optional nil values at the domain defaults."
    (let ((candidate (nshell.domain.completion:make-candidate "tool"
                                                              :description nil
                                                              :score nil)))
      (expect "tool" :to-equal (nshell.domain.completion:candidate-text candidate))
      (expect :command :to-be (nshell.domain.completion:candidate-kind candidate))
      (expect "" :to-equal (nshell.domain.completion:candidate-description candidate))
      (expect 0 :to-equal (nshell.domain.completion:candidate-score candidate))))

  (it "completion-candidate-construction-boundary-is-closed"
    "candidate construction rejects invalid values and keeps raw copy construction unbound."
    (multiple-value-bind (copy-symbol copy-status)
        (find-symbol "COPY-%COMPLETION-CANDIDATE" '#:nshell.domain.completion)
      (expect (fboundp 'nshell.domain.completion::%make-completion-candidate) :to-be-truthy)
      (expect (fboundp 'nshell.domain.completion::%allocate-completion-candidate) :to-be-truthy)
      (expect (or (null copy-status)
              (not (fboundp copy-symbol))) :to-be-truthy))
    (expect (lambda () (nshell.domain.completion:make-candidate 42)) :to-throw 'type-error)
    (expect (lambda () (nshell.domain.completion:make-candidate "tool" :kind "command")) :to-throw 'type-error)
    (expect (lambda () (nshell.domain.completion:make-candidate "tool" :description :bad)) :to-throw 'type-error)
    (expect (lambda () (nshell.domain.completion:make-candidate "tool" :score "10")) :to-throw 'type-error))

  (it "completion-rank-score-applies-exact-and-prefix-bonuses"
    "completion-rank-score stacks bonuses: exact (+100000), prefix (+10000), described (+1000)."
    (flet ((score (prefix text &key (description "") (base 0))
             (nshell.domain.completion::%completion-rank-score
              prefix
              (nshell.domain.completion:make-candidate text :description description :score base))))
      ;; exact match: base + 100000 + 10000 (prefix) + 1000 (described)
      (expect 111000 :to-equal (score "git" "git" :description "v-ctrl"))
      ;; prefix-only (not exact): base + 10000
      (expect 10000 :to-equal (score "git" "gitk"))
      ;; no bonus: just base
      (expect 5 :to-equal (score "git" "awk" :base 5))))

  (it "better-duplicate-candidate-p-prefers-higher-score-then-description"
    "better-duplicate-candidate-p returns true when candidate is strictly better than current."
    (flet ((make (text &key (score 0) (description ""))
             (nshell.domain.completion:make-candidate text :score score :description description))
           (better (a b)
             (nshell.domain.completion::%better-duplicate-candidate-p a b)))
      ;; higher score wins unconditionally
      (expect (better (make "t" :score 10) (make "t" :score 5)) :to-be-truthy)
      (expect (better (make "t" :score 5) (make "t" :score 10)) :to-be-falsy)
      ;; equal score: description present beats absent
      (expect (better (make "t" :description "info") (make "t")) :to-be-truthy)
      (expect (better (make "t") (make "t" :description "info")) :to-be-falsy)
      ;; equal score, both described or both bare: not better
      (expect (better (make "t" :description "a") (make "t" :description "b")) :to-be-falsy)))

  (it "merge-candidates-keeps-indexed-winner"
    (let* ((low (nshell.domain.completion:make-candidate "dup" :score 1))
           (high (nshell.domain.completion:make-candidate
                  "dup" :score 5 :description "winner"))
           (results (nshell.domain.completion::%merge-candidates
                     (list low)
                     (list high))))
      (expect 1 :to-equal (length results))
      (expect 5 :to-equal (nshell.domain.completion:candidate-score (first results)))
      (expect "winner" :to-equal (nshell.domain.completion:candidate-description (first results)))))

  (it "merge-candidates-replaces-duplicate-in-original-position"
    (let* ((low (nshell.domain.completion:make-candidate "dup" :score 1))
           (other (nshell.domain.completion:make-candidate "other" :score 2))
           (high (nshell.domain.completion:make-candidate "dup" :score 5))
           (results (nshell.domain.completion::%merge-candidates
                     (list low other high))))
      (expect 2 :to-equal (length results))
      (expect "other" :to-equal (nshell.domain.completion:candidate-text (first results)))
      (expect high :to-be (second results))))

  (it "pbt-path-command-completion-is-prefixed-and-deduped"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
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

  (it "pbt-rule-prover-fact-round-trips-generated-values"
    (check-property (:trials 50)
        ((command (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
         (completion (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word))
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

  (it "pbt-knowledge-base-description-preserves-command-completion"
    (check-property (:trials 50)
        ((suffix (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
         (description (gen-prompt-text :min-length 0 :max-length 24) #'shrink-prompt-text))
      (let* ((command (concatenate 'string "zz-nshell-" suffix))
             (kb (nshell.domain.completion:make-empty-knowledge-base)))
        (nshell.domain.completion:kb-add-command kb command :description description)
        (let ((candidates (nshell.domain.completion:complete kb command)))
          (and (= 1 (length candidates))
               (string= command
                        (nshell.domain.completion:candidate-text (first candidates)))
               (string= description
                        (nshell.domain.completion:candidate-description (first candidates))))))))

  (it "pbt-command-completion-ranks-exact-match-first"
    (check-property (:trials 50)
        ((suffix (gen-command-prefix :min-length 1 :max-length 8) nil))
      (let* ((command (concatenate 'string "zz-nshell-" suffix))
             (longer (concatenate 'string command "-extra"))
             (kb (nshell.domain.completion:make-empty-knowledge-base)))
        (nshell.domain.completion:kb-add-command kb longer)
        (nshell.domain.completion:kb-add-command kb command)
        (let ((candidates (nshell.domain.completion:complete kb command)))
          (and (<= 2 (length candidates))
               (string= command
                        (nshell.domain.completion:candidate-text
                         (first candidates))))))))

  (it "pbt-command-completion-ranks-case-sensitive-prefix-first"
    (check-property (:trials 50)
        ((suffix (gen-command-prefix :min-length 1 :max-length 8) nil))
      (let* ((prefix (concatenate 'string "zzcase-" suffix))
             (typed-case (concatenate 'string prefix "-typed"))
             (folded-case (concatenate 'string (string-upcase prefix) "-folded"))
             (kb (nshell.domain.completion:make-empty-knowledge-base)))
        (nshell.domain.completion:kb-add-command kb folded-case)
        (nshell.domain.completion:kb-add-command kb typed-case)
        (let ((texts (completion-texts
                      (nshell.domain.completion:complete kb prefix))))
          (< (position typed-case texts :test #'string=)
             (position folded-case texts :test #'string=))))))

  (it "pbt-completion-ranking-prefers-higher-score"
    (check-property (:trials 50)
        ((prefix (gen-command-prefix :min-length 1 :max-length 4) nil)
         (low-tail (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
         (high-tail (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
         (base-score (gen-in-range 0 100) nil)
         (score-delta (gen-in-range 1 100) nil))
      (let* ((low-text (concatenate 'string prefix "-z-" low-tail))
             (high-text (concatenate 'string prefix "-a-" high-tail))
             (low (nshell.domain.completion:make-candidate low-text :score base-score))
             (high (nshell.domain.completion:make-candidate high-text
                                                            :score (+ base-score score-delta)))
             (ranked (nshell.domain.completion::%rank-candidates prefix (list low high))))
        (and (string= high-text (nshell.domain.completion:candidate-text (first ranked)))
             (string= low-text (nshell.domain.completion:candidate-text (second ranked)))))))

  (it "pbt-completion-ranking-breaks-score-ties-lexically"
    (check-property (:trials 50)
        ((prefix (gen-command-prefix :min-length 1 :max-length 4) nil)
         (early-tail (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
         (late-tail (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
         (score (gen-in-range 0 100) nil))
      (let* ((early-text (concatenate 'string prefix "-a-" early-tail))
             (late-text (concatenate 'string prefix "-z-" late-tail))
             (early (nshell.domain.completion:make-candidate early-text :score score))
             (late (nshell.domain.completion:make-candidate late-text :score score))
             (ranked (nshell.domain.completion::%rank-candidates prefix (list late early))))
        (and (string= early-text (nshell.domain.completion:candidate-text (first ranked)))
             (string= late-text (nshell.domain.completion:candidate-text (second ranked)))))))

  (it "pbt-completion-merge-keeps-higher-scored-duplicate"
    (check-property (:trials 50)
        ((text (gen-shell-word :min-length 1 :max-length 10) #'shrink-shell-word)
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
             (merged (nshell.domain.completion::%merge-candidates (list low) (list high))))
        (and (= 1 (length merged))
             (= expected-score (nshell.domain.completion:candidate-score (first merged)))
             (string= description
                      (nshell.domain.completion:candidate-description (first merged)))))))

  (it "pbt-completion-merge-keeps-described-duplicate-on-score-tie"
    (check-property (:trials 50)
        ((text (gen-shell-word :min-length 1 :max-length 10) #'shrink-shell-word)
         (score (gen-in-range 0 100) nil)
         (description (gen-prompt-text :min-length 1 :max-length 16) #'shrink-prompt-text))
      (let* ((plain (nshell.domain.completion:make-candidate text
                                                             :description ""
                                                             :score score))
             (described (nshell.domain.completion:make-candidate text
                                                                 :description description
                                                                 :score score))
             (merged (nshell.domain.completion::%merge-candidates (list plain)
                                                                  (list described))))
        (and (= 1 (length merged))
             (= score (nshell.domain.completion:candidate-score (first merged)))
             (string= description
                      (nshell.domain.completion:candidate-description (first merged)))))))

  (it "completion-merge-handles-large-duplicate-set-with-best-candidate"
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
           (merged (nshell.domain.completion::%merge-candidates
                    (cons low unique-candidates)
                    (list high)))
           (winner (completion-candidate-by-text "zz-large-tool" merged)))
      (expect 2001 :to-equal (length merged))
      (expect (null winner) :to-be-falsy)
      (expect 100 :to-equal (nshell.domain.completion:candidate-score winner))
      (expect "fast path" :to-equal (nshell.domain.completion:candidate-description winner))))

  (it "knowledge-base-argument-completion-handles-large-duplicate-flag-set"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base))
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
        (expect 2001 :to-equal (length texts))
        (expect 1 :to-equal (count "--shared" texts :test #'string=))
        (expect "--shared" :to-equal (first texts))
        (expect "--unique-1999" :to-equal (car (last texts))))))

  (it "knowledge-base-option-value-completion-handles-large-duplicate-value-set"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base))
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
        (expect 2001 :to-equal (length attached-texts))
        (expect 1 :to-equal (count "--mode=shared" attached-texts :test #'string=))
        (expect "--mode=shared" :to-equal (first attached-texts))
        (expect "--mode=unique-1999" :to-equal (car (last attached-texts)))
        (expect 2001 :to-equal (length separate-texts))
        (expect 1 :to-equal (count "shared" separate-texts :test #'string=))
        (expect "shared" :to-equal (first separate-texts))
        (expect "unique-1999" :to-equal (car (last separate-texts))))))

  (it "pbt-argument-completion-is-shell-token-aware"
    (check-property (:trials 50)
        ((suffix (gen-command-prefix :min-length 1 :max-length 8) nil)
         (left (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
         (right (gen-shell-word :min-length 1 :max-length 8) #'shrink-shell-word)
         (stem (gen-command-prefix :min-length 1 :max-length 4) nil))
      (let* ((command (concatenate 'string "zz-nshell-" suffix))
             (prefix (concatenate 'string "--" stem))
             (flag (concatenate 'string prefix "-flag"))
             (kb (nshell.domain.completion:make-empty-knowledge-base)))
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
                (format nil "~a ~a\\ ~a ~a" command left right prefix))))))))
