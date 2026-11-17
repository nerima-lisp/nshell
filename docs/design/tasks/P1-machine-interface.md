# P1 機械インターフェースと安全

規模: 中。目的: AI が推測せずに使える入口と、同じ規則で動く安全判定。P2 以降の安全網 (golden test) もここで作る。

P1 の新しいコードは、`packages/` の再編 (P2 の後) を待たずに最初から `packages/feature/machine/` に、知識ベースは `packages/feature/kb/` に置く (P4 も同じ)。どのパッケージも `src/<layer>/` を持ち、層の静的チェックはパスの層名で判定する。

## P1-1 共通の応答の型

- [x] ux/U6 のフィールド (ok, status, value, stdout, stderr, error, effects, safety, state, duration_ms, session, seq) を表す構造体と JSON 変換
- [x] `nshell_api: 1` を版として持つ
- [x] 常に出すキーは `nshell_api ok status duration_ms stdout stderr effects safety state`。ほかは任意。P2-5 用の `warnings[]` と、explain 用の `forms` を持つ
- [x] JSON Schema はトップレベルを `additionalProperties: true` にし、`error.code` は enum で縛る
- [x] Schema の検証器は cl-json-kit に足したものを使う

受け入れ条件: 型の JSON Schema を `docs/design/conformance/envelope.schema.json` に置き、すべての応答がそれに通るテスト。

## P1-2 --json と --timeout

- [x] `nshell --json --command INPUT` が 1 つの応答を出して終了
- [x] `--timeout SEC` は実行全体の期限。超えたらプロセスグループごと停止 (既存の SIGTERM → SIGKILL を流用)、E_TIMEOUT
- [x] `--json` の既定の期限は 120 秒。既定値は initialize の応答で知らせる。通常のバッチは今のまま (外部コマンドごとに 3600 秒)
- [x] 出力の節約 (U6): ANSI 除去・\r の圧縮・先頭と末尾・全文の保存先 path。切り詰めの印は英語で固定
- [x] 全出力は、mkdtemp で作った 0700 のディレクトリ `$XDG_CACHE_HOME/nshell/out/<session>/` に 0600 で保存する。直近 50 セッション分だけ残し、`--private` では保存しない
- [x] `--json` は危険度を報告するだけにする。承認を求めるのは `NSHELL_AGENT=1`・MCP・`--serve` のときで、既存の origin 判定 (`src/application/execute-pipeline-control.lisp`) を通す
- [x] AI ゲートがいま返している終了コード 126 を、E_NEEDS_APPROVAL の 3 と E_BLOCKED_BY_POLICY の 4 に変える (P0-3 の表)。リリースノートに書く

受け入れ条件: proposal/02 と ux/U6 の例がそのまま golden test として通る。

## P1-3 非対話の既定環境

- [x] 機械向けモードと `NSHELL_AGENT=1` のときだけ、色・プロンプト・ページャ・autosuggest を無効化し、子プロセスに PAGER=cat などを渡す
- [ ] 端末からの入力待ちを検出して E_WAITING_FOR_INPUT (最後の出力を返す)。子を PTY と背景プロセスグループで動かし、SIGTTIN と WUNTRACED で検出する
- [x] 全画面プログラムを E_INTERACTIVE_PROGRAM で止め、代わりの書き方を fixes に。コマンド名の表と `ESC[?1049h` で検出する

## P1-4 explain・initialize・policy・read_output

- [x] explain: 実行せずに AST・各リストの分類・effects・safety。P1 では分類の `kind` だけを返し、`rule` (language/L2 の規則番号) は P2-2 まで null
- [x] CLI は予約語 `explain` を登録し、`nshell [--json] explain '…'` とする (language/L2 2.5)
- [x] initialize / policy / read_output (ux/U5・U6・U7)
- [x] read_output は不透明な id と offset で読む。出力の保存ディレクトリの外は拒否する

## P1-5 危険度判定と効果モデルを Prolog の規則に

