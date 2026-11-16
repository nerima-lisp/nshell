(in-package #:nshell/spec)
(defparameter *l7-rows*
    '((:row 9
       :probe-id "comma-in-word"
       :source nil
       :v08 (:exit :success :values ("a"))
       :v09 (:exit :success :values ("a,b")))
      (:row 10
       :probe-id "brace"
       :source (format nil "(echo {a,b}c)~%")
       :fixture-v08 (:exit :success :values ("{a"))
       :v08 (:exit :success :values ("{a"))
       :v09 (:exit :success :values ("ac" "bc")))
      (:row 11
       :probe-id "pipe-char-word"
       :source nil
       :v08 (:exit 2)
       :v09 (:exit :success :values ("a|b")))
      (:row 12
       :probe-id "escaped-sym"
       :source (format nil "(echo a\\ b)~%")
       :fixture-v08 (:exit :success :values ("Foo Bar"))
       :v08 (:exit :success :values ("a b")))
      (:row 13
       :probe-id "string-escapes"
       :source (format nil "(echo \"a\\nb\")~%")
       :fixture-v08 (:exit :success :values ("a" "b"))
       :v08 (:exit :success :values ("a" "b")))
      (:row 14
       :probe-id "kw-arg"
       :source (format nil "(echo :foo)~%")
       :fixture-v08 (:exit :success :values (":foo" ":Bar"))
       :v08 (:exit :success :values (":foo")))
      (:row 15
       :probe-id "unquote-atoms"
       :source (format nil "(echo ,t ,nil x)~%")
       :fixture-v08 (:exit :success :values ("true x"))
       :v08 (:exit :success :values ("true x")))
      (:row 16
       :probe-id "dollar-braced"
       :source nil
       :v08 (:exit :success :home t))
      (:row 17
       :probe-id "dollar-list"
       :source nil
       :v08 (:exit :success :values ("[a b c]"))
       :v09 (:exit :success :values ("[a][b][c]")))
      (:row 18
       :probe-id "redir-2to1"
       :source (format nil "(^sh -c \"printf err >&2\" 2>&1 > o2.txt)~%(^cat o2.txt)~%")
       :fixture-v08 (:exit :success)
       :v08 (:exit :success :values ("err")))
      (:row 19
       :probe-id "redir-value-target"
       :source nil
       :v08 (:exit :success :values ("hi")))
      (:row 20
       :probe-id "bg-sexp"
       :source (format nil "(sleep 0 &)~%")
       :fixture-v08 (:exit 2)
       :v08 (:exit 2))
      (:row 21
       :probe-id "and-cmd"
       :source nil
       :v08 (:exit :success :values ("ok")))
      (:row 22
       :probe-id "cmd-in-value"
       :source nil
       :v08 (:exit 1))
      (:row 23
       :probe-id "nested-cmd-arg"
       :source (format nil "(echo (echo x))~%")
       :fixture-v08 (:exit :success :values ("nested"))
       :v08 (:exit :success :values ("x")))
      (:row 24
       :probe-id "var-dollar-in-value"
       :source nil
       :v08 (:exit :success :values ("HELLO")))
      (:row 25
       :probe-id "sharp-eq"
       :source nil
       :v08 (:exit :success :values ("1")))
      (:row 26
       :probe-id "loop-cmd"
       :source nil
       :v08 (:exit :success :values ("1" "2")))
      (:row 27
       :probe-id "sort-in-value"
       :source nil
       :v08 (:exit 1))
      (:row 28
       :probe-id "find-in-value"
       :source nil
       :v08 (:exit :success :values ("2"))
       :v09 (:exit 1))
      (:row 29
       :probe-id "last-top"
       :source nil
       :v08 (:exit 1)
       :v09 (:exit :success :values ("(2)")))
      (:row 30
       :probe-id "defun-sym-args"
       :source (format nil "(defun g (a) (echo a=$a))~%(g sym)~%")
       :fixture-v08 (:exit :success :values ("got="))
       :v08 (:exit :success :values ("a="))
       :v09 (:exit 1))
      (:row 31
       :probe-id "print-top"
       :source nil
       :v08 (:exit :success :single-value "42"))
      (:row 32
       :probe-id "bare-fish-if"
       :source nil
       :v08 (:exit 2))
      (:row 33
       :probe-id "bare-paren-mid"
       :source nil
       :v08 (:exit :success :values ("3")))
      (:row 34
       :probe-id "pipe-mixed-2"
       :source nil
       :v08 (:exit 2))
      (:row 35
       :probe-id "bare-var-list"
       :source nil
       :v08 (:exit :success :values ("b")))
      (:row 36
       :probe-id "glob-nomatch"
       :source (format nil "(echo *.nomatch)~%")
       :fixture-v08 (:exit :success :values ("*.nomatch" "*.nomatch2"))
       :v08 (:exit :success :values ("*.nomatch"))
       :v09 (:exit 1))
      (:row 37
       :probe-id "mid-dollar"
       :source (format nil "(set x v)~%(echo \${x}.txt)~%")
       :fixture-v08 (:exit :success :values ("prev" "vpost"))
       :v08 (:exit :success :values ("v.txt")))
      (:row 38
       :probe-id "err-lisp"
       :source nil
       :v08 (:exit 1))))