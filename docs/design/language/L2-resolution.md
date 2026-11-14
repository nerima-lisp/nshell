# 形式の分類と名前解決

## 2.1 リストの分類: 上から順に最初に当てはまるもの

S式のリスト (HEAD …) は Lisp 形式かコマンド形式のどちらかです。HEAD の書き方と名前で決まり、PATH の中身では決まりません (最後の行だけが例外)。

| # | HEAD | 種類 | 例 |
|---|---|---|---|
| 1 | ^name | コマンド。PATH の外部コマンドだけを探す (builtin・関数・alias を飛ばす) | (^ls -la) |
| 2 | \| \|& & | 構文形式 (パイプ・背景) | (\| (ls) (wc -l)) |
| 3 | pkg:name | Lisp | (cl:sort xs #'<) |
| 4 | 特殊形式と nshell の形式 (下の表) | Lisp。再定義できない | (if …) (capture …) |
| 5 | 利用者の定義 | defcmd・alias・abbr ならコマンド、defun・defmacro なら Lisp | (deploy staging) |
| 6 | builtin | コマンド | (cd /tmp) (set x 1) |
| 7 | 衝突表の名前 | コマンド | (sort -u a.txt) |
| 8 | CL の関数とマクロ | Lisp | (format t "~a" x) |
| 9 | それ以外 | コマンド。実行時に PATH を探し、なければ 127 | (git status) |

## 2.2 4 番の形式 (いつでも Lisp)

```
if when unless cond case and or not progn prog1 let let* flet labels
block return return-from dolist dotimes loop lambda function quote
setf incf decf push handler-case handler-bind unwind-protect ignore-errors
defun defmacro defcmd define-shell-function defvar defparameter
-> where select sort-by take count first
capture capture-lines capture-json status run with-env glob files out str view clip ?-
```

これらの名前で defcmd・alias・abbr を定義しようとしたら E_PARSE で拒否する。

## 2.3 衝突表

CL にもあり、シェルでもよく使う 6 つはコマンドとして扱います。Lisp の方は cl: をつけて呼びます。

| 名前 | 既定 | もう一方を使うには |
|---|---|---|
| sort find join split sleep time | コマンド | (cl:sort xs #'<) など |
| last write expand truncate print ほか | Lisp (CL) | (^last) など |

表は nshell の版ごとに固定し、変えるときは破壊的変更として扱う。

名前が 7 と 8 の両方にあるかどうかは PATH を見ずに決まる。

## 2.4 入れ子と位置

分類の規則はどの深さでも同じ。違いは書かれた位置 (L4) だけ。

コマンドの引数の位置にあるリストは分類の前に「置換」として扱う (L3)。

, と ,@ のあとの式も同じ規則で分類する。その位置は値の位置なので、コマンドは capture などで包む。

## 2.5 explain で分類を確かめる

```
$ nshell --json explain '(sort data.txt)'
{"forms": [{"text": "(sort data.txt)", "kind": "command",
            "rule": "2.1-7 collision", "path": "/usr/bin/sort"}]}
```

REPL では入力中のリストの色 (コマンドはシアン、Lisp は紫) と、Tab の説明でも同じ分類を示します。