- [x] `safety.lisp` の判定を proposal/06 A・B の規則に置き換える
- [x] コマンド名・すべての引数・リダイレクト・代入の前置きが許可仕様 (spec) に一致するときだけ safe。未知のコマンドや spec に一致しないものは confirm、ルート以外への `rm -r` は confirm
- [x] 変わる既存の期待値は、理由ごとに移行テストの表へ書く。proposal/02 と ux/U7 の例も直す
- [x] 規則は `findall` ですべて評価し、最も高いレベルを採る。同じレベルの規則はすべて safety.reasons に入れる (規則名と説明)
- [x] 規則名は `classify/<kebab>` とし、1 つのデータファイルにまとめる
- [x] block を出せるのは組み込み規則だけ。ユーザー規則は別の rulebase で評価し、結果を confirm までに抑える。P1-5 で作るのは仕組みとテスト用の注入だけで、rules.pl を読むのは P5-7
- [x] 安全判定の効力を持つのは、Enter のときの判定と、実行のゲートの判定。AI の提案を受け取ったときと explain のときにも判定するが、これは表示 (`[safe]` などの印) と、block の提案を入力欄に入れないことにだけ使う。入力中の表示は P3-7
- [x] 診断の規則 (P4-3) のうち diagnose/typo の 1 本だけを P1 で作り、proposal/02 の例を golden test として通す
- [x] 旧判定と新規則を同じ入力群で比べるテスト

受け入れ条件: 上で直したものを除き既存の safety テストが全部通り、explain の出力に規則名が出る。

## P1-6 MCP の拡張

- [x] --mcp に run / explain / complete / state / history / help / initialize / policy / read_output / query の 10 ツール。query は P4-5 まで E_NOT_IMPLEMENTED (isError) を返す
- [x] elicitation のためにプロトコルを 2025-06-18 へ上げる
- [x] `list_sessions` と `read_state` は 1 リリースのあいだ非推奨として残す
- [x] セッションは 1 サーバープロセスに 1 つ
- [x] safe のコマンドは承認なしで実行する。confirm 判定はクライアントの承認 (elicitation) があれば確認、なければ E_NEEDS_APPROVAL

## P1-7 golden test と言語の適合テスト

- [x] `t/golden/`: --json の出力をファイルで固定するランナー。1 ケース 1 ファイルの `t/golden/<id>.json` で、中身は `{input, env, files, expected}`、キーは整列する
- [x] golden の正規化: `duration_ms` → 0、`session` → `s_golden`、作業ルート・HOME・XDG → `$WORK` 系、`/private/tmp` → `/tmp`、外部ツールのパス → `<tool>`、pid、バージョン文字列。`error.message` は保存するが比較しない。期待値の更新は環境変数で行う
- fixture の `files` にある `bin/` から始まるパスは、実行権限を 0755 にして作る。実行器はホストの `PATH` を渡さず、`PATH` を `$WORK/bin` と `t/spec` と同じ固定 bin だけで作る。fixture の `env.PATH` があれば、その値の `$WORK` を実際の作業ディレクトリに展開し、その値をそのまま使う。
- git リポジトリが必要な例では、実際のリポジトリを作らず、fixture の `bin/git` に固定出力を返す小さなスクリプトを置く。作業ディレクトリ外の git 設定や、ホストに入っている git のバージョンによって結果が変わらないようにする。
- [x] `t/spec/`: `docs/design/conformance/language-probes-v0.7.0.json` の全ケースを取り込む。L7.1 の行に対応するケースは v0.8 の期待値を設計の行から書き、P2 で実装する分は担当の単位を付けた `it-fails` にする。担当がなくなった行は `it` になる。次のバージョンの期待値は `it-fails` で記述する。v0.8 で挙動が変わらないケースは JSON の v0.7.0 観測値を `it` で固定する
- [x] `t/spec` はスクリプトモードで実行する。PATH は固定の bin に絞り、テストを流す環境で記録し直す。v0.7.0 の JSON は出典として残す
- [x] L7 の行と probe の対応は `t/spec/l7-rows.lisp` に置く
- [x] golden test と spec は cl-weave のテストとして `NSHELL_BIN` を起動する。`checks.default` にバイナリを渡す
- [x] シナリオ JSON コーパスから残す 30〜40 本を選び、golden に移す候補を挙げる (削除は P2)。残すのは PTY 中心で、CI が ID を指定している P12・L02・T06・J05・Q03・Q07・Q08 を含める。一覧は [P1-7c-scenario-corpus.md](P1-7c-scenario-corpus.md)。30〜40 本を目安とし、基準に当たる 41 本を残す

受け入れ条件: P2 で言語を変えたとき、どの行が変わったかが golden / spec の差分で分かる。
