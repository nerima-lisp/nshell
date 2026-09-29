(in-package #:nshell/test)

(describe "east-asian-ambiguous-width"
  (it "validates-the-three-width-policies"
    (dolist (case '(("auto" :auto) ("narrow" :narrow) ("wide" :wide)))
      (expect (second case) :to-equal
              (nshell.domain.configuration:parse-east-asian-ambiguous-width
               (first case))))
    (expect (lambda ()
              (nshell.domain.configuration:parse-east-asian-ambiguous-width
               "invalid"))
            :to-throw 'type-error))

  (it "uses-locale-precedence-for-auto-fallback"
    (with-repl-test-state
      (repl-test-set-env "LC_ALL" "C")
      (repl-test-set-env "LC_CTYPE" "ja_JP.UTF-8")
      (repl-test-set-env "LANG" "zh_CN.UTF-8")
      (with-temporary-function
          ('nshell.infrastructure.terminal:interactive-terminal-p
           (lambda (&optional fd) (declare (ignore fd)) nil))
        (nshell.presentation::%apply-east-asian-ambiguous-width)
        (expect cl-tty-kit:*east-asian-ambiguous-wide* :to-be nil))
      (let ((environment
              (nshell.domain.environment:env-set
               (nshell.domain.environment:make-environment)
               "LC_CTYPE" "ja_JP.UTF-8" nil)))
        (expect (nshell.presentation::%east-asian-locale-wide-p environment)
                :to-be-truthy)))

  (it "matches-only-locale-language-prefixes"
    (dolist (locale '("ja_JP.UTF-8" "zh.CN" "ko@euckr" "JA"))
      (let ((environment
              (nshell.domain.environment:env-set
               (nshell.domain.environment:make-environment)
               "LANG" locale nil)))
        (expect (nshell.presentation::%east-asian-locale-wide-p environment)
                :to-be-truthy)))
    (let ((environment
            (nshell.domain.environment:env-set
             (nshell.domain.environment:make-environment)
             "LANG" "en_JA.UTF-8" nil)))
      (expect (nshell.presentation::%east-asian-locale-wide-p environment)
              :to-be nil)))

  (it "respects-explicit-width-in-batch-initialization"
    (with-repl-test-state
      (repl-test-set-env "NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH" "wide")
      (nshell.presentation::%initialize-batch-state)
      (expect cl-tty-kit:*east-asian-ambiguous-wide* :to-be-truthy)
      (repl-test-set-env "NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH" "narrow")
      (nshell.presentation::%initialize-batch-state)
      (expect cl-tty-kit:*east-asian-ambiguous-wide* :to-be nil)))

  (it "uses-locale-fallback-in-batch-auto-mode"
    (with-repl-test-state
      (repl-test-set-env "NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH" "auto")
      (repl-test-set-env "LANG" "ja_JP.UTF-8")
      (nshell.presentation::%initialize-batch-state)
      (expect cl-tty-kit:*east-asian-ambiguous-wide* :to-be-truthy)))

  (it "preserves-ordinary-input-when-querying-cpr"
    (let ((*standard-input* (make-string-input-stream "x"))
          (*standard-output* (make-string-output-stream)))
      (multiple-value-bind (row column)
          (nshell.infrastructure.terminal:query-cursor-position
           :attempts 1 :sleep-seconds 0)
        (expect row :to-be nil)
        (expect column :to-be nil)
        (expect (read-char *standard-input*) :to-equal #\x))))

  (it "parses-cpr-and-honors-the-short-timeout"
    (let ((input (list #\Esc #\[ #\3 #\; #\5 #\R)))
      (with-temporary-function
          ('nshell.infrastructure.terminal::read-available-char
           (lambda (&key attempts sleep-seconds)
             (declare (ignore attempts sleep-seconds))
             (pop input)))
        (multiple-value-bind (row column)
            (nshell.infrastructure.terminal:query-cursor-position
             :attempts 10 :sleep-seconds 0.001)
          (expect row :to-be 4)
          (expect column :to-be 6))))
    (let ((input (list #\Esc)))
      (with-temporary-function
          ('nshell.infrastructure.terminal::read-available-char
           (lambda (&key attempts sleep-seconds)
             (declare (ignore attempts sleep-seconds))
             (pop input)))
        (multiple-value-bind (row column)
            (nshell.infrastructure.terminal:query-cursor-position
             :attempts 2 :sleep-seconds 0.001)
          (expect row :to-be nil)
          (expect column :to-be nil)))))

  (it "returns-three-states-for-terminal-probe"
    (let ((queries 0))
      (with-temporary-function
          ('nshell.infrastructure.terminal::query-cursor-position
           (lambda (&key attempts sleep-seconds)
             (declare (ignore attempts sleep-seconds))
             (incf queries)
             (if (= queries 1) (values 1 10) (values 1 12))))
        (let ((*standard-input* (make-string-input-stream ""))
              (*standard-output* (make-string-output-stream)))
          (expect (nshell.infrastructure.terminal:detect-east-asian-ambiguous-wide-p)
                  :to-be :wide)))
      (setf queries 0)
      (with-temporary-function
          ('nshell.infrastructure.terminal::query-cursor-position
           (lambda (&key attempts sleep-seconds)
             (declare (ignore attempts sleep-seconds))
             (incf queries)
             (if (= queries 1) (values 1 10) (values 1 11))))
        (let ((*standard-input* (make-string-input-stream ""))
              (*standard-output* (make-string-output-stream)))
          (expect (nshell.infrastructure.terminal:detect-east-asian-ambiguous-wide-p)
                  :to-be :narrow))))))

  (it "keeps-measured-narrow-over-japanese-locale"
    (with-repl-test-state
      (repl-test-set-env "NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH" "auto")
      (repl-test-set-env "LANG" "ja_JP.UTF-8")
      (with-temporary-function
          ('nshell.infrastructure.terminal:interactive-terminal-p
           (lambda (&optional fd) (declare (ignore fd)) t))
        (with-temporary-function
            ('nshell.infrastructure.terminal:detect-east-asian-ambiguous-wide-p
             (lambda (&key attempts sleep-seconds)
               (declare (ignore attempts sleep-seconds))
               :narrow))
          (nshell.presentation::%apply-east-asian-ambiguous-width)
          (expect cl-tty-kit:*east-asian-ambiguous-wide* :to-be nil)))))

  (it "measures-unicode-graphemes-as-display-units"
    (let ((vs16 "❤️")
          (family "👨‍👩‍👧‍👦")
          (flag "🇯🇵")
          (combining "é"))
      (dolist (case `((,vs16 1) (,family 2) (,flag 1) (,combining 1)))
        (expect (second case) :to-equal
                (cl-tty-kit:grapheme-width
                 (first (cl-tty-kit:string-graphemes (first case))))))
      (expect (nshell.presentation::%string-visible-width family) :to-equal 2)
      (expect (nshell.presentation::%string-visible-width vs16) :to-equal 2)
      (expect (nshell.presentation::%string-visible-width flag) :to-equal 2)
      (expect (nshell.presentation::%string-visible-width combining) :to-equal 1)
      (expect (nshell.presentation::%truncate-string-to-width family 1)
              :to-equal "")
      (expect (nshell.presentation::%truncate-string-to-width family 2)
              :to-equal family)))

  (it "moves-and-deletes-input-by-grapheme"
    (let* ((family "👨‍👩‍👧‍👦")
           (state (input-state :buffer (concatenate 'string "a" family "b")
                               :cursor-pos (+ 1 (length family))))
           (backspaced nil)
           (ignored-output nil))
      (declare (ignore ignored-output))
      (multiple-value-setq (backspaced ignored-output)
        (nshell.presentation::backspace-before-cursor state))
      (expect (nshell.presentation:input-state-buffer backspaced)
              :to-equal "ab")
      (expect (nshell.presentation:input-state-cursor-pos backspaced)
              :to-equal 1))
    (let* ((family "👨‍👩‍👧‍👦")
           (state (input-state :buffer (concatenate 'string "a" family "b")
                               :cursor-pos 1))
           (moved nil)
           (ignored-output nil))
      (declare (ignore ignored-output))
      (multiple-value-setq (moved ignored-output)
        (nshell.presentation::move-cursor-clearing-suggestion state 1))
      (expect (nshell.presentation:input-state-cursor-pos moved)
              :to-equal (+ 1 (length family))))))
