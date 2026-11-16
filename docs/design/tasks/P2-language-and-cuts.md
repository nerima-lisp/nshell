# P2 言語の整理と削減

規模: 大。目的: 言語仕様 v0.8 (language/L0〜L7) を実装し、二重実装と計測の層を外す。P1 の golden / spec テストが安全網。P2 の完了で v0.8.0 を出す。

language/L7.1 の各行は、v0.8 で新しい挙動に切り替えるものと、v0.8 では旧挙動のまま書き換え案つきの警告を出して次のバージョン (v0.9.0) で切り替えるものに分かれる。どちらに入るかは language/L7 の表に従う。

## P2-1 読み取り (L1)

- [ ] Lisp の部分の記号を大文字に揃える。コマンドの語は書いたまま。REPL の値の表示は `*print-case* :downcase`
- [ ] 字句の読み方は名前の分類に依存させない。`|…|`・`#`・`,` は Lisp の部分でも語頭でだけ特別な意味を持つ
- [ ] 語の途中の `,` `|` `#` は文字 (`(echo a,b)` と `(echo a|b)` は v0.8 では旧挙動のまま警告し、v0.9.0 で切り替える。L7.1)。`$` は英字・_・{ が続くときだけ変数
- [ ] 文字列のエスケープ \n \t \r \e \0 \\ \" \u{…}
- [ ] Lisp の部分の `<` `>` を比較関数として読む (`(function <)`・`#'<`)
- [ ] 完結した S式は 1 行に複数並べてよい。E_PARSE にするのは、S式の後ろに bare-line が続く場合 (`(echo hi) | tr a-z A-Z` など) だけ
- [ ] スクリプトは全体を読んでから実行 (L6.1)
- [ ] エラーは 1 回だけ、原因の開始位置つきで出す (L6.2)。新しい見た目の表示は P3-3

## P2-2 名前解決 (L2)

- [ ] 2.1 の 9 段の順序を実装し、PATH を見るのは最後の段だけにする
- [ ] 衝突表をデータとして持つ。コマンド側は `sort find sleep time open`。`join` と `split` は CL にないので表に入れない
- [ ] explain に規則番号を出す
- [ ] 意味が変わる入力には v0.8 の間だけ警告。`,(find …)` が E_VALUE_POSITION に変わる件は v0.8 では警告にとどめる

## P2-3 コマンド形式と値 (L3・L4)

- [ ] 引数の書き方の表 (L3.1) と値の変換表 (L3.2)。`(FORM)` 置換と `$(…)`
- [ ] `:kw` をコマンドの引数にしたときは、v0.8 から `":kw"` として渡し、警告を出す
- [ ] リダイレクトの対象に `,EXPR`、`2>&1` などの複製。L3.4 の表にない `>|`・`<&`・`0<`・`1>` も残す
- [ ] `(& FORM)`・`with-env`
- [ ] 位置の規則 (L4.1): 値の位置のコマンドは E_VALUE_POSITION。`and`/`or`/`not` は常に条件として評価
- [ ] CL のマクロの中では、暗黙の本体を文の位置、引数を値の位置として扱う。コードウォーカーか lowering で実装する
- [ ] capture / capture-lines / capture-json / status / run / glob / files / str
- [ ] 一致しない glob は、v0.8 では警告を出して語のまま渡す (次のバージョンで E_NO_MATCH)。変えるのはコマンド引数の展開だけで、補完が使う `expand-glob` には触れない
- [ ] `$name` を Lisp の部分でも使えるように (L4.3)。Lisp の束縛なら大文字にして照合し、シェル変数と環境変数は書いたまま照合する。`$status` は整数
- [ ] 値を返す builtin (L4.4): jobs history dirs functions abbr type complete pwd
- [ ] defcmd (define-shell-function は別名)
- [ ] L2 2.2 の名前は defun でも再定義を拒否する。新しく入る defcmd では v0.8 から E_PARSE。既存の書き方 (defun・define-shell-function・alias・abbr) では v0.8 は警告と `nshell migrate` で知らせ、次のバージョンで E_PARSE にする
- [ ] ある名前が defun と defcmd または alias の両方で定義されたら、後の定義を採って警告する。abbr はスクリプトでは展開しない
- [ ] `out` `view` `clip` `?-` は、P4・P5 で実装するまで E_NOT_IMPLEMENTED を返す
- [ ] レコードと JSON の規則 (L4.6)、where の比較演算子 (L4.7)
- [ ] スクリプトではトップレベルの値を表示しない (L4.8)

## P2-4 bare-line (L5)

- [ ] bare-line の制御構文 (if・for・while・switch・function・begin)、here-doc (`<<`・`<<-`)、`!`、`not cmd; and cmd2` の形を v0.8 で削除する。実行前に E_UNSUPPORTED_SYNTAX で入力全体を拒否し、L5.3 の表にある同じ意味の S式を示す
- [ ] 語の中の ( … ) を S式の置換に
- [ ] `$xs[2]` の添字
- [ ] bare-line の `,expr` は L5.1 の文法にないので、v0.8 では警告し、次のバージョンで削る

## P2-5 移行

- [ ] L7.2 の警告をすべて出す。警告には書き換え案を含める。`--json` では応答の `warnings[]` に入れる
- [ ] 同じ箇所への警告は 1 セッションに 1 回だけ出す
- [ ] `nshell migrate FILE`: 該当箇所と書き換え案の一覧 (書き換えはしない)。予約語 `migrate` を登録する

受け入れ条件 (P2-1〜P2-5 共通): `t/spec/` の v0.8 の期待値 (`it`) がすべて通り、次のバージョンの期待値は `it-fails` のまま残る。それ以外の golden は変わらない (変わったものは理由を PR に書く)。

## P2-6 削除

- [ ] contracts 層 (src/application/contracts, src/presentation/contracts) を unit テストに吸収して削除
- [ ] NFR 計測・競合ベンチのスクリプトのうち、P0-7 の計測で置き換えたものだけを削除する。fuzz の入力 (`scripts/measure-nfr-07-09.py` の `lisp_fuzz_source`) は P5-3 のために残す
- [ ] fish 形式のビルトイン 10 個 (and or not break continue function count contains seq math)、prevd / nextd、pipeline-graph
- [x] slurp / barf、マウス、Ctrl-X 再実行、Alt-C / Alt-L / Alt-U / Alt-T の既定割り当て
- [ ] シナリオコーパスを 30〜40 本に。batch のものは golden へ移し、それ以外は 1 本ずつ削除の理由を記録する。CI が ID を指定している P12・L02・T06・J05・Q03・Q07・Q08 は残す。Q05 の NFS VM 専用ジョブと試行は、2026-11-15 の別々の試行で delayed glob の 3 回目と baseline glob の 1 回目が失敗し、nshell の変更ごとに CI が不安定になっていたため前倒しで外した (`e0c76568`)。`Q05-git-probe-timeout-does-not-block-input` シナリオは対象外である
- [ ] cl-dataflow-kit・cl-boundary-kit への依存を外す (どちらもコードの変更が要る)。cl-boundary-kit をイメージから消すため、cl-concurrent-kit と cl-resilience-kit からも外す。この 2 つでの用途は時計だけなので、cl-host-kit の時計に置き換える

受け入れ条件: 全テストが通り、inventory/I1〜I9 の「削除候補」がすべて消えている。
