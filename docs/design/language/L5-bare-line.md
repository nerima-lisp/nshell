# bare-line

毎日打つ短いコマンドのための近道です。制御構文は持たず、迷ったら S式で書きます。

## 5.1 文法

```
line      = [ list ] [ comment ] NEWLINE
list      = and-or { ( ";" | "&" ) and-or } [ ";" | "&" ]
and-or    = pipeline { ( "&&" | "||" ) pipeline }
pipeline  = command { ( "|" | "|&" ) command }
command   = { assign } word { word | redirect }
assign    = NAME "=" word
redirect  = [ FD ] ( ">" | ">>" | ">|" | "<" | "&>" | "&>>" | "<<<" ) word
          | [ FD ] ( ">&" | "<&" ) FD
word      = part { part }
part      = BARE | SQUOTE | DQUOTE | VAR | "$(" line ")"
          | "(" sexp ")" | "<(" line ")" | ">(" line ")"
VAR       = "$" NAME [ "[" INDEX "]" ] | "${" NAME "}"
```

## 5.2 置換

語の中の ( … ) は S式として読み、L3 と同じ置換をする: echo (date) は出力、echo (+ 1 2) は 3。

$( … ) は中身を bare-line として実行する。"…" の中でも展開する。

( … ) は "…" の中では展開しない (文字そのもの)。

bare-line の ,expr は 5.1 の文法にない。v0.8 では今までどおり扱って警告し、v0.9.0 で削る。

## 5.3 使えない構文と書き換え

次の構文は、実行する前に入力全体を E_UNSUPPORTED_SYNTAX で拒否し、同じ意味の S式を示します。現在は if や end が「コマンドが見つからない」になったうえで、本体だけが実行されてしまいます。

| bare-line | S式 |
|---|---|
| if test -e x; echo y; end | (if (test -e x) (echo y)) |
| for f in *.txt; echo $f; end | (dolist (f (glob "*.txt")) (echo $f)) |
| while test -e lock; sleep 1; end | (loop (unless (test -e lock) (return)) (sleep 1)) |
| switch $x; case a; …; end | (case … ) または (cond …) |
| function f; …; end | (defcmd f () …) |
| begin; …; end | (progn …) |
| cat <<EOF … EOF、cat <<-EOF … EOF | (cat <<< "…複数行の文字列…") |
| ! cmd | (not (cmd)) |
| not cmd; and cmd2 | (and (not (cmd)) (cmd2)) |
| cmd1; and cmd2 | (and (cmd1) (cmd2)) |
| cmd1; or cmd2 | (or (cmd1) (cmd2)) |
| break | (return) |
| continue | 直接対応する S式はない。ループの本体を (when …) か (unless …) で組み替える |

builtin の and・or・not・break・continue・function も同じく拒否する。

この拒否は v0.8 から行う。警告つきで動かす段階は設けない。
