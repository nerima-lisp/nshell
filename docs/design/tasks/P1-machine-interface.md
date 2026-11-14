# P1 機械インターフェースと安全

規模: 中。目的: AI が推測せずに使える入口と、同じ規則で動く安全判定。P2 以降の安全網 (golden test) もここで作る。

## P1-1 共通の応答の型

- [ ] ux/U6 のフィールド (ok, status, value, stdout, stderr, error, effects, safety, state, duration_ms, session, seq) を表す構造体と JSON 変換
- [ ] `nshell_api: 1` を版として持つ

受け入れ条件: 型の JSON Schema を `docs/design/conformance/envelope.schema.json` に置き、すべての応答がそれに通るテスト。

## P1-2 --json と --timeout

- [ ] `nshell --json --command INPUT` が 1 つの応答を出して終了
- [ ] `--timeout SEC`: 超えたらプロセスグループごと停止 (既存の SIGTERM → SIGKILL を流用)、E_TIMEOUT
- [ ] 出力の節約 (U6): ANSI 除去・\r の圧縮・先頭と末尾・全文の保存先 path

受け入れ条件: proposal/02 と ux/U6 の例がそのまま golden test として通る。

## P1-3 非対話の既定環境

- [ ] TTY でないか `NSHELL_AGENT=1` で、色・プロンプト・ページャ・autosuggest を無効化し、子プロセスに PAGER=cat などを渡す
- [ ] 端末からの入力待ちを検出して E_WAITING_FOR_INPUT (最後の出力を返す)
- [ ] 全画面プログラムを E_INTERACTIVE_PROGRAM で止め、代わりの書き方を fixes に

## P1-4 explain・initialize・policy・read_output

- [ ] explain: 実行せずに AST・各リストの分類 (language/L2 の規則番号)・effects・safety
- [ ] initialize / policy / read_output (ux/U5・U6・U7)

## P1-5 危険度判定と効果モデルを Prolog の規則に

- [ ] `safety.lisp` の判定を proposal/06 A・B の規則に置き換える。既存の分類テストはすべてそのまま通す
- [ ] 理由 (規則名と説明) を safety.reasons に出す
- [ ] block を出せるのは組み込み規則だけ

受け入れ条件: 既存の safety テストが全部通り、explain の出力に規則名が出る。

## P1-6 MCP の拡張

- [ ] --mcp に run / explain / complete / state / history / help / initialize / policy / read_output / query の 10 ツール (query は P4 まで未実装を返してよい)
- [ ] confirm 判定はクライアントの承認 (elicitation) があれば確認、なければ E_NEEDS_APPROVAL

## P1-7 golden test と言語の適合テスト

- [ ] `t/golden/`: --json の出力をファイルで固定するランナー
- [ ] `t/spec/`: `docs/design/conformance/language-probes-v0.7.0.json` の全ケースを取り込み、現在の挙動を固定する。language/L7 の差分表の行は「期待値は L7 の右列」として pending にしておく
- [ ] シナリオ JSON コーパスから、残す 30〜40 本を golden に移す候補を選ぶ (削除は P2)

受け入れ条件: P2 で言語を変えたとき、どの行が変わったかが golden / spec の差分で分かる。
