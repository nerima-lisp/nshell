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

(test string-prefix-p-tests-leading-substring
  "string-prefix-p returns true only when prefix is a leading substring of string."
  (flet ((pre (prefix string)
           (nshell.application::%string-prefix-p prefix string)))
    (is (pre "" "abc"))
    (is (pre "a" "abc"))
    (is (pre "abc" "abc"))
    (is (not (pre "abcd" "abc")))
    (is (not (pre "b" "abc")))))

(test string-parse-integer-option-returns-value-or-error
  "string-parse-integer-option returns (values N nil) on success and (values nil msg) on failure."
  (flet ((parse (opt val)
           (multiple-value-list (nshell.application::%string-parse-integer-option opt val))))
    (is (equal '(5 nil)   (parse "-n" "5")))
    (is (equal '(-3 nil)  (parse "--count" "-3")))
    (is (null (first  (parse "-n" "nope"))))
    (is (search "invalid integer" (second (parse "-n" "nope"))))))

(test string-resolve-attached-value-parses-inline-option-values
  "string-resolve-attached-value extracts inline -N5 and --opt=5 values, nil otherwise."
  (flet ((resolve (option short long short-prefix-len long-prefix-len)
           (nshell.application::%string-resolve-attached-value
            option short long short-prefix-len long-prefix-len)))
    ;; -n5: short prefix "-n" (2 chars), option "-n5" → "5"
    (is (string= "5"  (resolve "-n5"       "-n" "--count" 2 8)))
    ;; --count=5: long prefix "--count=" (8 chars), option "--count=5" → "5"
    (is (string= "5"  (resolve "--count=5" "-n" "--count" 2 8)))
    ;; exact match, no inline value
    (is (null         (resolve "-n"        "-n" "--count" 2 8)))
    (is (null         (resolve "--count"   "-n" "--count" 2 8)))))

(test string-repeat-effective-count-resolves-count-and-max
  "string-repeat-effective-count returns the explicit count, a max-derived count, or 1."
  (flet ((eff (text count max-length)
           (nshell.application::%string-repeat-effective-count text count max-length)))
    (is (= 3 (eff "ab" 3 nil)))
    (is (= 1 (eff "ab" nil nil)))
    (is (= 3 (eff "ab" nil 5)))
    (is (= 1 (eff "ab" nil 0)))
    (is (= 3 (eff "ab" 3 5)))))

(test string-repeat-text-generates-repeated-string
  "string-repeat-text returns nil for zero count and truncates at max-length."
  (flet ((rep (text count &optional max-length)
           (nshell.application::%string-repeat-text text count max-length)))
    (is (string= "abab" (rep "ab" 2)))
    (is (string= "ababa" (rep "ab" 3 5)))
    (is (null (rep "ab" 0)))))

(test string-sub-normalize-indices-handle-negative-values
  "string-sub-normalize-start/end convert negative fish-style indices to 1-based positions."
  (flet ((norm-start (s len)
           (nshell.application::%string-sub-normalize-start s len))
         (norm-end (e len)
           (nshell.application::%string-sub-normalize-end e len)))
    (is (= 3  (norm-start 3 10)))
    (is (= 9  (norm-start -2 10)))
    (is (= 4  (norm-end 4 10)))
    (is (= 9  (norm-end -1 10)))))

(test string-slice-extracts-substrings-with-length-and-end
  "string-slice applies normalized start, length, and end to extract substrings."
  (flet ((slc (text start &key length end)
           (nshell.application::%string-slice text start :length length :end end)))
    (is (string= "bcde" (slc "abcde" 2)))
    (is (string= "bc"   (slc "abcde" 2 :length 2)))
    (is (string= "bc"   (slc "abcde" 2 :end 3)))
    (is (string= "de"   (slc "abcde" -2)))
    (is (string= ""     (slc "abcde" 10)))))

(test string-wildcard-match-p-handles-star-and-question-mark
  "string-wildcard-match-p supports * (any sequence) and ? (single char) wildcards."
  (flet ((match (pat str &key ignore-case)
           (nshell.application::%string-wildcard-match-p pat str :ignore-case ignore-case)))
    (is (match "*.txt" "readme.txt"))
    (is (not (match "*.txt" "readme.md")))
    (is (match "file?" "files"))
    (is (not (match "file?" "filess")))
    (is (match "a*b" "aXYZb"))
    (is (match "GIT*" "git-status" :ignore-case t))
    (is (not (match "GIT*" "git-status" :ignore-case nil)))))

(test string-trim-trailing-newlines-strips-only-trailing-newlines
  "string-trim-trailing-newlines removes only trailing newline characters."
  (flet ((trim (s) (nshell.application::%string-trim-trailing-newlines s)))
    (is (string= "hello"               (trim (format nil "hello~%"))))
    (is (string= "hello"               (trim (format nil "hello~%~%"))))
    (is (string= (format nil "a~%b")   (trim (format nil "a~%b~%"))))
    (is (string= ""                    (trim "")))))
