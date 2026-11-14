# 現状との差分と移行

## 7.1 現在の動作との差分

左の入力を v0.7.0 (main) で実際に実行した結果と、この仕様での結果です。どれも適合テストとして t/spec/ に入れ、--json の golden test で固定します。

| 入力 | 現在 (v0.7.0) | この仕様 |
|---|---|---|
| (echo a,b) | a (b が消える) | a,b |
| (echo {a,b}c) | {a | ac bc |
| (echo a\|b) | 構文エラー | a\|b |
| (echo a\ b) | a\ b | a b |
| (echo "a\nb") | anb | a と b の 2 行 |
| (echo :foo) | foo | :foo |
| (echo ,t ,nil x) | T と空の引数と x | true x (nil は引数なし) |
| (echo ${HOME}) | 何も出ない | ホームのパス |
| (set xs a b c) (^printf "[%s]" $xs) | [a b c] | [a][b][c] |
| (^ls x 2>&1) | 2>&1 が引数に | リダイレクト |
| (echo hi > ,(f)) | 読み込みエラー | (f) の値のファイルへ |
| (sleep 1 &) | & が sleep の引数に | E_PARSE。(& (sleep 1)) を提示 |
| (and (true) (echo ok)) | 何も実行しない | ok |
| (echo ,(echo x)) | 関数 echo が未定義 | E_VALUE_POSITION と (capture …) の提示 |
| (echo (echo x)) | 関数 echo が未定義 | x (置換) |
| (string-upcase $v) | 関数 UNQUOTE が未定義 | 変数 v の値を大文字に |
| (position 2 xs :test #'=) | 未知の keyword :\|test\| | 動く (Lisp の部分は大文字に揃える) |
| (loop for i from 1 to 2 do (echo ,i)) | LOOP の keyword が不明 | 1 と 2 |
| (echo ,(sort (list 3 1 2) (function <))) | 読み込みエラー (< をリダイレクトと解釈) | 読める。sort は衝突表でコマンドなので E_VALUE_POSITION。(echo ,@(cl:sort (list 3 1 2) #'<)) なら 1 2 3 |
| (last (list 1 2)) | /usr/bin/last のコマンドとして扱われ、引数の型エラー | CL の last。値は (2) |
| (defun g (a) …) (g sym) | sym を変数として評価し空 | defun は Lisp 関数: sym が未束縛なら E_LISP_ERROR。語で渡すなら defcmd |
| (print 42) (スクリプト) | 42 が 2 回 | 1 回 |
| if test 1 = 1 ⏎ echo x ⏎ end | if と end が見つからず、echo x は実行される | 実行前に E_UNSUPPORTED_SYNTAX |
| echo (+ 1 2) | +: command not found | 3 |
| (echo hi) \| tr a-z A-Z | incomplete reader input | E_PARSE と (\| (echo hi) (tr a-z A-Z)) の提示 |
| set ys a b c ⏎ echo $ys[2] | 空 | b |
| (echo *.nomatch) | *.nomatch がそのまま渡る | E_NO_MATCH (fish と同じ)。文字なら "*.nomatch" |
| (echo ${x}.txt) | ${x}.txt が消える | 値 + .txt |
| (echo ,(car 1)) | 同じエラーが 2 回、位置なし | 1 回、E_LISP_ERROR と位置 |

## 7.2 移行

| 変更 | v0.8 | 次の版 |
|---|---|---|
| bare-line の制御構文・here-doc・! | 警告つきで動かす (本体だけが走る不具合は直す) | E_UNSUPPORTED_SYNTAX |
| 名前解決の順序 (PATH より CL) | 意味が変わる入力に警告 | 新しい順序のみ |
| :kw を引数にしたとき | 警告 (":kw" になる) | ":kw" |
| 語の途中の , と \| | 警告 | 文字として扱う |
| $xs が要素ごとの引数になる | 警告 | 要素ごと |
| (= (cmd) 0) で終了コード | 警告し (status …) を提示 | E_VALUE_POSITION |
| S式から defun の関数に語を渡す ((g sym)) | 警告し defcmd を提示 | Lisp の呼び出しのみ |
| 一致しない glob | 警告 (今までどおり語のまま) | E_NO_MATCH |

nshell migrate FILE がスクリプトを読み、上の変更に当たる箇所と書き換え案を一覧にします (書き換えはしない)。
