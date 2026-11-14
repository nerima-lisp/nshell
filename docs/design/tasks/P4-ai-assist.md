# P4 AI 支援

規模: 中。P3 と並行できる。`packages/` の再編 (proposal/04 の配置) は P2 の後に行い、P4 はその後に始める。新しいコードは `packages/feature/machine/` に置く。

## P4-1 --serve

- [ ] stdio の JSON Lines。cd・変数・ジョブなどの状態を保つ
- [ ] P1 のメソッドをすべて同じ実装で提供 (P1-6 のツールと同じ一覧を共有する)
- [ ] 要求そのものを処理できない失敗 (要求の形が不正、未知のメソッド、E_PROTOCOL など) は、トップレベルの `{"id":…,"error":{"code":"E_…"}}` で返す
- [ ] 実行したコマンドの失敗 (E_COMMAND_NOT_FOUND など) は、`result` の envelope (`ok:false`・`status`・`error.code`) で返す
- [ ] 要求は順に 1 つずつ処理する
- [ ] バックグラウンドジョブの出力は read_output で返し、プロトコルの標準出力には出さない

## P4-2 AI プロバイダ (proposal/09)

- [ ] sidecar をプロバイダのアダプタに分ける: claude-code (既定)・codex・ollama
- [ ] 3 つとも「ツールを使わせない」を起動時に確認する
  - claude-code: マニフェストを確かめる
  - codex: 起動引数を確かめ、空の一時 cwd で起動し、MCP を設定で無効にする。item の種類が `agent_message` か `reasoning` 以外 (`command_execution`・`file_change`・`mcp_tool_call`・`collab_tool_call`・`web_search`・`todo_list`) ならその回を打ち切る。`turn.failed` と `error` は失敗として扱う
  - ollama: `tools` を付けずに要求し、`tool_calls` を含む応答を拒否する。起動時に `/api/version` と `/api/tags` を確かめる
- [ ] codex で残るリスク (打ち切る前にファイルを読める) を、`ai set provider codex` で切り替えたときと docs に表示する
- [ ] Ollama には cl-ollama-kit v3 を使う (cl-http-kit 経由で動く)
- [ ] `ai set provider` / `NSHELL_AI_PROVIDER` / init.lisp の `(ai-provider …)`
- [ ] 送信先の表示、勝手に切り替えない
- [ ] 点検用の `provider-check` 関数を出す。P5-4 の doctor がこれを使う

受け入れ条件: 各アダプタに偽のプロバイダ (決まった JSON を返す実行ファイル・HTTP サーバ) を当てたテスト。実際のサービスにはつながない。偽の Ollama サーバを使う check には `__darwinAllowLocalNetworking = true;` を付ける。

## P4-3 入口

- [ ] 行頭 `?` と Ctrl-] の自然言語入力。AI への質問になるのは後ろに空白がある `? ` のときだけで、`?foo` は glob のまま
- [ ] 応答は P3-4 のパネルの部品へ流す
- [ ] ai why (Alt-W)・ai explain
- [ ] ai why の一次診断を規則で (proposal/06 C)。規則に当たらないときだけプロバイダへ

## P4-4 承認と共有セッション (ux/U7)

- [ ] 承認 ID は `ap_` と 16 進 16 桁。有効期限は 120 秒で、1 回だけ使える。セッション・入力のバイト列・cwd に結びつける
- [ ] 期限切れのときは、新しい ID つきで E_NEEDS_APPROVAL を返す。承認できる人がいないときは、ID なしで E_NEEDS_APPROVAL を返す
- [ ] `--serve --attach [PATH|ID]`: ユーザー専用ソケットで人の対話セッションにつながる。`--mcp` にも使える。AI のコマンドは `ai ❯` つきで流れる
- [ ] ソケットは `$XDG_RUNTIME_DIR/nshell/<session>.sock`、なければ `${TMPDIR:-/tmp}/nshell-$UID/` の下。ディレクトリは 0700 で先に作り、ソケットは 0600。接続元の uid を確かめ、macOS の sun_path の 104 バイト制限に収める
- [ ] 子プロセスには `NSHELL_SESSION_SOCKET` を渡す
- [ ] 履歴の origin に `:ai` を足し、`:proposal` と `:agent` は残す。`origin:ai` での検索は 3 つすべてに一致させる
- [ ] 履歴の読み込み側は、未知の origin を持つレコードを捨てず、origin を nil として読む

## P4-5 論理クエリ (proposal/06 F)

- [ ] S式の `(?- …)` と MCP / --serve の query
