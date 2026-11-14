# 現状との差分と移行

## 7.1 現在の動作との差分

左の入力を v0.7.0 (main) で実際に実行した結果と、この仕様での結果です。どれも適合テストとして t/spec/ に入れ、--json の golden test で固定します。v0.8 の列の意味は 7.2 で説明します。

| 入力 | 現在 (v0.7.0) | この仕様 | v0.8 |
|---|---|---|---|
| (echo a,b) | a (b が消える) | a,b | 警告し v0.9.0 で切り替え |
| (echo {a,b}c) | {a | ac bc | 警告し v0.9.0 で切り替え |
| (echo a\|b) | 構文エラー | a\|b | 警告し v0.9.0 で切り替え。v0.8 は今までどおり E_PARSE で、書き換え案を付ける |
| (echo a\ b) | a\ b | a b | 切り替え |
| (echo "a\nb") | anb | a と b の 2 行 | 切り替え |
| (echo :foo) | foo | :foo | 切り替え (警告つき) |
| (echo ,t ,nil x) | T と空の引数と x | true x (nil は引数なし) | 切り替え |
| (echo ${HOME}) | 何も出ない | ホームのパス | 切り替え |
| (set xs a b c) (^printf "[%s]" $xs) | [a b c] | [a][b][c] | 警告し v0.9.0 で切り替え |
| (^ls x 2>&1) | 2>&1 が引数に | リダイレクト | 切り替え |
| (echo hi > ,(f)) | 読み込みエラー | (f) の値のファイルへ | 切り替え |
| (sleep 1 &) | & が sleep の引数に | E_PARSE。(& (sleep 1)) を提示 | 切り替え |
| (and (true) (echo ok)) | 何も実行しない | ok | 切り替え |
| (echo ,(echo x)) | 関数 echo が未定義 | E_VALUE_POSITION と (capture …) の提示 | 切り替え |
| (echo (echo x)) | 関数 echo が未定義 | x (置換) | 切り替え |
| (string-upcase $v) | 関数 UNQUOTE が未定義 | 変数 v の値を大文字に | 切り替え |
| (position 2 xs :test #'=) | 未知の keyword :\|test\| | 動く (Lisp の部分は大文字に揃える) | 切り替え |
| (loop for i from 1 to 2 do (echo ,i)) | LOOP の keyword が不明 | 1 と 2 | 切り替え |
| (echo ,(sort (list 3 1 2) (function <))) | 読み込みエラー (< をリダイレクトと解釈) | 読める。sort は衝突表でコマンドなので E_VALUE_POSITION。(echo ,@(cl:sort (list 3 1 2) #'<)) なら 1 2 3 | 切り替え ((function <) の読み取り) |
| (echo ,(find 2 (list 1 2 3))) | 2 | E_VALUE_POSITION。find は衝突表でコマンド。CL の find は (cl:find …) | 警告し v0.9.0 で切り替え |
| (last (list 1 2)) | /usr/bin/last のコマンドとして扱われ、引数の型エラー | CL の last。値は (2) | 警告し v0.9.0 で切り替え |
| (defun g (a) …) (g sym) | sym を変数として評価し空 | defun は Lisp 関数: sym が未束縛なら E_LISP_ERROR。語で渡すなら defcmd | 警告し v0.9.0 で切り替え |
| (print 42) (スクリプト) | 42 が 2 回 | 1 回 | 切り替え |
| if test 1 = 1 ⏎ echo x ⏎ end | if と end が見つからず、echo x は実行される | 実行前に E_UNSUPPORTED_SYNTAX | 切り替え |
| echo (+ 1 2) | +: command not found | 3 | 切り替え |
| (echo hi) \| tr a-z A-Z | incomplete reader input | E_PARSE と (\| (echo hi) (tr a-z A-Z)) の提示 | 切り替え |
| set ys a b c ⏎ echo $ys[2] | 空 | b | 切り替え |
| (echo *.nomatch) | *.nomatch がそのまま渡る | E_NO_MATCH (fish と同じ)。文字なら "*.nomatch" | 警告し v0.9.0 で切り替え |
| (echo ${x}.txt) | ${x}.txt が消える | 値 + .txt | 切り替え |
| (echo ,(car 1)) | 同じエラーが 2 回、位置なし | 1 回、E_LISP_ERROR と位置 | 切り替え |

## 7.2 移行

v0.8 では、7.1 で「警告し v0.9.0 で切り替え」とした入力は旧挙動のまま動かし、書き換え案つきの警告を出します。v0.9.0 で新しい挙動に切り替えます。7.1 で「切り替え」とした入力は v0.8 から新しい挙動になります。

同じ箇所への警告は、1 セッションに 1 回だけ出す。

| 変更 | v0.8 | v0.9.0 |
|---|---|---|
| bare-line の制御構文 (if・for・while・switch・function・begin)・here-doc (<< <<-)・!・not cmd; and cmd2、builtin の and・or・not・break・continue・function | 実行前に E_UNSUPPORTED_SYNTAX で入力全体を拒否し、同じ意味の S式 (L5.3) を示す | 同じ |
| 名前解決の順序 (PATH より CL。(last (list 1 2)) など) | 意味が変わる入力に警告 | 新しい順序のみ |
| ,(find …) (find は衝突表でコマンド) | 警告 | E_VALUE_POSITION |
| :kw を引数にしたとき | ":kw" として渡し、警告 | ":kw" |
| 語の途中の , と \| | 警告 ((echo a\|b) は今までどおり E_PARSE で、書き換え案を付ける) | 文字として扱う |
| (echo {a,b}c) の brace 展開 | 警告 | ac bc |
| $xs が要素ごとの引数になる | 警告 | 要素ごと |
| (= (cmd) 0) で終了コード | 警告し (status …) を提示 | E_VALUE_POSITION |
| S式から defun の関数に語を渡す ((g sym)) | 警告し defcmd を提示 | Lisp の呼び出しのみ |
| 一致しない glob (コマンド引数だけ。補完の expand-glob は変えない) | 警告 (今までどおり語のまま) | E_NO_MATCH |
| L2.2 の名前の再定義 | defcmd は E_PARSE。defun・define-shell-function・alias・abbr は警告 | E_PARSE |
| bare-line の ,expr | 警告 (今までどおり動かす) | 削る |

nshell migrate FILE がスクリプトを読み、上の変更に当たる箇所と書き換え案を一覧にします (書き換えはしない)。
