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

同じ名前を defun と、defcmd または alias の両方で定義したときは、後の定義を採って警告する。

abbr はスクリプトでは展開しない。

## 2.2 4 番の形式 (いつでも Lisp)

```
if when unless cond case and or not progn prog1 let let* flet labels
block return return-from dolist dotimes loop lambda function quote
setf incf decf push handler-case handler-bind unwind-protect ignore-errors
defun defmacro defcmd define-shell-function defvar defparameter
-> where select sort-by take count first
capture capture-lines capture-json status run with-env glob files out str view clip ?-
```

これらの名前は、defun を含むどの書き方でも再定義できない。新しく入る defcmd は v0.8 から、既存の書き方は v0.9.0 から E_PARSE で拒否する。

| 書き方 | v0.8 | v0.9.0 |
|---|---|---|
| defcmd | E_PARSE | E_PARSE |
| defun・define-shell-function・alias・abbr | 警告し、nshell migrate でも知らせる | E_PARSE |

out・view・clip・?- は、実装されるまで E_NOT_IMPLEMENTED を返す。

## 2.3 衝突表

CL にもあり、シェルでもよく使う 5 つはコマンドとして扱います。Lisp の方は cl: をつけて呼びます。

| 名前 | 既定 | もう一方を使うには |
|---|---|---|
| sort find sleep time open | コマンド | (cl:sort xs #'<) など |
| last write truncate print ほか | Lisp (CL) | (^last) など |

join と split は CL にない名前なので表に入れない。

衝突表のコマンドを値の位置に書くと E_VALUE_POSITION になる。,(find …) は v0.8 では今までどおり CL の find として評価して警告し、v0.9.0 で切り替える (L7)。

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
