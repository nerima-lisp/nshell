(in-package #:nshell/spec)

;;; One entry per L7.1 row (docs/design/language/L7-diff-and-migration.md).
;;; :input strings hold real newlines because the script is written verbatim.
;;; "execution-plan.md:N" cites the private v0.8 execution plan; "ruling N"
;;; cites the coordinator rulings for P1-7a.

(defparameter *l7-rows*
  (quote
   ((:row 9
 :probe "comma-in-word"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:9")
 :v08 (:expect :v07
       :warning (:code "W_MID_WORD_SPECIAL" :rewrite nil)
       :owners ("S6")
       :basis ("language/L7-diff-and-migration.md:9" "language/L7-diff-and-migration.md:42"
               "language/L7-diff-and-migration.md:52" "proposal/02-machine-interface.md:141"
               "execution-plan.md:482" "execution-plan.md:341"))
 :v09 (:expect (:exit 0 :stdout ("a,b") :stdout-final-newline t)
       :input nil
       :basis ("language/L7-diff-and-migration.md:9" "language/L7-diff-and-migration.md:52" "language/L1-lexical.md:28"
               "language/L6-execution-and-errors.md:9"
               "conformance/language-probes-v0.7.0.json:1231")))

(:row 10
 :probe "brace"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:10")
 :v08 (:expect :v07
       :warning (:code "W_BRACE_EXPANSION" :rewrite nil)
       :owners ("S6")
       :basis ("language/L7-diff-and-migration.md:10" "language/L7-diff-and-migration.md:42"
               "language/L7-diff-and-migration.md:53" "proposal/02-machine-interface.md:142"
               "execution-plan.md:482" "execution-plan.md:341"))
 :v09 (:expect (:exit 0 :stdout ("ac bc" "ac bc") :stdout-final-newline t)
       :input nil
       :basis ("language/L7-diff-and-migration.md:10" "language/L7-diff-and-migration.md:53" "language/L3-command-forms.md:9"
               "language/L3-command-forms.md:40" "language/L6-execution-and-errors.md:9"
               "conformance/language-probes-v0.7.0.json:1161")))

(:row 11
 :probe "pipe-char-word"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:11")
 :v08 (:expect (:exit 2 :error "E_PARSE" :position (1 8) :contains ("\"a|b\""))
       ;; W_MID_WORD_SPECIAL is not asserted. L7-diff-and-migration.md:11 files the row under
       ;; "警告し v0.9.0 で切り替え", which can be read as the warning plus E_PARSE, while
       ;; L7-diff-and-migration.md:52 names (echo a|b) as the case that keeps E_PARSE with a
       ;; rewrite in place of the warning. S6 decides which reading holds when it settles the
       ;; design; until then only the E_PARSE and its rewrite are checked.
       :warning nil
       :owners ("S3" "S6")
       :basis ("language/L7-diff-and-migration.md:11" "language/L7-diff-and-migration.md:52"
               "language/L1-lexical.md:32" "language/L6-execution-and-errors.md:5"
               "language/L6-execution-and-errors.md:25" "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:29" "language/L6-execution-and-errors.md:40"
               "language/L6-execution-and-errors.md:64" "execution-plan.md:76"
               "execution-plan.md:338" "execution-plan.md:341" "execution-plan.md:482"
               "tasks/P2-language-and-cuts.md:53"))
 :v09 (:expect (:exit 0 :stdout ("a|b") :stdout-final-newline t)
       :input nil
       :basis ("language/L7-diff-and-migration.md:11" "language/L7-diff-and-migration.md:52" "language/L1-lexical.md:32"
               "language/L6-execution-and-errors.md:9")))

(:row 12
 :probe "escaped-sym"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:12")
 :v08 (:expect (:exit 0 :stdout ("Foo Bar a b") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("language/L7-diff-and-migration.md:12" "language/L1-lexical.md:21" "language/L1-lexical.md:31"
               "language/L1-lexical.md:32" "language/L1-lexical.md:48" "language/L6-execution-and-errors.md:9"
               "execution-plan.md:336")))

(:row 13
 :probe "string-escapes"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:13")
 :v08 (:expect (:exit 0 :stdout ("a" "b t	x") :stdout-final-newline t)   ; TAB between t and x
       :warning nil
       :owners ("S2")
       :basis ("language/L7-diff-and-migration.md:13" "language/L1-lexical.md:44" "language/L3-command-forms.md:10"
               "language/L6-execution-and-errors.md:9" "execution-plan.md:336")))

(:row 14
 :probe "kw-arg"
 :input "(echo :foo)
"
 :input-basis ("language/L7-diff-and-migration.md:14" "language/L7-diff-and-migration.md:44" "execution-plan.md:75")
 :v08 (:expect (:exit 0 :stdout (":foo") :stdout-final-newline t)
       :warning (:code "W_KEYWORD_ARGUMENT" :rewrite nil)
       :owners ("S4" "S6")
       :basis ("language/L7-diff-and-migration.md:14" "language/L7-diff-and-migration.md:51" "language/L3-command-forms.md:13"
               "language/L1-lexical.md:50" "proposal/02-machine-interface.md:140" "execution-plan.md:62"
               "execution-plan.md:481" "execution-plan.md:337" "execution-plan.md:341"
               "tasks/P2-language-and-cuts.md:28")))

(:row 15
 :probe "unquote-atoms"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:15")
 :v08 (:expect (:exit 0 :stdout ("true kw str 1.5 a") :stdout-final-newline t)
       :warning nil
       :owners ("S4")
       :basis ("language/L7-diff-and-migration.md:15" "language/L3-command-forms.md:17" "language/L3-command-forms.md:27"
               "language/L3-command-forms.md:29" "language/L3-command-forms.md:30" "language/L3-command-forms.md:31"
               "language/L3-command-forms.md:32" "language/L3-command-forms.md:33" "language/L1-lexical.md:47"
               "language/L6-execution-and-errors.md:9" "execution-plan.md:337")))

(:row 16
 :probe "dollar-braced"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:16")
 :v08 (:expect (:exit 0 :stdout :home)
       :warning nil
       :owners ("S2")
       :basis ("language/L7-diff-and-migration.md:16" "language/L1-lexical.md:33" "language/L4-values-and-positions.md:35"
               "language/L6-execution-and-errors.md:9" "execution-plan.md:336")))

(:row 17
 :probe "dollar-list"
 :input "(set xs a b c)
(^printf \"[%s]\" $xs)
"
 :input-basis ("language/L7-diff-and-migration.md:17" "language/L7-diff-and-migration.md:54" "language/L7-diff-and-migration.md:44")
 :v08 (:expect (:exit 0 :stdout ("[a b c]") :stdout-final-newline nil)
       :warning (:code "W_LIST_SPLICE" :rewrite nil)
       :owners ("S6")
       :basis ("language/L7-diff-and-migration.md:17" "language/L7-diff-and-migration.md:42"
               "language/L7-diff-and-migration.md:54" "proposal/02-machine-interface.md:143"
               "language/L6-execution-and-errors.md:9" "execution-plan.md:482" "execution-plan.md:341"))
 :v09 (:expect (:exit 0 :stdout ("[a][b][c]") :stdout-final-newline nil)
       :input "(set xs a b c)
(^printf \"[%s]\" $xs)
"
       :basis ("language/L7-diff-and-migration.md:17" "language/L3-command-forms.md:14" "language/L4-values-and-positions.md:31"
               "language/L6-execution-and-errors.md:9")))

(:row 18
 :probe "redir-2to1"
 :input "(^bash -c \"echo err 1>&2\" 2>&1)
"
 :input-basis ("language/L7-diff-and-migration.md:18" "language/L3-command-forms.md:57" "language/L3-command-forms.md:67")
 :v08 (:expect (:exit 0 :stdout ("err") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("language/L7-diff-and-migration.md:18" "language/L3-command-forms.md:57" "language/L3-command-forms.md:63"
               "language/L3-command-forms.md:67" "language/L2-resolution.md:9" "language/L1-lexical.md:26"
               "language/L6-execution-and-errors.md:9" "execution-plan.md:336")))

(:row 19
 :probe "redir-value-target"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:19" "language/L3-command-forms.md:65")
 :v08 (:expect (:exit 0 :stdout ("hi") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("language/L7-diff-and-migration.md:19" "language/L3-command-forms.md:52" "language/L3-command-forms.md:65"
               "language/L2-resolution.md:16" "language/L2-resolution.md:66" "language/L1-lexical.md:47"
               "language/L6-execution-and-errors.md:9" "execution-plan.md:336")))

(:row 20
 :probe "bg-sexp"
 :input "(sleep 1 &)
(echo after-bg)
"
 :input-basis ("language/L7-diff-and-migration.md:20" "language/L6-execution-and-errors.md:5")
 :v08 (:expect (:exit 2 :error "E_PARSE" :position (1 10)
                :contains ("(& (sleep 1))") :absent ("after-bg"))
       :warning nil
       :owners ("S2" "S3")
       :basis ("language/L7-diff-and-migration.md:20" "language/L3-command-forms.md:75" "language/L6-execution-and-errors.md:5"
               "language/L6-execution-and-errors.md:25" "language/L6-execution-and-errors.md:27" "language/L6-execution-and-errors.md:29"
               "language/L6-execution-and-errors.md:40" "language/L6-execution-and-errors.md:64"
               "execution-plan.md:76" "execution-plan.md:336" "execution-plan.md:338")))
(:row 21
 :probe "and-cmd"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:21")
 :v08 (:expect (:exit 0 :stdout ("and-ok") :stdout-final-newline t)
       :warning nil
       :owners ("S4")
       :basis ("language/L7-diff-and-migration.md:21"
               "language/L4-values-and-positions.md:15"
               "language/L4-values-and-positions.md:8"
               "language/L2-resolution.md:12"
               "language/L2-resolution.md:26"
               "language/L6-execution-and-errors.md:9")))

(:row 22
 :probe "cmd-in-value"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:22")
 :v08 (:expect (:exit 1 :error "E_VALUE_POSITION" :position (1 8)
                :contains ("(capture (echo inner))"))
       :warning nil
       :owners ("S3" "S4")
       :basis ("language/L7-diff-and-migration.md:22"
               "language/L6-execution-and-errors.md:22"
               "language/L4-values-and-positions.md:9"
               "language/L6-execution-and-errors.md:52"
               "language/L6-execution-and-errors.md:65"
               "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:29"
               "language/L6-execution-and-errors.md:21")))

(:row 23
 :probe "nested-cmd-arg"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:23")
 :v08 (:expect (:exit 0 :stdout ("nested") :stdout-final-newline t)
       :warning nil
       :owners ("S4")
       :basis ("language/L7-diff-and-migration.md:23"
               "language/L3-command-forms.md:19"
               "language/L2-resolution.md:64"
               "language/L6-execution-and-errors.md:9")))

(:row 24
 :probe "var-dollar-in-value"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:24")
 :v08 (:expect (:exit 0 :stdout ("HELLO") :stdout-final-newline t)
       :warning nil
       :owners ("S2" "S4")
       :basis ("language/L7-diff-and-migration.md:24"
               "language/L4-values-and-positions.md:31"
               "language/L4-values-and-positions.md:33"
               "language/L2-resolution.md:16"
               "language/L3-command-forms.md:27"
               "language/L6-execution-and-errors.md:9")))

(:row 25
 :probe "sharp-eq"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:25")
 :v08 (:expect (:exit 0 :stdout ("1") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("language/L7-diff-and-migration.md:25"
               "language/L1-lexical.md:47"
               "language/L2-resolution.md:16"
               "language/L3-command-forms.md:28"
               "language/L6-execution-and-errors.md:9")))

(:row 26
 :probe "loop-cmd"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:26")
 :v08 (:expect (:exit 0 :stdout ("i 1" "i 2") :stdout-final-newline t)
       :warning nil
       :owners ("S2" "S4")
       :basis ("language/L7-diff-and-migration.md:26"
               "language/L1-lexical.md:47"
               "language/L2-resolution.md:27"
               "language/L4-values-and-positions.md:13"
               "language/L3-command-forms.md:9"
               "language/L3-command-forms.md:17"
               "language/L3-command-forms.md:28"
               "language/L6-execution-and-errors.md:9")))

(:row 27
 :probe "sort-in-value"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:27")
 :v08 (:expect (:exit 1 :error "E_VALUE_POSITION" :position (1 8))
       :warning nil
       :owners ("S2" "S3" "S4")
       :basis ("language/L7-diff-and-migration.md:27"
               "language/L1-lexical.md:38"
               "language/L2-resolution.md:15"
               "language/L2-resolution.md:49"
               "language/L2-resolution.md:54"
               "language/L4-values-and-positions.md:9"
               "language/L6-execution-and-errors.md:65"
               "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:29"
               "language/L6-execution-and-errors.md:21"
               "execution-plan.md:64")))

(:row 28
 :probe "find-in-value"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:28")
 :v08 (:expect :v07
       :warning (:code "W_VALUE_POSITION" :rewrite "(cl:find")
       :owners ("S6")
       :basis ("language/L7-diff-and-migration.md:28"
               "language/L7-diff-and-migration.md:42"
               "language/L7-diff-and-migration.md:50"
               "language/L2-resolution.md:54"
               "proposal/02-machine-interface.md:139"
               "execution-plan.md:64"))
 :v09 (:expect (:exit 1 :error "E_VALUE_POSITION" :position (1 8))
       :input nil
       :basis ("language/L7-diff-and-migration.md:28"
               "language/L7-diff-and-migration.md:50"
               "language/L2-resolution.md:49"
               "language/L2-resolution.md:54"
               "language/L6-execution-and-errors.md:65"
               "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:21")))

(:row 29
 :probe "last-top"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:29")
 :v08 (:expect :unsettled
       :reason :design-conflict
       :conflict "language/L7-diff-and-migration.md:29, language/L7-diff-and-migration.md:49 vs language/L3-command-forms.md:19, language/L7-diff-and-migration.md:23: v0.8 keeps PATH-before-CL resolution for last, but the v0.8 substitution rule turns (list 1 2) in a command argument into one argument per element, so v0.8 runs the command `last 1 2` instead of v0.7.0's argument type error"
       :warning (:code "W_RESOLUTION_ORDER" :rewrite nil)
       :owners ("S6")
       :basis ("language/L7-diff-and-migration.md:29"
               "language/L7-diff-and-migration.md:42"
               "language/L7-diff-and-migration.md:49"
               "proposal/02-machine-interface.md:138"))
 ;; The marker line makes a binary that prints nothing fail: the value of
 ;; (last (list 1 2)) itself is not displayed in a script (L4.8).
 :v09 (:expect (:exit 0 :stdout ("after-last") :stdout-final-newline t)
       :input "(last (list 1 2))
(echo after-last)
"
       :basis ("language/L7-diff-and-migration.md:29"
               "language/L6-execution-and-errors.md:5"
               "language/L7-diff-and-migration.md:49"
               "language/L2-resolution.md:16"
               "language/L2-resolution.md:50"
               "language/L4-values-and-positions.md:102"
               "language/L6-execution-and-errors.md:9")))

(:row 30
 :probe "defun-sym-args"
 :input "(defun g2 (a) (echo got=$a))
(g2 sym)
"
 :input-basis ("language/L7-diff-and-migration.md:30"
               ;; Line 4 (g2 ,(+ 1 1)) is removed by ruling 4; line 3 (g2 "str") is
               ;; removed so W_DEFUN_WORD_ARGS occurs once without an assumption
               ;; about string arguments (coordinator decision, no ruling number).
               "ruling 4")
 :v08 (:expect (:exit 0 :stdout ("got=") :stdout-final-newline t)
       :warning (:code "W_DEFUN_WORD_ARGS" :rewrite "defcmd")
       :owners ("S6")
       :basis ("language/L7-diff-and-migration.md:30"
               "language/L7-diff-and-migration.md:42"
               "language/L7-diff-and-migration.md:56"
               "language/L4-values-and-positions.md:102"
               "language/L6-execution-and-errors.md:9"
               "proposal/02-machine-interface.md:145"))
 :v09 (:expect (:exit 1 :error "E_LISP_ERROR" :position (2 5))
       :input "(defun g2 (a) (echo got=$a))
(g2 sym)
"
       :basis ("language/L7-diff-and-migration.md:30"
               "language/L7-diff-and-migration.md:56"
               "language/L4-values-and-positions.md:59"
               "language/L1-lexical.md:47"
               "language/L6-execution-and-errors.md:39"
               "language/L6-execution-and-errors.md:55"
               "language/L6-execution-and-errors.md:65"
               "language/L6-execution-and-errors.md:27")))
(:row 31
 :probe "print-top"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:31")
 :v08 (:expect (:exit 0 :stdout ("" "42 ") :stdout-final-newline nil)
       :warning nil
       :owners ("S3")
       :basis ("language/L7-diff-and-migration.md:31" "language/L4-values-and-positions.md:102"
               "language/L2-resolution.md:16" "language/L2-resolution.md:50" "language/L6-execution-and-errors.md:9"
               "execution-plan.md:481" "execution-plan.md:338" "tasks/P2-language-and-cuts.md:42")))

(:row 32
 :probe "bare-fish-if"
 :input "if test 1 = 1
 echo fish-if | tr a-z A-Z
end
"
 :input-basis ("language/L7-diff-and-migration.md:32" "language/L5-bare-line.md:34" "language/L5-bare-line.md:11")
 :v08 (:expect (:exit 2 :error "E_UNSUPPORTED_SYNTAX" :position (1 1)
                :contains ("(if (test 1 = 1)") :absent ("FISH-IF"))
       :warning nil
       :owners ("S3")
       :basis ("language/L7-diff-and-migration.md:32" "language/L7-diff-and-migration.md:48" "language/L5-bare-line.md:34"
               "language/L5-bare-line.md:38" "language/L6-execution-and-errors.md:50" "language/L5-bare-line.md:54" "language/L6-execution-and-errors.md:25" "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:29" "language/L6-execution-and-errors.md:64" "execution-plan.md:63"
               "execution-plan.md:76" "execution-plan.md:338" "tasks/P2-language-and-cuts.md:46"
               "ruling 2")))

(:row 33
 :probe "bare-paren-mid"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:33")
 :v08 (:expect (:exit 0 :stdout ("3") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("language/L7-diff-and-migration.md:33" "language/L5-bare-line.md:24" "language/L3-command-forms.md:19"
               "language/L3-command-forms.md:28" "inventory/I4-builtins.md:51" "language/L6-execution-and-errors.md:9"
               "execution-plan.md:336" "tasks/P2-language-and-cuts.md:47")))

(:row 34
 :probe "pipe-mixed-2"
 :input "(| (echo before-marker) (tr a-z A-Z))
(echo hi) | tr a-z A-Z
"
 :input-basis ("language/L7-diff-and-migration.md:34" "language/L6-execution-and-errors.md:5" "language/L3-command-forms.md:73")
 :v08 (:expect (:exit 2 :error "E_PARSE" :position (2 11)
                :contains ("(| (echo hi) (tr a-z A-Z))")
                :absent ("BEFORE-MARKER" "HI"))
       :warning nil
       :owners ("S3")
       :basis ("language/L7-diff-and-migration.md:34" "language/L1-lexical.md:9" "language/L6-execution-and-errors.md:5"
               "language/L6-execution-and-errors.md:25" "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:29" "language/L6-execution-and-errors.md:40"
               "language/L6-execution-and-errors.md:49" "language/L6-execution-and-errors.md:64" "execution-plan.md:66"
               "execution-plan.md:76" "execution-plan.md:338" "tasks/P2-language-and-cuts.md:14"
               "tasks/P2-language-and-cuts.md:16" "ruling 2")))

(:row 35
 :probe "bare-var-list"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:35")
 :v08 (:expect (:exit 0 :stdout ("b" "b") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("language/L7-diff-and-migration.md:35" "language/L3-command-forms.md:15" "language/L5-bare-line.md:19"
               "language/L4-values-and-positions.md:31" "inventory/I4-builtins.md:51"
               "language/L6-execution-and-errors.md:9" "execution-plan.md:336" "tasks/P2-language-and-cuts.md:48")))

(:row 36
 :probe "glob-nomatch"
 :input "(echo *.nomatch)
"
 :input-basis ("language/L7-diff-and-migration.md:36" "language/L7-diff-and-migration.md:57" "execution-plan.md:75")
 :v08 (:expect (:exit 0 :stdout ("*.nomatch") :stdout-final-newline t)
       :warning (:code "W_NO_MATCH" :rewrite "\"*.nomatch\"")
       :owners ("S6")
       :basis ("language/L7-diff-and-migration.md:36" "language/L7-diff-and-migration.md:42" "language/L7-diff-and-migration.md:57"
               "language/L3-command-forms.md:44" "proposal/02-machine-interface.md:146" "execution-plan.md:65"
               "execution-plan.md:482" "execution-plan.md:341" "inventory/I4-builtins.md:51"
               "language/L6-execution-and-errors.md:9" "tasks/P2-language-and-cuts.md:34"
               "tasks/P2-language-and-cuts.md:53"))
 :v09 (:expect (:exit 1 :error "E_NO_MATCH" :position (1 7))
       :input "(echo *.nomatch)
"
       :basis ("language/L7-diff-and-migration.md:36" "language/L7-diff-and-migration.md:57" "language/L3-command-forms.md:44"
               "language/L6-execution-and-errors.md:27" "language/L6-execution-and-errors.md:53"
               "language/L6-execution-and-errors.md:65")))

(:row 37
 :probe "mid-dollar"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:37")
 :v08 (:expect (:exit 0 :stdout ("prev vpost" "prev") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("language/L7-diff-and-migration.md:37" "language/L1-lexical.md:33" "language/L3-command-forms.md:16"
               "language/L5-bare-line.md:16" "language/L5-bare-line.md:17" "language/L5-bare-line.md:19"
               "language/L4-values-and-positions.md:31" "inventory/I4-builtins.md:51"
               "execution-plan.md:336" "tasks/P2-language-and-cuts.md:11")))

(:row 38
 :probe "err-lisp"
 :input nil
 :input-basis ("language/L7-diff-and-migration.md:38")
 :v08 (:expect (:exit 1 :error "E_LISP_ERROR" :position (1 8)
                :absent ("after-lisp-error"))
       :warning nil
       :owners ("S3")
       :basis ("language/L7-diff-and-migration.md:38" "language/L6-execution-and-errors.md:21" "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27" "language/L6-execution-and-errors.md:29"
               "language/L6-execution-and-errors.md:39" "language/L6-execution-and-errors.md:55"
               "language/L6-execution-and-errors.md:65" "execution-plan.md:76" "execution-plan.md:338"
               "tasks/P2-language-and-cuts.md:16" "ruling 2")))
)))

;;; JSON probes outside L7.1 whose v0.8 behaviour differs from the v0.7.0
;;; record per a design line. Same entry form as a row, without :row; :expect
;;; must be an expectation.
(defparameter *probe-changes*
  (quote
   (
;; ---- r4b-diag: error probes ----
;; ---- E_ARG_TYPE -------------------------------------------------------
(:probe "cl-sort"
 :input nil
 ;; (1 8) = the ( of (cl:sort ...), the offending , argument (convention, as rows 22/27/38).
 ;; ",@(cl:sort" is L6.4's ",@ を使う" applied to the input the way L7.1 row 27 writes it
 ;; ("(echo ,@(cl:sort (list 3 1 2) #'<))"); inferred. Drop :contains to get the
 ;; reviewer-verified shape (exit, code once, position).
 :v08 (:expect (:exit 1 :error "E_ARG_TYPE" :position (1 8) :contains (",@(cl:sort"))
       :warning nil
       :owners ("S3" "S4")
       :basis ("language/L2-resolution.md:11" "language/L3-command-forms.md:17"
               "language/L3-command-forms.md:35" "language/L6-execution-and-errors.md:51"
               "language/L6-execution-and-errors.md:65" "language/L7-diff-and-migration.md:27"
               "language/L6-execution-and-errors.md:25" "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:29" "execution-plan.md:76"
               "execution-plan.md:337" "execution-plan.md:338")))

(:probe "fn-quote"
 :input nil
 ;; (mapcar #'1+ (list 1 2)) is CL (L2.1 row 8); its value (2 3) is a list after , -> E_ARG_TYPE.
 ;; (1 8) = the ( of (mapcar. ",@(mapcar" = L6.4 fix applied; inferred.
 :v08 (:expect (:exit 1 :error "E_ARG_TYPE" :position (1 8) :contains (",@(mapcar"))
       :warning nil
       :owners ("S3" "S4")
       :basis ("language/L2-resolution.md:16" "language/L3-command-forms.md:17"
               "language/L3-command-forms.md:35" "language/L6-execution-and-errors.md:51"
               "language/L6-execution-and-errors.md:65" "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27" "language/L6-execution-and-errors.md:29"
               "execution-plan.md:76" "execution-plan.md:337" "execution-plan.md:338")))

(:probe "unquote-list"
 :input "(^printf \"[%s]\" ,(list 1 2 3))
"
 :input-basis ("language/L3-command-forms.md:35"
               ;; Lines 2-4 of the fixture are dropped so the expectation does not depend on
               ;; whether an E_ARG_TYPE ends a script: language/L6-execution-and-errors.md:39 names
               ;; only E_LISP_ERROR, language/L6-execution-and-errors.md:60 covers every code.
               "language/L6-execution-and-errors.md:39" "language/L6-execution-and-errors.md:60")
 ;; (1 18) = the ( after the , (the offending , argument). ",@(list" = the L6.4 fix applied;
 ;; inferred, drop it if only exit/code/position are wanted.
 :v08 (:expect (:exit 1 :error "E_ARG_TYPE" :position (1 18) :contains (",@(list"))
       :warning nil
       :owners ("S3" "S4")
       :basis ("language/L3-command-forms.md:17" "language/L3-command-forms.md:35"
               "language/L6-execution-and-errors.md:51" "language/L6-execution-and-errors.md:65"
               "language/L6-execution-and-errors.md:9" "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27" "language/L6-execution-and-errors.md:29"
               "execution-plan.md:76" "execution-plan.md:337" "execution-plan.md:338")))

(:probe "cl-sort-top"
 :input nil
 ;; sort is a collision-table command (L2.1 row 7, L2.3). Its argument #'< is a word-head #
 ;; dispatch in a command word (L1.2 # row), read as (function <) (L1:38); a list in argument
 ;; position is a substitution (L2.4:64); function is an L2.2 form, so the value is a function
 ;; object, which L3.2 converts with "そのほか -> E_ARG_TYPE". (list 3 1 2) before it converts
 ;; to 3 1 2 without error. Inferred chain; (1 20) = the # of #'<.
 ;; No :contains: neither ,@ nor (str ...) (L6.4) fixes a function argument, and no design line
 ;; names the cl:sort rewrite as an error fix (L2.3 lists it only as "もう一方を使うには").
 :v08 (:expect (:exit 1 :error "E_ARG_TYPE" :position (1 20))
       :warning nil
       :owners ("S2" "S3" "S4")
       :basis ("language/L2-resolution.md:15" "language/L2-resolution.md:49"
               "language/L1-lexical.md:34" "language/L1-lexical.md:38"
               "language/L2-resolution.md:64" "language/L2-resolution.md:27"
               "language/L3-command-forms.md:19" "language/L3-command-forms.md:36"
               "language/L6-execution-and-errors.md:51" "language/L6-execution-and-errors.md:65"
               "language/L6-execution-and-errors.md:25" "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:29" "execution-plan.md:76"
               "execution-plan.md:336" "execution-plan.md:337" "execution-plan.md:338")))

;; ---- E_VALUE_POSITION ---------------------------------------------------
(:probe "cmd-let"
 :input nil
 ;; Same shape as the L6.2 example (let binding = value position). (1 10) = the ( of
 ;; (echo inner2). "(capture (echo inner2))" = the L6.2 example rewrite applied; inferred.
 ;; No :absent for "inner2": the rewrite itself contains it.
 :v08 (:expect (:exit 1 :error "E_VALUE_POSITION" :position (1 10)
                :contains ("(capture (echo inner2))"))
       :warning nil
       :owners ("S3" "S4")
       :basis ("language/L4-values-and-positions.md:9" "language/L6-execution-and-errors.md:19"
               "language/L6-execution-and-errors.md:20" "language/L6-execution-and-errors.md:22"
               "language/L6-execution-and-errors.md:52" "language/L6-execution-and-errors.md:65"
               "language/L6-execution-and-errors.md:25" "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:29" "execution-plan.md:76"
               "execution-plan.md:337" "execution-plan.md:338" "tasks/P2-language-and-cuts.md:31")))

(:probe "cmd-value"
 :input nil
 ;; (1 10) = the ( of (true). L6.4 names (capture …) and (status …); the L6.2 example for this
 ;; let-binding shape shows capture, so the capture form is checked; inferred.
 :v08 (:expect (:exit 1 :error "E_VALUE_POSITION" :position (1 10)
                :contains ("(capture (true))"))
       :warning nil
       :owners ("S3" "S4")
       :basis ("language/L4-values-and-positions.md:9" "language/L6-execution-and-errors.md:20"
               "language/L6-execution-and-errors.md:22" "language/L6-execution-and-errors.md:52"
               "language/L6-execution-and-errors.md:65" "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27" "language/L6-execution-and-errors.md:29"
               "execution-plan.md:76" "execution-plan.md:337" "execution-plan.md:338"
               "tasks/P2-language-and-cuts.md:31")))

(:probe "cmd-value-false"
 :input nil
 ;; v0.7.0 ran (false) and signalled command-failed; v0.8 rejects the command in the value
 ;; position instead. (1 10) = the ( of (false). Rewrite as cmd-value; inferred.
 :v08 (:expect (:exit 1 :error "E_VALUE_POSITION" :position (1 10)
                :contains ("(capture (false))"))
       :warning nil
       :owners ("S3" "S4")
       :basis ("language/L4-values-and-positions.md:9" "language/L6-execution-and-errors.md:20"
               "language/L6-execution-and-errors.md:22" "language/L6-execution-and-errors.md:52"
               "language/L6-execution-and-errors.md:65" "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27" "language/L6-execution-and-errors.md:29"
               "execution-plan.md:76" "execution-plan.md:337" "execution-plan.md:338"
               "tasks/P2-language-and-cuts.md:31")))

;; ---- E_LISP_ERROR -------------------------------------------------------
(:probe "redir-2"
 :input nil
 ;; (> "out2.txt") is a list in argument position -> substitution (L2.4:64). Its head > is not a
 ;; standalone redirect word of the echo form (L3:63) but a HEAD, classified as the CL function
 ;; (L2.1 row 8, L1:36 Lisp column). CL > signals type-error for a non-real argument in safe
 ;; code (CLHS "should signal type-error"). (1 10) = the ( of (> . The script ends (L6.3), so
 ;; (^cat out2.txt) does not run; no :absent because no marker text is free of the source and
 ;; of coreutils wording.
 ;; Owner S3 only (row 38 precedent): the v0.7.0 record already shows the CL type error, so only
 ;; once/position/code change.
 :v08 (:expect (:exit 1 :error "E_LISP_ERROR" :position (1 10))
       :warning nil
       :owners ("S3")
       :basis ("language/L2-resolution.md:64" "language/L2-resolution.md:16"
               "language/L1-lexical.md:36" "language/L3-command-forms.md:19"
               "language/L3-command-forms.md:63" "language/L6-execution-and-errors.md:39"
               "language/L6-execution-and-errors.md:55" "language/L6-execution-and-errors.md:65"
               "language/L6-execution-and-errors.md:25" "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:29" "proposal/08-robustness.md:40"
               "execution-plan.md:76" "execution-plan.md:338")))

(:probe "var-set-sexp-list"
 :input nil
 ;; (set xs a b) sets a shell variable (builtin, L2.1 row 6). A plain xs in the Lisp part is the
 ;; CL symbol XS (L1.3), not a shell variable: L4.3 gives shell-variable lookup to $name only.
 ;; Evaluating the unbound XS signals unbound-variable (CL). (2 17) = the x of xs, the form whose
 ;; evaluation fails; inferred (the alternative reading is (2 8), the ( of (type-of xs)).
 :v08 (:expect (:exit 1 :error "E_LISP_ERROR" :position (2 17))
       :warning nil
       :owners ("S3" "S4")
       :basis ("language/L2-resolution.md:14" "language/L1-lexical.md:47"
               "language/L4-values-and-positions.md:33" "language/L4-values-and-positions.md:35"
               "language/L2-resolution.md:16" "language/L6-execution-and-errors.md:39"
               "language/L6-execution-and-errors.md:55" "language/L6-execution-and-errors.md:65"
               "language/L6-execution-and-errors.md:25" "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:29" "execution-plan.md:76"
               "execution-plan.md:337" "execution-plan.md:338" "tasks/P2-language-and-cuts.md:35")))

;; ---- v0.8 outcome is not an error -------------------------------------
(:probe "kw-host"
 :input nil
 ;; Same subject as L7.1 row 25: :test reads as :TEST, so position accepts it. getf -> "n",
 ;; position -> 1 (CL, L2.1 row 8); string and integer convert per L3.2. Keywords here are
 ;; Lisp arguments, not command arguments, so no W_KEYWORD_ARGUMENT (L3:13).
 :v08 (:expect (:exit 0 :stdout ("n" "1") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("language/L7-diff-and-migration.md:25" "language/L1-lexical.md:47"
               "language/L1-lexical.md:50" "language/L2-resolution.md:16"
               "language/L3-command-forms.md:17" "language/L3-command-forms.md:27"
               "language/L3-command-forms.md:28" "language/L6-execution-and-errors.md:9"
               "execution-plan.md:336" "tasks/P2-language-and-cuts.md:9")))

(:probe "dollar-in-host"
 :input nil
 ;; Same subject as L7.1 row 24: $v in the Lisp part is the one-element value "hello"
 ;; (L4.3); string= is CL; the if body is a statement position, so echo runs.
 :v08 (:expect (:exit 0 :stdout ("eq") :stdout-final-newline t)
       :warning nil
       :owners ("S2" "S4")
       :basis ("language/L7-diff-and-migration.md:24" "language/L4-values-and-positions.md:33"
               "language/L4-values-and-positions.md:35" "language/L2-resolution.md:12"
               "language/L2-resolution.md:16" "language/L4-values-and-positions.md:7"
               "language/L1-lexical.md:33" "language/L6-execution-and-errors.md:9"
               "execution-plan.md:336" "execution-plan.md:337" "tasks/P2-language-and-cuts.md:35")))

(:probe "cmd-capture-dollar"
 :input nil
 ;; $(…) at word head: run the content as bare-line, stdout without the final newline as one
 ;; argument (L3.1). Owner S4 per P2-3 "(FORM) 置換と $(…)"; S2 may also be needed if the
 ;; S-expression reader must learn $( (inferred, no W3 line names it).
 :v08 (:expect (:exit 0 :stdout ("cap") :stdout-final-newline t)
       :warning nil
       :owners ("S4")
       :basis ("language/L3-command-forms.md:20" "language/L5-bare-line.md:26"
               "language/L6-execution-and-errors.md:9" "execution-plan.md:337"
               "tasks/P2-language-and-cuts.md:27")))

;; ---- r4b-diag: probes with no writable v0.8 expectation ----
(:probe "quote-arg"
 :input nil
 ;; S2: the reader's command-word ' rule (L1:27, L3:11) must define whether '(a b) is a quoted list or a word.
 :v08 (:expect :unsettled
       :reason :rule-scope
       :deferred t
       :conflict "C2: language/L1-lexical.md:27 (command word: ' passes the following word without expansion) vs language/L2-resolution.md:64 with language/L3-command-forms.md:19 (a list in argument position is a substitution); reading A gives stdout `x a b`, reading B `x (a b)`, exit 0 both"
       :warning nil
       :owners ("S2")
       :basis ("language/L1-lexical.md:27"
               "language/L2-resolution.md:64"
               "language/L3-command-forms.md:19"
               "language/L6-execution-and-errors.md:25")))

(:probe "quote-list"
 :input nil
 ;; S2: same command-word ' rule as quote-arg.
 :v08 (:expect :unsettled
       :reason :rule-scope
       :deferred t
       :conflict "C2: language/L1-lexical.md:27 (command word: ' passes the following word without expansion) vs language/L2-resolution.md:64 with language/L3-command-forms.md:19 (a list in argument position is a substitution); reading A gives stdout `a b`, reading B `(a b)`, exit 0 both"
       :warning nil
       :owners ("S2")
       :basis ("language/L1-lexical.md:27"
               "language/L2-resolution.md:64"
               "language/L3-command-forms.md:19"
               "language/L6-execution-and-errors.md:25")))

(:probe "redir-3"
 :input nil
 ;; S4: the value-position check (D-28 walker/lowering, execution-plan.md:69) decides whether it runs before CL evaluation.
 :v08 (:expect :unsettled
       :reason :behaviour-undefined
       :deferred t
       :conflict "C3: language/L4-values-and-positions.md:9 (command in a value position is E_VALUE_POSITION, at (1 13)) vs CL left-to-right evaluation with language/L6-execution-and-errors.md:39 (unbound OUT3.TXT evaluated first, E_LISP_ERROR at (1 4)); the design does not say whether the position check precedes evaluation; exit 1 both"
       :warning nil
       :owners ("S4")
       :basis ("language/L4-values-and-positions.md:9"
               "language/L6-execution-and-errors.md:39"
               "language/L4-values-and-positions.md:13"
               "execution-plan.md:69")))

(:probe "value-pipe"
 :input nil
 ;; :a reads as :A (L1:47, L1:50); (-> X (select :a)) is (select X :a) (L4:96) and keeps
 ;; the column (L4:91); to-json of a select result is fixed in v0.8 (L4:76) and maps :A to
 ;; "a" (L4:70), the list to an array (L4:71), numbers to numbers (L4:73). echo prints the
 ;; one argument (L3:27). No line fixes the JSON spacing or line layout, so stdout is
 ;; compared as one parsed JSON value with object member order ignored.
 :v08 (:expect (:exit 0 :stdout-json "[{\"a\": 1}, {\"a\": 2}]"
                :stderr () :stderr-final-newline nil)
       :warning nil
       :owners ("S5")
       :basis ("language/L1-lexical.md:47" "language/L1-lexical.md:50"
               "language/L4-values-and-positions.md:96" "language/L4-values-and-positions.md:91"
               "language/L4-values-and-positions.md:76" "language/L4-values-and-positions.md:70"
               "language/L4-values-and-positions.md:71" "language/L4-values-and-positions.md:73"
               "language/L4-values-and-positions.md:94" "language/L3-command-forms.md:27"
               "language/L3-command-forms.md:13" "language/L6-execution-and-errors.md:9"
               "execution-plan.md:340" "tasks/P2-language-and-cuts.md:41")))

(:probe "cl-last"
 :input nil
 ;; S4: line 2 inherits row 29's conflict between PATH-first resolution and element-wise substitution (L3:19), which S4 implements.
 :v08 (:expect :unsettled
       :reason :design-conflict
       :deferred t
       :conflict "C4 with C1: v0.8 keeps PATH-before-CL for last (language/L7-diff-and-migration.md:29, language/L7-diff-and-migration.md:49), so ,(last (list 1 2 3)) is a command in a value position, E_VALUE_POSITION at (1 8) (language/L4-values-and-positions.md:9) with W_RESOLUTION_ORDER (proposal/02-machine-interface.md:138); whether line 2 runs depends on C1, language/L6-execution-and-errors.md:39 (only E_LISP_ERROR ends a script) vs language/L6-execution-and-errors.md:60 (exit codes for every code), and line 2 inherits row 29's conflict"
       :warning nil
       :owners ("S4")
       :basis ("language/L7-diff-and-migration.md:29"
               "language/L7-diff-and-migration.md:49"
               "language/L4-values-and-positions.md:9"
               "proposal/02-machine-interface.md:138"
               "language/L6-execution-and-errors.md:39"
               "language/L6-execution-and-errors.md:60")))

(:probe "dollar-paren-sexp-word"
 :input nil
 :v08 (:expect (:exit 0 :stdout ("x$ y") :stdout-final-newline t)
       :warning nil
       :owners ("S2" "S4")
       :basis ("language/L1-lexical.md:7" "language/L1-lexical.md:25" "language/L1-lexical.md:33"
               "language/L3-command-forms.md:19" "language/L2-resolution.md:14"
               "language/L2-resolution.md:64" "inventory/I4-builtins.md:51"
               "language/L6-execution-and-errors.md:9"
               "execution-plan.md:336" "execution-plan.md:337"
               "tasks/P2-language-and-cuts.md:11" "tasks/P2-language-and-cuts.md:27")))

;; ---- r4b-scan-aa ----
(:probe "toplevel-value"
 :input nil
 :v08 (:expect (:exit 0 :stdout ("end") :stdout-final-newline t)
       :warning nil
       :owners ("S3")
       :basis ("language/L4-values-and-positions.md:102"
               "tasks/P2-language-and-cuts.md:42"
               "execution-plan.md:338"
               "language/L6-execution-and-errors.md:9")))

(:probe "case-keyword"
 :input nil
 :v08 (:expect (:exit 0 :stdout ("1") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("language/L1-lexical.md:47"
               "language/L1-lexical.md:50"
               "language/L2-resolution.md:16"
               "language/L3-command-forms.md:28"
               "execution-plan.md:67"
               "execution-plan.md:336"
               "tasks/P2-language-and-cuts.md:9")))

(:probe "test-pos"
 :input nil
 :v08 (:expect (:exit 0 :stdout ("yes" "right" "and-ok" "or-ok") :stdout-final-newline t)
       :warning nil
       :owners ("S4")
       :basis ("language/L4-values-and-positions.md:15"
               "language/L4-values-and-positions.md:8"
               "language/L3-command-forms.md:77"
               "language/L2-resolution.md:26"
               "inventory/I4-builtins.md:36"
               "language/L6-execution-and-errors.md:9"
               "execution-plan.md:337"
               "tasks/P2-language-and-cuts.md:31")))

(:probe "status-var"
 :input nil
 :v08 (:expect (:exit 0 :stdout ("s=1 q=$?" "s=0") :stdout-final-newline t)
       :warning (:code "W_NO_MATCH" :rewrite "\"q=$?\"")
       :owners ("S2" "S6")
       :basis ("language/L1-lexical.md:33"
               "language/L1-lexical.md:35"
               "language/L3-command-forms.md:40"
               "language/L3-command-forms.md:44"
               "language/L4-values-and-positions.md:37"
               "language/L7-diff-and-migration.md:57"
               "proposal/02-machine-interface.md:146"
               "execution-plan.md:65"
               "execution-plan.md:336"
               "execution-plan.md:341"
               "tasks/P2-language-and-cuts.md:11"
               "language/L6-execution-and-errors.md:9")))

(:probe "eq-status"
 :input nil
 :v08 (:expect (:exit 0 :stdout ("true") :stdout-final-newline t)
       :warning (:code "W_STATUS_AS_VALUE" :rewrite "(status (false))")
       :owners ("S4" "S6")
       :basis ("language/L7-diff-and-migration.md:55"
               "language/L3-command-forms.md:32"
               "language/L7-diff-and-migration.md:15"
               "execution-plan.md:481"
               "execution-plan.md:482"
               "proposal/02-machine-interface.md:144"
               "execution-plan.md:337"
               "execution-plan.md:341"))
 :v09 (:expect (:exit 1 :error "E_VALUE_POSITION" :position (1 11))
       :input nil
       :basis ("language/L7-diff-and-migration.md:55"
               "language/L4-values-and-positions.md:9"
               "language/L6-execution-and-errors.md:65"
               "language/L6-execution-and-errors.md:27")))

(:probe "bare-posix-if"
 :input "if true; then echo posix-if | tr a-z A-Z; fi
"
 :input-basis ("language/L5-bare-line.md:34" "language/L6-execution-and-errors.md:5")
 ;; The | tr a-z A-Z marker follows row 32 (AMENDMENT 3 :absent).
 :v08 (:expect (:exit 2 :error "E_UNSUPPORTED_SYNTAX" :position (1 1)
                :contains ("(if (true)") :absent ("POSIX-IF"))
       :warning nil
       :owners ("S3")
       :basis ("language/L5-bare-line.md:34"
               "language/L5-bare-line.md:38"
               "language/L5-bare-line.md:54"
               "language/L7-diff-and-migration.md:48"
               "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:50"
               "language/L6-execution-and-errors.md:64"
               "execution-plan.md:63"
               "execution-plan.md:76"
               "execution-plan.md:338"
               "tasks/P2-language-and-cuts.md:46")))

(:probe "bare-for"
 :input "for i in 1 2
 echo i=$i | tr a-z A-Z
end
"
 :input-basis ("language/L5-bare-line.md:34" "language/L6-execution-and-errors.md:5")
 ;; The | tr a-z A-Z marker follows row 32 (AMENDMENT 3 :absent).
 :v08 (:expect (:exit 2 :error "E_UNSUPPORTED_SYNTAX" :position (1 1)
                :contains ("(dolist (i") :absent ("I="))
       :warning nil
       :owners ("S3")
       :basis ("language/L5-bare-line.md:34"
               "language/L5-bare-line.md:39"
               "language/L5-bare-line.md:54"
               "language/L7-diff-and-migration.md:48"
               "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:50"
               "language/L6-execution-and-errors.md:64"
               "execution-plan.md:63"
               "execution-plan.md:76"
               "execution-plan.md:338"
               "tasks/P2-language-and-cuts.md:46")))

(:probe "bare-heredoc"
 :input "cat <<EOF | tr a-z A-Z
line1
EOF
"
 :input-basis ("language/L5-bare-line.md:34" "language/L6-execution-and-errors.md:5")
 ;; The | tr a-z A-Z marker follows row 32 (AMENDMENT 3 :absent).
 :v08 (:expect (:exit 2 :error "E_UNSUPPORTED_SYNTAX" :position (1 5)
                :contains ("(cat <<<") :absent ("LINE1"))
       :warning nil
       :owners ("S3")
       :basis ("language/L3-command-forms.md:61"
               "language/L5-bare-line.md:34"
               "language/L5-bare-line.md:44"
               "language/L5-bare-line.md:54"
               "language/L7-diff-and-migration.md:48"
               "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:50"
               "language/L6-execution-and-errors.md:64"
               "execution-plan.md:63"
               "execution-plan.md:73"
               "execution-plan.md:76"
               "execution-plan.md:338"
               "tasks/P2-language-and-cuts.md:46")))

(:probe "err-unbalanced"
 :input nil
 :v08 (:expect (:exit 2 :error "E_PARSE" :position (1 1))
       :warning nil
       :owners ("S3")
       :basis ("language/L6-execution-and-errors.md:5"
               "language/L6-execution-and-errors.md:15"
               "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:29"
               "language/L6-execution-and-errors.md:40"
               "language/L6-execution-and-errors.md:64"
               "execution-plan.md:76"
               "execution-plan.md:338"
               "tasks/P2-language-and-cuts.md:16")))

(:probe "err-where"
 :input nil
 :v08 (:expect (:exit 1 :error "E_ARG_TYPE" :position (1 8))
       :warning nil
       :owners ("S3" "S4" "S5")
       :basis ("language/L4-values-and-positions.md:90"
               "language/L4-values-and-positions.md:96"
               "language/L2-resolution.md:30"
               "language/L1-lexical.md:36"
               "language/L3-command-forms.md:35"
               "language/L6-execution-and-errors.md:51"
               "language/L6-execution-and-errors.md:65"
               "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27"
               "execution-plan.md:337"
               "execution-plan.md:338"
               "execution-plan.md:340"
               "tasks/P2-language-and-cuts.md:41")))

(:probe "num-arg"
 :input nil
 ;; S2: the reader's word-head # dispatch (L1:34, D-26) versus numbers passed as written (L1:46, L3:12).
 :v08 (:expect :unsettled
       :reason :design-conflict
       :deferred t
       :conflict "language/L1-lexical.md:21, language/L1-lexical.md:34 and execution-plan.md:67 (D-26: # is a dispatch character at word head in command words, #x10 reads as 16 -> \"16\") vs language/L1-lexical.md:46 with language/L3-command-forms.md:12 (a number in a command word is passed as written, \"#x10\")"
       :warning nil
       :owners ("S2")
       :basis ("language/L1-lexical.md:21"
               "language/L1-lexical.md:34"
               "language/L1-lexical.md:45"
               "language/L1-lexical.md:46"
               "language/L3-command-forms.md:12"
               "execution-plan.md:67")))

(:probe "dollar-undefined"
 :input nil
 ;; S6: the kept $xs shape with W_LIST_SPLICE (L7:17, L7:54) must say whether it covers an undefined variable.
 :v08 (:expect :unsettled
       :reason :rule-scope
       :deferred t
       :conflict "language/L3-command-forms.md:14 with language/L4-values-and-positions.md:31 and language/L4-values-and-positions.md:33 (an undefined variable gives no argument, \"< >\") vs language/L7-diff-and-migration.md:17 and language/L7-diff-and-migration.md:54 (v0.8 keeps the old $xs argument shape with W_LIST_SPLICE, one empty argument \"<  >\"); no line says whether W_LIST_SPLICE fires for an undefined variable"
       :warning nil
       :owners ("S6")
       :basis ("language/L3-command-forms.md:14"
               "language/L4-values-and-positions.md:31"
               "language/L4-values-and-positions.md:33"
               "language/L3-command-forms.md:33"
               "language/L7-diff-and-migration.md:17"
               "language/L7-diff-and-migration.md:54"
               "execution-plan.md:482")))

(:probe "pipe-mixed-1"
 :input nil
 ;; S2: the bare-line (...) substitution (L5:17, L5:24) is not defined as a pipeline stage's command name.
 :v08 (:expect :unsettled
       :reason :rule-scope
       :deferred t
       :conflict "language/L5-bare-line.md:17 and language/L5-bare-line.md:24 (( ... ) in a bare-line word is an S-expression and substituted, L7:33 switch) vs language/L3-command-forms.md:19 (substitution is defined only in argument position, not as the command name, nor which stdin the substituted tr reads in a pipeline stage)"
       :warning nil
       :owners ("S2")
       :basis ("language/L5-bare-line.md:17"
               "language/L5-bare-line.md:24"
               "language/L7-diff-and-migration.md:33"
               "language/L3-command-forms.md:19"
               "execution-plan.md:336")))

(:probe "defun-rest"
 :input nil
 ;; S4: the kept evaluation of (g x y z) gives "空" (L7:30), undefined as nil or "", which the ,@ conversion (L3:33) turns into different output; S6 owns the warning.
 :v08 (:expect :unsettled
       :reason :behaviour-undefined
       :conflict "language/L7-diff-and-migration.md:30, language/L7-diff-and-migration.md:56 and proposal/02-machine-interface.md:145 (v0.8 keeps the old evaluation of x y z and warns W_DEFUN_WORD_ARGS) vs language/L3-command-forms.md:18, language/L3-command-forms.md:33 and language/L7-diff-and-migration.md:15 (v0.8 drops nil elements of ,@): line 1 is \"\" or \"  \"; line 2 \"p q\" per language/L4-values-and-positions.md:59"
       :warning (:code "W_DEFUN_WORD_ARGS" :rewrite "defcmd")
       :owners ("S4" "S6")
       :basis ("language/L7-diff-and-migration.md:30"
               "language/L7-diff-and-migration.md:56"
               "proposal/02-machine-interface.md:145"
               "language/L3-command-forms.md:18"
               "language/L3-command-forms.md:33"
               "language/L7-diff-and-migration.md:15"
               "execution-plan.md:481")))

;; ---- r4b-scan-ab ----
(:probe "lt-host"
 :input nil
 :v08 (:expect (:exit 0 :stdout ("true") :stdout-final-newline t)
       :warning nil
       :owners ("S4")
       :basis ("language/L3-command-forms.md:32" "language/L7-diff-and-migration.md:15"
               "execution-plan.md:481" "language/L1-lexical.md:36" "language/L2-resolution.md:16"
               "language/L6-execution-and-errors.md:9" "tasks/P2-language-and-cuts.md:27"
               "execution-plan.md:337")))

(:probe "or-cmd"
 :input nil
 :v08 (:expect (:exit 0 :stdout ("or-ok") :stdout-final-newline t)
       :warning nil
       :owners ("S4")
       :basis ("language/L4-values-and-positions.md:15" "language/L4-values-and-positions.md:8"
               "language/L3-command-forms.md:77" "language/L2-resolution.md:26"
               "language/L6-execution-and-errors.md:9" "tasks/P2-language-and-cuts.md:31"
               "execution-plan.md:337")))

(:probe "defun-lisp-call"
 :input nil
 :v08 (:expect (:exit 0 :stdout ("9") :stdout-final-newline t)
       :warning nil
       :owners ("S3")
       :basis ("language/L4-values-and-positions.md:102" "language/L7-diff-and-migration.md:31"
               "execution-plan.md:481" "language/L4-values-and-positions.md:59"
               "language/L3-command-forms.md:28" "language/L6-execution-and-errors.md:9"
               "tasks/P2-language-and-cuts.md:42" "execution-plan.md:338")))

(:probe "regex"
 :input nil
 :v08 (:expect (:exit 0 :stdout ("true") :stdout-final-newline t)
       :warning nil
       :owners ("S4")
       :basis ("inventory/I2-language.md:38" "language/L3-command-forms.md:32"
               "language/L7-diff-and-migration.md:15" "execution-plan.md:481"
               "language/L6-execution-and-errors.md:9" "tasks/P2-language-and-cuts.md:27"
               "execution-plan.md:337")))

(:probe "semicolon-word"
 :input nil
 :v08 (:expect (:exit 2 :error "E_PARSE" :position (1 1))
       :warning nil
       :owners ("S3")
       :basis ("language/L1-lexical.md:29" "language/L1-lexical.md:7" "language/L6-execution-and-errors.md:5"
               "language/L6-execution-and-errors.md:15" "language/L6-execution-and-errors.md:25"
               "language/L6-execution-and-errors.md:27" "language/L6-execution-and-errors.md:29"
               "language/L6-execution-and-errors.md:40" "language/L6-execution-and-errors.md:64"
               "tasks/P2-language-and-cuts.md:15" "tasks/P2-language-and-cuts.md:16"
               "execution-plan.md:76" "execution-plan.md:338")))

(:probe "set-list-sexp"
 ;; The marker line makes a binary that prints nothing fail: the value of
 ;; (count $ys) itself is not displayed in a script (L4.8).
 :input "(set ys a b c)
(count $ys)
(echo after-count)
"
 :input-basis ("language/L4-values-and-positions.md:102" "language/L6-execution-and-errors.md:5")
 :v08 (:expect (:exit 0 :stdout ("after-count") :stdout-final-newline t)
       :warning nil
       :owners ("S3" "S4")
       :basis ("language/L2-resolution.md:12" "language/L2-resolution.md:30"
               "language/L4-values-and-positions.md:93" "language/L4-values-and-positions.md:96"
               "language/L4-values-and-positions.md:33" "language/L4-values-and-positions.md:102"
               "language/L4-values-and-positions.md:59" "language/L6-execution-and-errors.md:9"
               "tasks/P2-language-and-cuts.md:20" "tasks/P2-language-and-cuts.md:42"
               "execution-plan.md:337" "execution-plan.md:338")))

(:probe "bang"
 :input nil
 :v08 (:expect (:exit 2 :error "E_UNSUPPORTED_SYNTAX" :position (1 1) :contains ("(not (false))"))
       :warning nil
       :owners ("S3")
       :basis ("language/L5-bare-line.md:45" "language/L5-bare-line.md:34" "language/L5-bare-line.md:54"
               "language/L7-diff-and-migration.md:48" "language/L6-execution-and-errors.md:50"
               "language/L6-execution-and-errors.md:25" "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:64" "tasks/P2-language-and-cuts.md:46"
               "execution-plan.md:63" "execution-plan.md:76" "execution-plan.md:338")))

(:probe "not-bare"
 :input nil
 :v08 (:expect (:exit 2 :error "E_UNSUPPORTED_SYNTAX" :position (1 1) :contains ("(not (false))"))
       :warning nil
       :owners ("S3")
       :basis ("language/L5-bare-line.md:46" "language/L5-bare-line.md:34" "language/L5-bare-line.md:54"
               "language/L7-diff-and-migration.md:48" "language/L6-execution-and-errors.md:50"
               "language/L6-execution-and-errors.md:25" "language/L6-execution-and-errors.md:27"
               "language/L6-execution-and-errors.md:64" "tasks/P2-language-and-cuts.md:46"
               "execution-plan.md:63" "execution-plan.md:76" "execution-plan.md:338")))

(:probe "question"
 :input nil
 :v08 (:expect (:exit 0 :stdout ("?" "ab") :stdout-final-newline t)
       :warning (:code "W_NO_MATCH" :rewrite "\"?\"")   ; rewrite inferred: L6:53 "引用する" applied to `?`
       :owners ("S6")
       :basis ("language/L1-lexical.md:35" "language/L3-command-forms.md:40" "language/L3-command-forms.md:42"
               "language/L3-command-forms.md:44" "language/L7-diff-and-migration.md:42"
               "language/L7-diff-and-migration.md:57" "language/L6-execution-and-errors.md:53"
               "proposal/02-machine-interface.md:146" "language/L6-execution-and-errors.md:9"
               "tasks/P2-language-and-cuts.md:34" "tasks/P2-language-and-cuts.md:53"
               "execution-plan.md:65" "execution-plan.md:341"))
 :v09 (:expect (:exit 1 :error "E_NO_MATCH" :position (1 7))
       :input "(echo ?)
"
       :basis ("language/L3-command-forms.md:44" "language/L7-diff-and-migration.md:57"
               "language/L6-execution-and-errors.md:27" "language/L6-execution-and-errors.md:53"
               "language/L6-execution-and-errors.md:65")))

(:probe "errexit-like"
 :input nil
 ;; Top level: (^false) only sets $status (L6:37), so no command-failed is signalled and the
 ;; handler-case clause (L6:43) never runs; the progn continues to echo. Exit = the last
 ;; command, echo (L6:9).
 :v08 (:expect (:exit 0 :stdout ("after-false") :stdout-final-newline t)
       :warning nil
       :owners ("S3")
       :basis ("language/L6-execution-and-errors.md:37" "language/L6-execution-and-errors.md:43"
               "language/L6-execution-and-errors.md:9" "language/L4-values-and-positions.md:7"
               "language/L2-resolution.md:9" "language/L2-resolution.md:26"
               "language/L2-resolution.md:28" "inventory/I2-language.md:43")))

(:probe "handler-upper"
 :input nil
 ;; Same rule: nothing is signalled, the clause does not run, nothing is printed. Exit = the
 ;; last command, (^false) (L6:9); false exits 1 (coreutils). COMMAND-FAILED and
 ;; command-failed name the same symbol (L1:47), which this input no longer exercises.
 :v08 (:expect (:exit 1 :stdout () :stdout-final-newline nil)
       :warning nil
       :owners ("S3")
       :basis ("language/L6-execution-and-errors.md:37" "language/L6-execution-and-errors.md:43"
               "language/L6-execution-and-errors.md:9" "language/L2-resolution.md:9"
               "language/L2-resolution.md:28" "language/L1-lexical.md:47")))

(:probe "argv-index-fn"
 :input nil
 ;; S4: $argv inside a defun called from bare-line (L4:59, L4:60, L4:35) is undefined.
 :v08 (:expect :unsettled
       :reason :behaviour-undefined
       :deferred t
       :conflict "language/L4-values-and-positions.md:60 ($argv only for defcmd), language/L4-values-and-positions.md:59, inventory/I2-language.md:40 and language/L6-execution-and-errors.md:7 ($argv is the empty script argv: an empty line) vs inventory/I3-expansion.md:26 ($argv / $argv[N] kept as is: p); language/L4-values-and-positions.md:35 does not say whether a defun binds $argv"
       :warning nil
       :owners ("S4")
       :basis ("language/L4-values-and-positions.md:60"
               "language/L4-values-and-positions.md:59"
               "inventory/I2-language.md:40"
               "language/L6-execution-and-errors.md:7"
               "inventory/I3-expansion.md:26"
               "language/L4-values-and-positions.md:35")))

(:probe "set-list-bare"
 :input nil
 ;; S4: how a bare-line head count resolves after F3 deletes the builtin (L2:5, L2:30) is undefined; line 2 also needs the L7:54 bare-line scope.
 :v08 (:expect :unsettled
       :reason :rule-scope
       :deferred t
       :conflict "line 2: language/L7-diff-and-migration.md:54 (warn on $xs element splitting, not restricted to S-expressions) makes the v0.7.0 record insufficient; line 4: F3 deletes the builtin count (execution-plan.md:331, inventory/I4-builtins.md:54) vs count as an L2.2 form (language/L2-resolution.md:30) while language/L2-resolution.md:5 classifies only S-expression lists; the v0.8 output of line 4 and the exit are not derivable"
       :warning nil
       :owners ("S4")
       :basis ("language/L7-diff-and-migration.md:54"
               "execution-plan.md:331"
               "inventory/I4-builtins.md:54"
               "language/L2-resolution.md:30"
               "language/L2-resolution.md:5"
               "tasks/P2-language-and-cuts.md:63"))))))

;;; Probes whose run must not write a crash log. An owner marks a known crash.
(defparameter *crash-probes*
  (quote
   ((:probe "pipe-mixed-2" :owners ()
  :basis ("proposal/08-robustness.md:40" "language/L6-execution-and-errors.md:5"))
 (:probe "sort-in-value" :owners ()
  :basis ("proposal/08-robustness.md:40" "language/L7-diff-and-migration.md:27"))
 (:probe "redir-value-target" :owners ()
  :basis ("proposal/08-robustness.md:40" "language/L3-command-forms.md:65"))
 (:probe "defun-sym-args" :owners ()
  :basis ("proposal/08-robustness.md:40"))
 (:probe "time-head" :owners ()
  :basis ("proposal/08-robustness.md:40"))
 (:probe "loop-upper" :owners ("C")
  :basis ("proposal/08-robustness.md:40")))
))
