(in-package #:nshell/test)

(in-suite parser-tests)

(test shell-assignment-word-p
  "Shell assignment words are detected independently of completion/history."
  (is (nshell.domain.parsing:shell-assignment-word-p "FOO=bar"))
  (is (nshell.domain.parsing:shell-assignment-word-p "PATH=/bin:/usr/bin"))
  (is (not (nshell.domain.parsing:shell-assignment-word-p "git")))
  (is (not (nshell.domain.parsing:shell-assignment-word-p "FOO-bar"))))

(test shell-separator-predicates
  "Shell separator predicates share the same domain character sets."
  (dolist (ch '(#\Space #\Tab #\Newline))
    (is (nshell.domain.parsing:shell-word-separator-p ch)))
  (dolist (ch '(#\| #\; #\& #\< #\>))
    (is (nshell.domain.parsing:shell-operator-separator-p ch))
    (is (nshell.domain.parsing:shell-token-separator-p ch)))
  (is (not (nshell.domain.parsing:shell-word-separator-p #\|)))
  (is (not (nshell.domain.parsing:shell-operator-separator-p #\Space)))
  (is (not (nshell.domain.parsing:shell-token-separator-p #\a))))

(test shell-input-blank-p
  "Blank command input follows shell token separator rules."
  (is (nshell.domain.parsing:shell-input-blank-p " 	|;&<>"))
  (is (nshell.domain.parsing:shell-input-blank-p
       (format nil " ~c" #\Return)
       :include-return-p t))
  (is (not (nshell.domain.parsing:shell-input-blank-p
            (format nil " ~c" #\Return))))
  (is (not (nshell.domain.parsing:shell-input-blank-p " echo"))))

(test shell-command-separator-token-p
  "Command separator tokens are classified in the parsing domain."
  (dolist (type '(:pipe :and :or :semicolon :newline :ampersand))
    (is (nshell.domain.parsing:shell-command-separator-token-p
         (nshell.domain.parsing:make-token type ""))))
  (is (not (nshell.domain.parsing:shell-command-separator-token-p
            (nshell.domain.parsing:make-token :redirect ">"))))
  (is (not (nshell.domain.parsing:shell-command-separator-token-p
            (nshell.domain.parsing:make-token :word "git")))))
