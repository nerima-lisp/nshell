(in-package #:nshell/spec)
(defparameter *l7-rows*
    '((:row 9
       :probe-id "comma-in-word"
       :source nil
       :fixture-v08 :observed
       :v08 :observed
       :v09 (:exit :success :stdout-lines ("a,b") :final-newline t)
       :owner (:warning "S6")
       :warning (:code "W_MID_WORD_SPECIAL"
                 :message-en ", or | in the middle of a word; a literal character from v0.9.0."
                 :message-ja "語の途中の , と |。v0.9.0 から文字として扱う"))
      (:row 10
       :probe-id "brace"
       :source (format nil "(echo {a,b}c)~%")
       :fixture-v08 :observed
       :v08 (:exit :success :stdout-lines ("{a ") :final-newline t)
       :v09 (:exit :success :stdout-lines ("ac bc") :final-newline t)
       :owner (:warning "S6")
       :warning (:code "W_BRACE_EXPANSION"
                 :message-en "Brace expansion such as (echo {a,b}c); it gives ac bc from v0.9.0."
                 :message-ja "(echo {a,b}c) の brace 展開。v0.9.0 から ac bc になる"))
      (:row 11
       :probe-id "pipe-char-word"
       :source nil
       :v08 (:exit 2 :stdout-lines nil :final-newline nil
              :single-value "syntax error")
       :v09 (:exit :success :stdout-lines ("a|b") :final-newline t)
       :owner (:warning "S6")
       :warning (:code "W_MID_WORD_SPECIAL"
                 :message-en ", or | in the middle of a word; a literal character from v0.9.0."
                 :message-ja "語の途中の , と |。v0.9.0 から文字として扱う"))
      (:row 12
       :probe-id "escaped-sym"
       :source (format nil "(echo a\\ b)~%")
       :fixture-v08 (:exit :success :stdout-lines ("Foo Bar a b") :final-newline t)
       :v08 (:exit :success :stdout-lines ("a b") :final-newline t)
       :owner (:v08 "S2"))
      (:row 13
       :probe-id "string-escapes"
       :source (format nil "(echo \"a\\nb\")~%")
       :fixture-v08 (:exit :success :stdout-lines ("a" "b t	x") :final-newline t)
       :v08 (:exit :success :stdout-lines ("a" "b") :final-newline t)
       :owner (:v08 "S2"))
      (:row 14
       :probe-id "kw-arg"
       :source (format nil "(echo :foo)~%")
       :fixture-v08 (:exit :success :stdout-lines (":foo :Bar") :final-newline t)
       :v08 (:exit :success :stdout-lines (":foo") :final-newline t)
       :owner (:v08 "S4" :warning "S6")
       :warning (:code "W_KEYWORD_ARGUMENT"
                 :message-en "A keyword such as :kw used as an argument is passed as the word \":kw\"."
                 :message-ja ":kw を引数にすると \":kw\" として渡す"))
      (:row 15
       :probe-id "unquote-atoms"
       :source nil
       :v08 (:exit :success
              :stdout-lines ("true :kw str 1.5 a")
              :final-newline t)
       :owner (:v08 "S4"))
      (:row 16
       :probe-id "dollar-braced"
       :source nil
       :v08 (:exit :success :home t :final-newline t)
       :owner (:v08 "S2"))
      (:row 17
       :probe-id "dollar-list"
       :source (format nil "(set xs a b c)~%(^printf \"[%s]\" $xs)~%")
       :fixture-v08 :observed
       :v08 (:exit :success :stdout-lines ("[a b c]") :final-newline nil)
       :v09 (:exit :success :stdout-lines ("[a][b][c]") :final-newline nil)
       :owner (:warning "S6")
       :warning (:code "W_LIST_SPLICE"
                 :message-en "$xs expands to one argument per element."
                 :message-ja "$xs が要素ごとの引数になる"))
      (:row 18
       :probe-id "redir-2to1"
       :source (format nil "(^sh -c \"printf err >&2\" 2>&1 > o2.txt)~%(^cat o2.txt)~%")
       :fixture-v08 (:exit :success)
       :v08 (:exit :success :stdout-lines ("err") :final-newline nil)
       :owner (:v08 "S2"))
      (:row 19
       :probe-id "redir-value-target"
       :source nil
       :v08 (:exit :success :stdout-lines ("hi") :final-newline t)
       :owner (:v08 "S2")
       :crash t
       :v07-baseline-skip t)
      (:row 20
       :probe-id "bg-sexp"
       :source (format nil "(sleep 0 &)~%")
       :fixture-v08 (:exit 2 :stdout-lines nil :final-newline nil
                      :single-value "E_PARSE")
       :v08 (:exit 2 :stdout-lines nil :final-newline nil
              :single-value "E_PARSE")
       :owner (:v08 "S2"))
      (:row 21
       :probe-id "and-cmd"
       :source (format nil "(echo __SPEC_CANARY_and_cmd__)~%(and (true) (echo and-ok))~%")
       :v08 (:exit :success :stdout-lines ("__SPEC_CANARY_and_cmd__" "ok") :final-newline t)
       :owner (:v08 "S4"))
      (:row 22
       :probe-id "cmd-in-value"
       :source nil
       :v08 (:exit 1
              :stdout-line-count 4
              :final-newline t
              :stderr-lines nil
              :stderr-final-newline nil
              :single-value "E_VALUE_POSITION"
              :position (1 9 "(echo ,(echo inner))" "echo"))
       :owner (:v08 "S4"))
      (:row 23
       :probe-id "nested-cmd-arg"
       :source (format nil "(echo (echo x))~%")
       :fixture-v08 (:exit :success :stdout-lines ("nested") :final-newline t)
       :v08 (:exit :success :stdout-lines ("x") :final-newline t)
       :owner (:v08 "S4"))
      (:row 24
       :probe-id "var-dollar-in-value"
       :source nil
       :v08 (:exit :success :stdout-lines ("HELLO") :final-newline t)
       :owner (:v08 "S4"))
      (:row 25
       :probe-id "sharp-eq"
       :source nil
       :v08 (:exit :success :stdout-lines ("n" "1") :final-newline t)
       :owner (:v08 "S2"))
      (:row 26
       :probe-id "loop-cmd"
       :source nil
       :v08 (:exit :success :stdout-lines ("1" "2") :final-newline t)
       :owner (:v08 "S2"))
      (:row 27
       :probe-id "sort-in-value"
       :source nil
       :v08 (:exit 1
             :stdout-line-count 4
             :final-newline t
             :stderr-lines nil
             :stderr-final-newline nil
             :single-value "E_VALUE_POSITION"
             :position (1 9 "(echo ,(sort (list 3 1 2) (function <)))" "sort"))
       :owner (:v08 ("S2" "S4"))
       :crash t
       :v07-baseline-skip t)
      (:row 28
       :probe-id "find-in-value"
       :source nil
       :v08 :observed
       :v09 (:exit 1 :single-value "E_VALUE_POSITION")
       :owner (:warning "S6")
       :warning (:code "W_VALUE_POSITION"
                 :message-en ",(find …) whose head is a command in the conflict table; E_VALUE_POSITION from v0.9.0."
                 :message-ja ",(find …) の find が衝突表でコマンドになる。v0.9.0 から E_VALUE_POSITION"
                 :rewrite "cl:find"))
      (:row 29
       :probe-id "last-top"
       :source (format nil "(echo ,@(last (list 1 2)))~%")
       :fixture-v08 :observed
       :v08 (:exit :success :stdout-lines ("2") :final-newline t)
       :v09-source :fixture
       :v09 (:exit :success :stdout-lines ("2") :final-newline t)
       :owner (:warning "S6")
       :warning (:code "W_RESOLUTION_ORDER"
                 :message-en "The input changes meaning once Common Lisp names resolve before PATH, as in (last (list 1 2))."
                 :message-ja "名前解決の順序 (PATH より CL) で意味が変わる入力。(last (list 1 2)) など"
                 :rewrite "cl:last"))
      (:row 30
       :probe-id "defun-sym-args"
       :source (format nil "(defun g2 (a) (echo got=$a))~%(g2 sym)~%")
       :fixture-v08 :observed
       :v08 (:exit :success :stdout-lines ("got=") :final-newline t)
       :v09-source :fixture
       :v09 (:exit 1 :single-value "E_LISP_ERROR"
              :position (2 5 "(g2 sym)" "sym"))
       :owner (:warning "S6" :error "S3")
       :warning (:code "W_DEFUN_WORD_ARGS"
                 :message-en "Words passed from an S-expression to a defun function, as in (g sym)."
                 :message-ja "S式から defun の関数に語を渡した ((g sym) など)"
                 :rewrite "defcmd")
       :v08-current t
       :v07-baseline-skip t
       :crash t
       :crash-source (format nil "(defun g2 (a) (echo got=$a))~%(g2 sym)~%(g2 \"str\")~%(g2 ,(+ 1 1))~%")
       :crash-expectation (:exit 1
                           :stdout-line-count 3
                           :final-newline t
                           :stderr-lines nil
                           :stderr-final-newline nil
                           :single-value "Command argument"
                           :position (4 5 "(g2 ,(+ 1 1))" ","))
       :additional-crash-probes
       ((:probe-id "loop-upper" :crash t :owner (:crash "C"))
        (:probe-id "time-head"
         :v08 (:exit 127
               :stdout-lines nil
               :final-newline nil
               :stderr-lines ("nshell: time: command not found")
               :stderr-final-newline t
               :single-value "command not found")
         :owner (:v08 "S4")
         :crash t
         :v07-baseline-skip t)))
      (:row 31
       :probe-id "print-top"
       :source nil
       :v08 (:exit :success
              :stdout-lines ("" "42")
              :final-newline t
              :stderr-lines nil
              :stderr-final-newline nil
              :single-value "42")
       :owner (:v08 "S3"))
      (:row 32
       :probe-id "bare-fish-if"
       :source nil
       :v08 (:exit 2 :stdout-lines nil :final-newline nil
              :single-value "E_UNSUPPORTED_SYNTAX")
       :owner (:v08 "S3"))
      (:row 33
       :probe-id "bare-paren-mid"
       :source nil
       :v08 (:exit :success :stdout-lines ("3") :final-newline t)
       :owner (:v08 "S2")
       :additional-probes
       nil)
      (:row 34
       :probe-id "pipe-mixed-2"
       :source nil
       :v08 (:exit 2
             :stdout-lines nil
             :final-newline nil
             :stderr-lines ("nshell: $WORK/case.nsh:1:23: syntax error [22,22): Incomplete form at the end of the input.")
             :stderr-final-newline t
             :single-value "syntax error")
       :owner (:v08 "S3")
       :crash t
       :v07-baseline-skip t
       :additional-probes
       ((:row 34
         :probe-id "pipe-mixed-1"
         :v08-current t
         :v07-baseline-skip t
         :v08 (:exit 127
               :stdout-lines nil
               :final-newline nil
               :stderr-lines ("nshell: (tr a-z A-Z): command not found")
               :stderr-final-newline t
               :single-value "command not found"))))
      (:row 35
       :probe-id "bare-var-list"
       :source nil
       :v08 (:exit :success :stdout-lines ("b") :final-newline t)
       :owner (:v08 "S2"))
      (:row 36
       :probe-id "glob-nomatch"
       :source (format nil "(echo *.nomatch)~%")
       :fixture-v08 :observed
       :v08 (:exit :success :stdout-lines ("*.nomatch") :final-newline t)
       :v09 (:exit 1 :single-value "E_NO_MATCH")
       :owner (:warning "S6")
       :warning (:code "W_NO_MATCH"
                 :message-en "A glob in command arguments matched nothing and was kept as the word; E_NO_MATCH from v0.9.0."
                 :message-ja "コマンド引数の glob が一致せず、語のまま渡した。v0.9.0 から E_NO_MATCH"
                 :rewrite "\"*.nomatch\""))
      (:row 37
       :probe-id "mid-dollar"
       :source (format nil "(set x v)~%(echo \${x}.txt)~%")
       :fixture-v08 (:exit :success :stdout-lines ("prev vpost" "prev") :final-newline t)
       :v08 (:exit :success :stdout-lines ("v.txt") :final-newline t)
       :owner (:v08 "S2"))
      (:row 38
       :probe-id "err-lisp"
       :source nil
       :v08 (:exit 1
              :stdout-line-count 4
              :final-newline t
              :stderr-lines nil
              :stderr-final-newline nil
              :single-value "E_LISP_ERROR"
              :position (1 9 "(echo ,(car 1))" "car"))
       :owner (:v08 "S3"))))