# P2 言語の整理と削減

規模: 大。目的: 言語仕様 v0.8 (language/L0〜L7) を実装し、二重実装と計測の層を外す。P1 の golden / spec テストが安全網。

## P2-1 読み取り (L1)

- [ ] Lisp の部分の記号を大文字に揃える。コマンドの語は書いたまま
- [ ] 語の途中の `,` `|` `#` は文字。`$` は英字・_・{ が続くときだけ変数
- [ ] 文字列のエスケープ \n \t \r \e \0 \\ \" \u{…}
- [ ] Lisp の部分の `<` `>` を比較関数として読む (`(function <)`・`#'<`)
- [ ] スクリプトは全体を読んでから実行 (L6.1)

## P2-2 名前解決 (L2)

- [ ] 2.1 の 9 段の順序を実装し、PATH を見るのは最後の段だけにする
- [ ] 衝突表 (sort find join split sleep time) をデータとして持つ
- [ ] explain に規則番号を出す
- [ ] 意味が変わる入力には v0.8 の間だけ警告

## P2-3 コマンド形式と値 (L3・L4)

- [ ] 引数の書き方の表 (L3.1) と値の変換表 (L3.2)。`(FORM)` 置換と `$(…)`
- [ ] リダイレクトの対象に `,EXPR`、`2>&1` などの複製
- [ ] `(& FORM)`・`with-env`
- [ ] 位置の規則 (L4.1): 値の位置のコマンドは E_VALUE_POSITION。`and`/`or`/`not` は常に条件として評価
- [ ] capture / capture-lines / capture-json / status / run / glob / files / str
- [ ] `$name` を Lisp の部分でも使えるように (L4.3)
- [ ] 値を返す builtin (L4.4): jobs history dirs functions abbr type complete pwd
- [ ] defcmd (define-shell-function は別名)
- [ ] レコードと JSON の規則 (L4.6)、where の比較演算子 (L4.7)
- [ ] スクリプトではトップレベルの値を表示しない (L4.8)

## P2-4 bare-line (L5)

- [ ] 制御構文・here-doc・`!`・fish 形式の function を v0.8 では警告つきで動かし、本体だけが走る不具合を直す
- [ ] 語の中の ( … ) を S式の置換に
- [ ] `$xs[2]` の添字

## P2-5 移行

- [ ] L7.2 の警告をすべて出す。警告には書き換え案を含める
- [ ] `nshell migrate FILE`: 該当箇所と書き換え案の一覧 (書き換えはしない)

受け入れ条件 (P2-1〜P2-5 共通): `t/spec/` の pending 行がすべて L7 の右列の期待値で通る。それ以外の golden は変わらない (変わったものは理由を PR に書く)。

## P2-6 削除

- [ ] contracts 層 (src/application/contracts, src/presentation/contracts) を unit テストに吸収して削除
- [ ] NFR 計測・競合ベンチのスクリプトを削除し、起動時間とキー入力遅延のベンチ 2 本を残す
- [ ] fish 形式のビルトイン 10 個 (and or not break continue function count contains seq math)、prevd / nextd、pipeline-graph
- [ ] slurp / barf、マウス、Ctrl-X 再実行、Alt-C / Alt-L / Alt-U / Alt-T の既定割り当て
- [ ] シナリオコーパスを 30〜40 本に (残りは golden へ移したか、不要と判断した理由を PR に)
- [ ] cl-dataflow-kit・cl-boundary-kit への依存を外す

受け入れ条件: 全テストが通り、inventory/I1〜I9 の「削除候補」がすべて消えている。
