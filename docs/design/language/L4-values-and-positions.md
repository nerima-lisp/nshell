# Lisp 形式・位置・値

## 4.1 位置: コマンドを書いた場所で意味が決まる

| 位置 | どこ | コマンドの扱い |
|---|---|---|
| 文 | トップレベル、progn・let・when などの本体、関数の本体 | 実行し、出力は端末へ。終了コードは $status |
| 条件 | if・when・unless・cond の条件、and・or・not の引数 | 終了コード 0 なら真。失敗しても信号にならない |
| 値 | 関数の引数、let の束縛、, のあと、-> の段 | 直接は書けない (E_VALUE_POSITION)。4.2 の形式で包む。ただし 4.4 の builtin は値を返す |
| パイプの段 | (\| …) の中 | バイト列でつなぐ |
| 引数 | コマンドの引数の中の ( … ) | 置換 (L3) |

CL のマクロ (loop など) の中では、暗黙の本体を文の位置、引数を値の位置として扱う。実装はコードウォーカーか lowering で行う。

and・or は文の位置でも条件として評価する。現在はトップレベルの (and (true) (echo ok)) が何も実行しない。

## 4.2 コマンドから値を得る形式

| 形式 | 値 | 失敗したとき |
|---|---|---|
| (capture CMD) | stdout の文字列 (末尾の改行 1 つを除く) | command-failed |
| (capture-lines CMD) | 行のリスト | command-failed |
| (capture-json CMD) | stdout を from-json したもの | command-failed |
| (status CMD) | 終了コードの整数 | 信号なし |
| (run CMD) | (:status :stdout :stderr :duration-ms) のレコード | 信号なし |

補助: (glob "*.txt") はパスのリスト、(files "src") はファイルのレコード、(out) と (out -2) は直前・2 つ前の出力を (:line :text) のレコードで (U8)、(str a $b ,c) は 3.2 の変換で文字列をつなぐ。

## 4.3 シェル変数

値は文字列のリスト。(set xs a b c) は 3 要素、(set x a) は 1 要素。

Lisp の部分の $name は値を返す: 要素が 1 つなら文字列、2 つ以上ならリスト、未定義なら nil (現在は読み込みエラー)。

探す順: let などの Lisp の束縛 → 関数の局所 → 大域 → 環境変数。Lisp の束縛は名前を大文字にして照合し、シェル変数と環境変数は書いたまま照合する。

$status・$pipestatus・$argv は読み取り専用。Lisp の部分の $status は整数。

set -l -g -x -e -q はそのまま。S式からは (set -x NAME ,value)。

## 4.4 値を返す builtin

次の builtin は値の位置で呼ぶとレコードを返し、文の位置では今までどおり表示します。

| builtin | 値 |
|---|---|
| jobs | (:id :state :pid :command) |
| history | (:text :cwd :status :duration-ms :time :origin) |
| dirs | パスのリスト |
| functions abbr | 名前と定義 |
| type | (:name :kind :path) |
| complete -C LINE | (:text :kind :description) |
| pwd | 文字列 |

## 4.5 関数

| 定義 | S式からの呼び出し | bare-line から | 結果 |
|---|---|---|---|
| (defun f (a b) …) | Lisp の呼び出し。引数は評価される | 語を文字列で渡す | 値。状態は 0 |
| (defcmd f (a &rest r) …) | コマンド。引数は語 (L3)。$argv に全部 | 同じ | 終了コード (本体の最後のコマンド) |

define-shell-function は defcmd の別名として残す。

functions/NAME.nsh の自動読み込みは両方に効く。

## 4.6 レコードと JSON

| JSON | 値 | 備考 |
|---|---|---|
| object | plist (:NAME "x" :AGE 3) | キー: 小文字だけなら大文字の keyword、ほかは書いたまま (:\|userName\|)。逆変換で元に戻る |
| array | リスト | [] は nil |
| {} | :empty-object |  |
| string number | 文字列・数 |  |
| true false null | t :false :null | nil は [] に戻る。false を書くなら :false |

現在は select の結果 (keyword キー) を to-json できない。from-json はキーを文字列で返すので、両者を 1 つの形に揃える。

## 4.7 値パイプライン

```
(-> (jobs)
    (where (and (= :state "stopped") (match :command "^vim")))
    (sort-by :id :desc)
    (select :id :command)
    (take 5))
```

| 変換 | 意味 |
|---|---|
| where | 条件: = /= < <= > >= and or not、(has :k)、(match :k "re") |
| select :k … | 列を選ぶ |
| sort-by :k [:desc] | 並べ替え |
| take n first count | 先頭 n 件・最初の 1 件・件数 |
| to-json to-lines to-tsv | テキストへ (from-… は逆) |

(-> X (f a) g) は (g (f X a)) と同じ。

## 4.8 トップレベルの値

REPL では Lisp 形式の値が nil 以外なら ⇒ のあとに表示する。表示は *print-case* :downcase で行う。

スクリプトでは表示しない (現在は (print 42) の 42 が 2 回出る)。
