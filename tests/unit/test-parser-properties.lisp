(in-package #:nshell/test)

(describe "parser-tests"
  (it "shell-assignment-word-p"
    "Shell assignment words are detected independently of completion/history."
    (expect (nshell.domain.parsing:shell-assignment-word-p "FOO=bar") :to-be-truthy)
    (expect (nshell.domain.parsing:shell-assignment-word-p "PATH=/bin:/usr/bin") :to-be-truthy)
    (expect (nshell.domain.parsing:shell-assignment-word-p "git") :to-be-falsy)
    (expect (nshell.domain.parsing:shell-assignment-word-p "FOO-bar") :to-be-falsy))

  (it "shell-separator-predicates"
    "Shell separator predicates share the same domain character sets."
    (dolist (ch '(#\Space #\Tab #\Newline))
      (expect (nshell.domain.parsing:shell-word-separator-p ch) :to-be-truthy))
    (dolist (ch '(#\| #\; #\& #\< #\>))
      (expect (nshell.domain.parsing:shell-operator-separator-p ch) :to-be-truthy)
      (expect (nshell.domain.parsing:shell-token-separator-p ch) :to-be-truthy))
    (expect (nshell.domain.parsing:shell-word-separator-p #\|) :to-be-falsy)
    (expect (nshell.domain.parsing:shell-operator-separator-p #\Space) :to-be-falsy)
    (expect (nshell.domain.parsing:shell-token-separator-p #\a) :to-be-falsy))

  (it "shell-input-blank-p"
    "Blank command input follows shell token separator rules."
    (expect (nshell.domain.parsing:shell-input-blank-p " 	|;&<>") :to-be-truthy)
    (expect (nshell.domain.parsing:shell-input-blank-p
         (format nil " ~c" #\Return)
         :include-return-p t) :to-be-truthy)
    (expect (nshell.domain.parsing:shell-input-blank-p
              (format nil " ~c" #\Return)) :to-be-falsy)
    (expect (nshell.domain.parsing:shell-input-blank-p " echo") :to-be-falsy))

  (it "shell-command-separator-token-p"
    "Command separator tokens are classified in the parsing domain."
    (dolist (type '(:pipe :and :or :semicolon :newline :ampersand))
      (expect (nshell.domain.parsing:shell-command-separator-token-p
           (nshell.domain.parsing:make-token type "")) :to-be-truthy))
    (expect (nshell.domain.parsing:shell-command-separator-token-p
              (nshell.domain.parsing:make-token :redirect ">")) :to-be-falsy)
    (expect (nshell.domain.parsing:shell-command-separator-token-p
              (nshell.domain.parsing:make-token :word "git")) :to-be-falsy)))
