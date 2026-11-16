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
 :input-basis ("L7-diff-and-migration.md:9")
 :v08 (:expect :v07
       :warning (:code "W_MID_WORD_SPECIAL" :rewrite nil)
       :owners ("S6")
       :basis ("L7-diff-and-migration.md:9" "L7-diff-and-migration.md:42"
               "L7-diff-and-migration.md:52" "proposal/02-machine-interface.md:141"
               "execution-plan.md:482" "execution-plan.md:341"))
 :v09 (:expect (:exit 0 :stdout ("a,b") :stdout-final-newline t)
       :input nil
       :basis ("L7-diff-and-migration.md:9" "L7-diff-and-migration.md:52" "L1-lexical.md:28"
               "L6-execution-and-errors.md:9"
               "conformance/language-probes-v0.7.0.json:1231")))

(:row 10
 :probe "brace"
 :input nil
 :input-basis ("L7-diff-and-migration.md:10")
 :v08 (:expect :v07
       :warning (:code "W_BRACE_EXPANSION" :rewrite nil)
       :owners ("S6")
       :basis ("L7-diff-and-migration.md:10" "L7-diff-and-migration.md:42"
               "L7-diff-and-migration.md:53" "proposal/02-machine-interface.md:142"
               "execution-plan.md:482" "execution-plan.md:341"))
 :v09 (:expect (:exit 0 :stdout ("ac bc" "ac bc") :stdout-final-newline t)
       :input nil
       :basis ("L7-diff-and-migration.md:10" "L7-diff-and-migration.md:53" "L3-command-forms.md:9"
               "L3-command-forms.md:40" "L6-execution-and-errors.md:9"
               "conformance/language-probes-v0.7.0.json:1161")))

(:row 11
 :probe "pipe-char-word"
 :input nil
 :input-basis ("L7-diff-and-migration.md:11")
 :v08 (:expect (:exit 2 :error "E_PARSE")
       :warning nil
       :owners ("S3")
       :basis ("L7-diff-and-migration.md:11" "L6-execution-and-errors.md:5"
               "L6-execution-and-errors.md:25" "L6-execution-and-errors.md:29"
               "L6-execution-and-errors.md:40" "L6-execution-and-errors.md:64"
               "execution-plan.md:76" "execution-plan.md:338" "execution-plan.md:482"))
 :v09 (:expect (:exit 0 :stdout ("a|b") :stdout-final-newline t)
       :input nil
       :basis ("L7-diff-and-migration.md:11" "L7-diff-and-migration.md:52" "L1-lexical.md:32"
               "L6-execution-and-errors.md:9")))

