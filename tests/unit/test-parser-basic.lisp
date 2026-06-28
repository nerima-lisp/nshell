(in-package #:nshell/test)

(in-suite parser-tests)

(test parse-simple-command
  (with-complete-ast (ast "ls -la")
    (is (nshell.domain.parsing:command-node-p ast))
    (is (string= "ls" (nshell.domain.parsing:command-node-command ast)))
    (is (equal '("-la") (nshell.domain.parsing:command-node-args ast)))))

(test parse-fd-redirects-tokenize-and-need-no-spurious-target
  "fd-prefixed and combined redirects parse cleanly; 2>&1 needs no file target."
  (with-complete-command-line (result ast "cat x 2>err.txt")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (string= "cat" (nshell.domain.parsing:command-node-command ast))))
  (with-complete-command-line (result ast "cat x 2>&1")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (string= "cat" (nshell.domain.parsing:command-node-command ast))))
  (with-complete-command-line (result ast "make &>build.log")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (string= "make" (nshell.domain.parsing:command-node-command ast)))))

(test parse-keeps-dollar-substitutions-attached-to-word
  "$( ) and $(( )) stay attached to surrounding word characters as one argument."
  (with-complete-ast (ast "echo a$((1+2))b")
    (is (equal '("a$((1+2))b")
               (nshell.domain.parsing:command-node-arg-values ast))))
  (with-complete-ast (ast "echo $(echo hi)")
    (is (equal '("$(echo hi)")
               (nshell.domain.parsing:command-node-arg-values ast)))))

(test parse-records-quote-style-per-argument
  "Single and double quotes are distinguished so expansion can treat them differently."
  (with-complete-ast (ast "echo plain \"$FOO\" '*'")
    (let ((args (nshell.domain.parsing:command-node-args ast)))
      (is (= 3 (length args)))
      (assert-arg-quote-styles args nil :double :single))))

(test parse-records-quote-style-for-command-word
  "Command-position quote style is retained so execution can expand it consistently."
  (with-complete-ast (ast "\"$CMD\" plain")
    (is (eq :double
            (nshell.domain.parsing::command-node-command-quote-style ast))))
  (with-complete-ast (ast "'$CMD' plain")
    (is (eq :single
            (nshell.domain.parsing::command-node-command-quote-style ast))))
  (with-complete-ast (ast "$CMD plain")
    (is (null
         (nshell.domain.parsing::command-node-command-quote-style ast)))))

(test parse-pipeline
  (with-complete-ast (ast "ls | grep foo")
    (is (nshell.domain.parsing:pipeline-node-p ast))
    (is (= 2 (length (nshell.domain.parsing:pipeline-node-commands ast))))))

(test ast-node-command-line-renders-command-and-pipeline
  "AST command-line rendering should match the background job display text."
  (with-complete-ast (command "printf %s bg")
    (is (string= "printf %s bg"
                 (nshell.domain.parsing:ast-node->command-line command))))
  (with-complete-ast (pipeline "printf %s bg-pipe | cat")
    (is (string= "printf %s bg-pipe | cat"
                 (nshell.domain.parsing:ast-node->command-line pipeline)))))

(test parse-mixed-sequence-and-pipeline
  (with-complete-ast (ast "echo one | cat; echo two")
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (= 2 (length (nshell.domain.parsing:sequence-node-commands ast))))
    (is (nshell.domain.parsing:pipeline-node-p
         (first (nshell.domain.parsing:sequence-node-commands ast))))
    (is (nshell.domain.parsing:command-node-p
         (second (nshell.domain.parsing:sequence-node-commands ast))))
    (is (equal '(:semi)
               (nshell.domain.parsing:sequence-node-separators ast)))))

(test parse-newline-sequence
  (with-complete-ast (ast (format nil "echo one~%echo two"))
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (= 2 (length (nshell.domain.parsing:sequence-node-commands ast))))
    (is (equal '(:semi)
               (nshell.domain.parsing:sequence-node-separators ast)))))

(test parse-empty-input
  (with-parsed-command-line (result "")
    (is (null (nshell.domain.parsing:parse-result-ast result)))))

(test parse-complete-redirect
  (with-complete-command-line (result ast "echo hello > out.txt")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (nshell.domain.parsing:command-node-p ast))
    (is (equal '("hello" (">" . nil) "out.txt")
               (nshell.domain.parsing:command-node-args ast)))))

(test parse-here-string-redirect
  (with-complete-command-line (result ast "cat <<< hello")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (nshell.domain.parsing:command-node-p ast))
    (is (equal '(("<<<" . nil) "hello")
               (nshell.domain.parsing:command-node-args ast)))))

(test parse-here-document-redirect
  (with-complete-command-line (result ast (format nil "cat << EOF~%hello~%EOF"))
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (nshell.domain.parsing:command-node-p ast))
    (is (equal `(("<<" . nil) ,(format nil "hello~%"))
               (nshell.domain.parsing:command-node-args ast)))))

(test parse-here-document-preserves-tail-command
  (with-complete-command-line (result ast
                                      (format nil "cat << EOF~%hello~%EOF~%echo done"))
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (nshell.domain.parsing:sequence-node-p ast))
    (is (= 2 (length (nshell.domain.parsing:sequence-node-commands ast))))
    (is (equal '(:semi)
               (nshell.domain.parsing:sequence-node-separators ast)))
    (let ((first-command (first (nshell.domain.parsing:sequence-node-commands ast)))
          (second-command (second (nshell.domain.parsing:sequence-node-commands ast))))
      (is (equal `(("<<" . nil) ,(format nil "hello~%"))
                 (nshell.domain.parsing:command-node-args first-command)))
      (is (string= "echo"
                   (nshell.domain.parsing:command-node-command second-command)))
      (is (equal '("done")
                 (nshell.domain.parsing:command-node-args second-command))))))

(test parse-incomplete-here-document
  (with-parsed-command-line (result (format nil "cat << EOF~%hello"))
    (is (nshell.domain.parsing:parse-result-incomplete result))))

(test parse-escaped-space-word
  (with-complete-command-line (result ast "echo hello\\ world")
    (is (null (nshell.domain.parsing:parse-errors result)))
    (is (nshell.domain.parsing:command-node-p ast))
    (is (equal '("hello world")
               (nshell.domain.parsing:command-node-args ast)))))
