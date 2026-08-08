(in-package #:nshell/test)

(describe "history-expansion-domain-tests"
  (it "expands-the-most-recent-command"
    "The `!!` designator resolves to the newest history entry."
    (with-history (history "echo first" "echo second")
      (multiple-value-bind (expanded error)
          (nshell.domain.history:history-expand-line history "!!")
        (expect "echo second" :to-equal expanded)
        (expect error :to-be-null))))

  (it "expands-relative-history-and-the-last-argument"
    "Relative recall and `!$` use the current history ordering."
    (with-history (history "echo first" "printf second")
      (multiple-value-bind (relative relative-error)
          (nshell.domain.history:history-expand-line history "!-2")
        (expect "echo first" :to-equal relative)
        (expect relative-error :to-be-null))
      (multiple-value-bind (argument argument-error)
          (nshell.domain.history:history-expand-line history "!$")
        (expect "second" :to-equal argument)
        (expect argument-error :to-be-null))))

  (it "expands-prefix-and-containing-history-designators"
    "Prefix and `!?query?` recall resolve the newest matching entry."
    (with-history (history "git status" "echo first" "git diff")
      (multiple-value-bind (prefix prefix-error)
          (nshell.domain.history:history-expand-line history "!git")
        (expect "git diff" :to-equal prefix)
        (expect prefix-error :to-be-null))
      (multiple-value-bind (contains contains-error)
          (nshell.domain.history:history-expand-line history "!?status?")
        (expect "git status" :to-equal contains)
        (expect contains-error :to-be-null))))

  (it "leaves-quoted-and-escaped-exclamations-literal"
    "Quoted and backslash-escaped exclamation marks are not expanded."
    (with-history (history "echo first")
      (multiple-value-bind (expanded error)
          (nshell.domain.history:history-expand-line history
                                                      "echo '!echo' \\!echo")
        (expect "echo '!echo' \\!echo" :to-equal expanded)
        (expect error :to-be-null)))))
