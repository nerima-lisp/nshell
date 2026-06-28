(in-package #:nshell/test)
(in-suite builtin-tests)

(test string-builtin-covers-core-fish-style-subcommands
  "string provides common fish-style string transformation subcommands."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("length" "abc" "")
       :code 0
       :output (format nil "3~%0~%"))
      ('("lower" "HeLLo" "WORLD")
       :code 0
       :output (format nil "hello~%world~%"))
      ('("upper" "Hello")
       :code 0
       :output (format nil "HELLO~%"))
      ('("join" "," "a" "b" "c")
       :code 0
       :output (format nil "a,b,c~%"))
      ('("split" "," "a,b,,c")
       :code 0
       :output (format nil "a~%b~%~%c~%"))
      ('("trim" "  hi  ")
       :code 0
       :output (format nil "hi~%")))))

(test string-builtin-collect-cases
  "string collect normalizes input streams and handles empty-input options."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("collect" "alpha" "beta")
       :code 0
       :output (format nil "alpha~%beta~%"))
      ((list "collect" (format nil "alpha~%~%"))
       :code 0
       :output (format nil "alpha~%"))
      ((list "collect" "-N" (format nil "alpha~%~%"))
       :code 0
       :output (format nil "alpha~%~%~%"))
      ('("collect" "")
       :code 1
       :output-empty t)
      ('("collect" "--allow-empty" "")
       :code 1
       :output (format nil "~%"))
      ('("collect" "--" "-value")
       :code 0
       :output (format nil "-value~%"))
      ('("collect" "--bogus" "value")
       :code 1
       :contains '("unknown option --bogus")))))

(test string-builtin-replace-cases
  "string replace covers replacement, case-folding, quiet mode, and option errors."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("replace" "fish" "nshell" "fish shell fish")
       :code 0
       :output (format nil "nshell shell fish~%"))
      ('("replace" "--all" "fish" "nshell" "fish shell fish")
       :code 0
       :output (format nil "nshell shell nshell~%"))
      ('("replace" "--ignore-case" "fish" "nshell" "FiSh shell")
       :code 0
       :output (format nil "nshell shell~%"))
      ('("replace" "--quiet" "fish" "nshell" "fish shell")
       :code 0
       :output-empty t)
      ('("replace" "--quiet" "fish" "nshell" "bash shell")
       :code 1
       :output-empty t)
      ('("replace" "--" "-old" "new" "-old value")
       :code 0
       :output (format nil "new value~%"))
      ('("replace" "--bogus" "x" "y" "x")
       :code 1
       :contains '("unknown option --bogus")))))

(test string-builtin-match-cases
  "string match covers globbing, quiet mode, case folding, and option errors."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("match" "git*" "git" "status" "git status")
       :code 0
       :output (format nil "git~%git status~%"))
      ('("match" "no*" "git")
       :code 1
       :output-empty t)
      ('("match" "-q" "git*" "git status")
       :code 0
       :output-empty t)
      ('("match" "--quiet" "no*" "git")
       :code 1
       :output-empty t)
      ('("match" "--ignore-case" "git*" "GIT status")
       :code 0
       :output (format nil "GIT status~%"))
      ('("match" "--all" "git*" "git")
       :code 1
       :contains '("unknown option --all"))
      ('("match" "--" "-*" "-abc" "abc")
       :code 0
       :output (format nil "-abc~%"))
      ('("match" "--bogus" "x" "x")
       :code 1
       :contains '("unknown option --bogus")))))

(test string-builtin-repeat-cases
  "string repeat covers count, maximum length, quiet mode, and option errors."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("repeat" "2" "ab")
       :code 1
       :contains '("usage"))
      ('("repeat" "-n" "2" "ab" "c")
       :code 0
       :output (format nil "abab~%cc~%"))
      ('("repeat" "--count=3" "--max" "5" "ab")
       :code 0
       :output (format nil "ababa~%"))
      ('("repeat" "-m5" "ab")
       :code 0
       :output (format nil "ababa~%"))
      ('("repeat" "-n2" "--" "-ab")
       :code 0
       :output (format nil "-ab-ab~%"))
      ('("repeat" "-N" "-n2" "ab" "c")
       :code 0
       :output (format nil "abab~%cc"))
      ('("repeat" "--quiet" "-n" "2" "ab")
       :code 0
       :output-empty t)
      ('("repeat" "-n" "0" "ab")
       :code 1
       :output-empty t)
      ('("repeat" "-m" "0" "ab")
       :code 1
       :output-empty t)
      ('("repeat" "--bogus" "2" "ab")
       :code 1
       :contains '("unknown option --bogus")))))

(test string-builtin-sub-cases
  "string sub covers positive and negative slices, quiet mode, and option errors."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("sub" "--length" "2" "abcde")
       :code 0
       :output (format nil "ab~%"))
      ('("sub" "-s" "2" "-l" "2" "abcde")
       :code 0
       :output (format nil "bc~%"))
      ('("sub" "--start=-2" "abcde")
       :code 0
       :output (format nil "de~%"))
      ('("sub" "--end=3" "abcde")
       :code 0
       :output (format nil "abc~%"))
      ('("sub" "-e" "-1" "abcde")
       :code 0
       :output (format nil "abcd~%"))
      ('("sub" "-s" "-3" "-e" "-2" "abcde")
       :code 0
       :output (format nil "c~%"))
      ('("sub" "-q" "-s" "2" "abcde")
       :code 0
       :output-empty t)
      ('("sub" "-s2" "--" "-abc")
       :code 0
       :output (format nil "abc~%"))
      ('("sub" "-l" "1" "-e" "2" "abcde")
       :code 1
       :contains '("mutually exclusive"))
      ('("sub" "--bogus" "abcde")
       :code 1
       :contains '("unknown option --bogus")))))

(test string-builtin-rejects-invalid-integer-options
  "string repeat/sub surface integer parsing errors."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("repeat" "-n" "nope" "ab")
       :code 1
       :contains '("invalid integer for -n: nope"))
      ('("sub" "-s")
       :code 1
       :contains '("string: -s requires an integer")))))

(test string-builtin-supports-joined-and-assigned-integer-options
  "string repeat/sub accept --opt=value and -oN forms for integer options."
  (with-builtins-context (context)
    (assert-string-builtin-cases (context)
      ('("repeat" "--count=2" "--" "ab")
       :code 0
       :output (format nil "abab~%"))
      ('("repeat" "-n2" "--" "ab")
       :code 0
       :output (format nil "abab~%"))
      ('("sub" "--start=2" "--" "abcde")
       :code 0
       :output (format nil "bcde~%"))
      ('("sub" "-s2" "--" "abcde")
       :code 0
       :output (format nil "bcde~%")))))

(test pbt-string-match-ignore-case-matches-generated-words
  "string match -i agrees with case-insensitive equality for generated shell words."
  (assert-string-builtin-property (context)
      ((word (gen-shell-word :min-length 1 :max-length 8)))
    (let ((candidate (string-upcase word)))
      (multiple-value-bind (output code)
          (call-string-builtin context
                        (list "match" "-i" "--" word candidate))
        (and (= code 0)
             (string= (format nil "~A~%" candidate) output))))))

(test pbt-string-replace-ignore-case-replaces-generated-words
  "string replace -i replaces generated shell words regardless of case."
  (assert-string-builtin-property (context)
      ((word (gen-shell-word :min-length 1 :max-length 8)))
    (let ((candidate (string-upcase word)))
      (multiple-value-bind (output code)
          (call-string-builtin context
                        (list "replace" "-i" "--" word "X" candidate))
        (and (= code 0)
             (string= (format nil "X~%") output))))))

(test pbt-string-repeat-count-controls-generated-output-length
  "string repeat -n produces count copies for generated shell words."
  (assert-string-builtin-property (context)
      ((word (gen-shell-word :min-length 1 :max-length 6))
       (count (gen-in-range 1 6)))
    (multiple-value-bind (output code)
        (call-string-builtin context
                      (list "repeat" "-n" (write-to-string count) "--" word))
      (and (= code 0)
           (= (length output)
              (1+ (* (length word) count)))))))

(test pbt-string-repeat-max-bounds-generated-output-length
  "string repeat -m caps generated output before the trailing newline."
  (assert-string-builtin-property (context)
      ((word (gen-shell-word :min-length 1 :max-length 6))
       (max (gen-in-range 1 12)))
    (multiple-value-bind (output code)
        (call-string-builtin context
                      (list "repeat" "-m" (write-to-string max) "--" word))
      (and (= code 0)
           (= (length output) (1+ max))))))

(test pbt-string-collect-default-trims-generated-trailing-newlines
  "string collect trims generated trailing newlines by default."
  (is
   (assert-string-builtin-property (context)
       ((word (gen-shell-word :min-length 1 :max-length 10))
        (newline-count (gen-in-range 1 4)))
     (let ((input (concatenate 'string
                                word
                                (make-string newline-count
                                             :initial-element #\Newline))))
       (multiple-value-bind (output code)
           (call-string-builtin context (list "collect" "--" input))
         (and (= code 0)
              (string= (format nil "~A~%" word) output)))))))

(test pbt-string-sub-positive-start-and-length-control-output-length
  "string sub -s/-l returns the generated positive-index slice length."
  (is
   (assert-string-builtin-property (context)
       ((word (gen-shell-word :min-length 1 :max-length 12))
        (start (gen-in-range 1 12))
        (requested-length (gen-in-range 1 12)))
     (let* ((expected-length
              (min requested-length
                   (max 0 (- (length word) (1- start)))))
            (expected-code (if (plusp (length word)) 0 1)))
       (multiple-value-bind (output code)
           (call-string-builtin context
                         (list "sub" "-s" (write-to-string start)
                               "-l" (write-to-string requested-length)
                               "--" word))
         (and (= code expected-code)
              (= (length output) (1+ expected-length))))))))

