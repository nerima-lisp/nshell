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

  (it "detects-a-wide-probe-without-asking-in-batch"
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
                  :to-be t)))))))