(:row 12
 :probe "escaped-sym"
 :input nil
 :input-basis ("L7-diff-and-migration.md:12")
 :v08 (:expect (:exit 0 :stdout ("Foo Bar a b") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("L7-diff-and-migration.md:12" "L1-lexical.md:21" "L1-lexical.md:31"
               "L1-lexical.md:32" "L1-lexical.md:48" "L6-execution-and-errors.md:9"
               "execution-plan.md:336")))

(:row 13
 :probe "string-escapes"
 :input nil
 :input-basis ("L7-diff-and-migration.md:13")
 :v08 (:expect (:exit 0 :stdout ("a" "b t	x") :stdout-final-newline t)   ; TAB between t and x
       :warning nil
       :owners ("S2")
       :basis ("L7-diff-and-migration.md:13" "L1-lexical.md:44" "L3-command-forms.md:10"
               "L6-execution-and-errors.md:9" "execution-plan.md:336")))

(:row 14
 :probe "kw-arg"
 :input "(echo :foo)
"
 :input-basis ("L7-diff-and-migration.md:14" "L7-diff-and-migration.md:44" "execution-plan.md:75")
 :v08 (:expect (:exit 0 :stdout (":foo") :stdout-final-newline t)
       :warning (:code "W_KEYWORD_ARGUMENT" :rewrite nil)
       :owners ("S4" "S6")
       :basis ("L7-diff-and-migration.md:14" "L7-diff-and-migration.md:51" "L3-command-forms.md:13"
               "L1-lexical.md:50" "proposal/02-machine-interface.md:140" "execution-plan.md:62"
               "execution-plan.md:481" "execution-plan.md:337" "execution-plan.md:341"
               "tasks/P2-language-and-cuts.md:28")))

(:row 15
 :probe "unquote-atoms"
 :input nil
 :input-basis ("L7-diff-and-migration.md:15")
 :v08 (:expect (:exit 0 :stdout ("true kw str 1.5 a") :stdout-final-newline t)
       :warning nil
       :owners ("S4")
       :basis ("L7-diff-and-migration.md:15" "L3-command-forms.md:17" "L3-command-forms.md:27"
               "L3-command-forms.md:29" "L3-command-forms.md:30" "L3-command-forms.md:31"
               "L3-command-forms.md:32" "L3-command-forms.md:33" "L1-lexical.md:47"
               "L6-execution-and-errors.md:9" "execution-plan.md:337")))

(:row 16
 :probe "dollar-braced"
 :input nil
 :input-basis ("L7-diff-and-migration.md:16")
 :v08 (:expect (:exit 0 :stdout :home)
       :warning nil
       :owners ("S2")
       :basis ("L7-diff-and-migration.md:16" "L1-lexical.md:33" "L4-values-and-positions.md:35"
               "L6-execution-and-errors.md:9" "execution-plan.md:336")))

(:row 17
 :probe "dollar-list"
 :input "(set xs a b c)
(^printf \"[%s]\" $xs)
"
 :input-basis ("L7-diff-and-migration.md:17" "L7-diff-and-migration.md:54" "L7-diff-and-migration.md:44")
 :v08 (:expect (:exit 0 :stdout ("[a b c]") :stdout-final-newline nil)
       :warning (:code "W_LIST_SPLICE" :rewrite nil)
       :owners ("S6")
       :basis ("L7-diff-and-migration.md:17" "L7-diff-and-migration.md:42"
               "L7-diff-and-migration.md:54" "proposal/02-machine-interface.md:143"
               "L6-execution-and-errors.md:9" "execution-plan.md:482" "execution-plan.md:341"))
 :v09 (:expect (:exit 0 :stdout ("[a][b][c]") :stdout-final-newline nil)
       :input "(set xs a b c)
(^printf \"[%s]\" $xs)
"
       :basis ("L7-diff-and-migration.md:17" "L3-command-forms.md:14" "L4-values-and-positions.md:31"
               "L6-execution-and-errors.md:9")))

(:row 18
 :probe "redir-2to1"
 :input "(^bash -c \"echo err 1>&2\" 2>&1)
"
 :input-basis ("L7-diff-and-migration.md:18" "L3-command-forms.md:57" "L3-command-forms.md:67")
 :v08 (:expect (:exit 0 :stdout ("err") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("L7-diff-and-migration.md:18" "L3-command-forms.md:57" "L3-command-forms.md:63"
               "L3-command-forms.md:67" "L2-resolution.md:9" "L1-lexical.md:26"
               "L6-execution-and-errors.md:9" "execution-plan.md:336")))

(:row 19
 :probe "redir-value-target"
 :input nil
 :input-basis ("L7-diff-and-migration.md:19" "L3-command-forms.md:65")
 :v08 (:expect (:exit 0 :stdout ("hi") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("L7-diff-and-migration.md:19" "L3-command-forms.md:52" "L3-command-forms.md:65"
               "L2-resolution.md:16" "L2-resolution.md:66" "L1-lexical.md:47"
               "L6-execution-and-errors.md:9" "execution-plan.md:336")))

(:row 20
 :probe "bg-sexp"
 :input "(sleep 1 &)
(echo after-bg)
"
 :input-basis ("L7-diff-and-migration.md:20" "L6-execution-and-errors.md:5")
 :v08 (:expect (:exit 2 :error "E_PARSE" :contains ("(& (sleep 1))") :absent ("after-bg"))
       :warning nil
       :owners ("S2" "S3")
       :basis ("L7-diff-and-migration.md:20" "L3-command-forms.md:75" "L6-execution-and-errors.md:5"
               "L6-execution-and-errors.md:25" "L6-execution-and-errors.md:29"
               "L6-execution-and-errors.md:40" "L6-execution-and-errors.md:64"
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
 :v08 (:expect (:exit 1 :error "E_VALUE_POSITION" :position (1 8))
       :warning nil
       :owners ("S3" "S4")
       :basis ("language/L7-diff-and-migration.md:22"
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
       :conflict "language/L7-diff-and-migration.md:29, language/L7-diff-and-migration.md:49 vs language/L3-command-forms.md:19, language/L7-diff-and-migration.md:23: v0.8 keeps PATH-before-CL resolution for last, but the v0.8 substitution rule turns (list 1 2) in a command argument into one argument per element, so v0.8 runs the command `last 1 2` instead of v0.7.0's argument type error"
       :warning (:code "W_RESOLUTION_ORDER" :rewrite nil)
       :owners ("S6")
       :basis ("language/L7-diff-and-migration.md:29"
               "language/L7-diff-and-migration.md:42"
               "language/L7-diff-and-migration.md:49"
               "proposal/02-machine-interface.md:138"))
 :v09 (:expect (:exit 0 :stdout () :stdout-final-newline nil)
       :input nil
       :basis ("language/L7-diff-and-migration.md:29"
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
 :input-basis ("L7-diff-and-migration.md:31")
 :v08 (:expect (:exit 0 :stdout ("" "42 ") :stdout-final-newline nil)
       :warning nil
       :owners ("S3")
       :basis ("L7-diff-and-migration.md:31" "L4-values-and-positions.md:102"
               "L2-resolution.md:16" "L2-resolution.md:50" "L6-execution-and-errors.md:9"
               "execution-plan.md:481" "execution-plan.md:338" "tasks/P2-language-and-cuts.md:42")))

(:row 32
 :probe "bare-fish-if"
 :input "if test 1 = 1
 echo fish-if | tr a-z A-Z
end
"
 :input-basis ("L7-diff-and-migration.md:32" "L5-bare-line.md:34" "L5-bare-line.md:11")
 :v08 (:expect (:exit 2 :error "E_UNSUPPORTED_SYNTAX" :position (1 1) :absent ("FISH-IF"))
       :warning nil
       :owners ("S3")
       :basis ("L7-diff-and-migration.md:32" "L7-diff-and-migration.md:48" "L5-bare-line.md:34"
               "L5-bare-line.md:54" "L6-execution-and-errors.md:25" "L6-execution-and-errors.md:27"
               "L6-execution-and-errors.md:29" "L6-execution-and-errors.md:64" "execution-plan.md:63"
               "execution-plan.md:76" "execution-plan.md:338" "tasks/P2-language-and-cuts.md:46"
               "ruling 2")))

(:row 33
 :probe "bare-paren-mid"
 :input nil
 :input-basis ("L7-diff-and-migration.md:33")
 :v08 (:expect (:exit 0 :stdout ("3") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("L7-diff-and-migration.md:33" "L5-bare-line.md:24" "L3-command-forms.md:19"
               "L3-command-forms.md:28" "inventory/I4-builtins.md:51" "L6-execution-and-errors.md:9"
               "execution-plan.md:336" "tasks/P2-language-and-cuts.md:47")))

(:row 34
 :probe "pipe-mixed-2"
 :input "(| (echo before-marker) (tr a-z A-Z))
(echo hi) | tr a-z A-Z
"
 :input-basis ("L7-diff-and-migration.md:34" "L6-execution-and-errors.md:5" "L3-command-forms.md:73")
 :v08 (:expect (:exit 2 :error "E_PARSE"
                :contains ("(| (echo hi) (tr a-z A-Z))")
                :absent ("BEFORE-MARKER" "HI"))
       :warning nil
       :owners ("S3")
       :basis ("L7-diff-and-migration.md:34" "L1-lexical.md:9" "L6-execution-and-errors.md:5"
               "L6-execution-and-errors.md:25" "L6-execution-and-errors.md:27"
               "L6-execution-and-errors.md:29" "L6-execution-and-errors.md:40"
               "L6-execution-and-errors.md:49" "L6-execution-and-errors.md:64" "execution-plan.md:66"
               "execution-plan.md:76" "execution-plan.md:338" "tasks/P2-language-and-cuts.md:14"
               "tasks/P2-language-and-cuts.md:16" "ruling 2")))

(:row 35
 :probe "bare-var-list"
 :input nil
 :input-basis ("L7-diff-and-migration.md:35")
 :v08 (:expect (:exit 0 :stdout ("b" "b") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("L7-diff-and-migration.md:35" "L3-command-forms.md:15" "L5-bare-line.md:19"
               "L4-values-and-positions.md:31" "inventory/I4-builtins.md:51"
               "L6-execution-and-errors.md:9" "execution-plan.md:336" "tasks/P2-language-and-cuts.md:48")))

(:row 36
 :probe "glob-nomatch"
 :input "(echo *.nomatch)
"
 :input-basis ("L7-diff-and-migration.md:36" "L7-diff-and-migration.md:57" "execution-plan.md:75")
 :v08 (:expect (:exit 0 :stdout ("*.nomatch") :stdout-final-newline t)
       :warning (:code "W_NO_MATCH" :rewrite "\"*.nomatch\"")
       :owners ("S6")
       :basis ("L7-diff-and-migration.md:36" "L7-diff-and-migration.md:42" "L7-diff-and-migration.md:57"
               "L3-command-forms.md:44" "proposal/02-machine-interface.md:146" "execution-plan.md:65"
               "execution-plan.md:482" "execution-plan.md:341" "inventory/I4-builtins.md:51"
               "L6-execution-and-errors.md:9" "tasks/P2-language-and-cuts.md:34"
               "tasks/P2-language-and-cuts.md:53"))
 :v09 (:expect (:exit 1 :error "E_NO_MATCH" :position (1 7))
       :input "(echo *.nomatch)
"
       :basis ("L7-diff-and-migration.md:36" "L7-diff-and-migration.md:57" "L3-command-forms.md:44"
               "L6-execution-and-errors.md:27" "L6-execution-and-errors.md:53"
               "L6-execution-and-errors.md:65")))

(:row 37
 :probe "mid-dollar"
 :input nil
 :input-basis ("L7-diff-and-migration.md:37")
 :v08 (:expect (:exit 0 :stdout ("prev vpost" "prev") :stdout-final-newline t)
       :warning nil
       :owners ("S2")
       :basis ("L7-diff-and-migration.md:37" "L1-lexical.md:33" "L3-command-forms.md:16"
               "L5-bare-line.md:16" "L5-bare-line.md:17" "L5-bare-line.md:19"
               "L4-values-and-positions.md:31" "inventory/I4-builtins.md:51"
               "execution-plan.md:336" "tasks/P2-language-and-cuts.md:11")))

(:row 38
 :probe "err-lisp"
 :input nil
 :input-basis ("L7-diff-and-migration.md:38")
 :v08 (:expect (:exit 1 :error "E_LISP_ERROR" :position (1 8)
                :absent ("after-lisp-error"))
       :warning nil
       :owners ("S3")
       :basis ("L7-diff-and-migration.md:38" "L6-execution-and-errors.md:21" "L6-execution-and-errors.md:25"
               "L6-execution-and-errors.md:27" "L6-execution-and-errors.md:29"
               "L6-execution-and-errors.md:39" "L6-execution-and-errors.md:55"
               "L6-execution-and-errors.md:65" "execution-plan.md:76" "execution-plan.md:338"
               "tasks/P2-language-and-cuts.md:16" "ruling 2")))
)))

;;; Probes whose run must not write a crash log. An owner marks a known crash.
(defparameter *crash-probes*
  (quote
   ((:probe "pipe-mixed-2" :owners ()
  :basis ("proposal/08-robustness.md:40" "L6-execution-and-errors.md:5"))
 (:probe "sort-in-value" :owners ()
  :basis ("proposal/08-robustness.md:40" "L7-diff-and-migration.md:27"))
 (:probe "redir-value-target" :owners ()
  :basis ("proposal/08-robustness.md:40" "L3-command-forms.md:65"))
 (:probe "defun-sym-args" :owners ()
  :basis ("proposal/08-robustness.md:40"))
 (:probe "time-head" :owners ()
  :basis ("proposal/08-robustness.md:40"))
 (:probe "loop-upper" :owners ("C")
  :basis ("proposal/08-robustness.md:40")))
))
