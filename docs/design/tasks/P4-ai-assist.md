# P4 AI 支援

規模: 中。P3 と並行できる。

## P4-1 --serve

- [ ] stdio の JSON Lines。cd・変数・ジョブなどの状態を保つ
- [ ] P1 のメソッドをすべて同じ実装で提供

## P4-2 AI プロバイダ (proposal/09)

- [ ] sidecar をプロバイダのアダプタに分ける: claude-code (既定)・codex・ollama
- [ ] 3 つとも「ツールを使わせない」を起動時に確認 (codex はコマンド実行イベントでその回を打ち切る)
- [ ] `ai set provider` / `NSHELL_AI_PROVIDER` / init.lisp の `(ai-provider …)`
- [ ] 送信先の表示、勝手に切り替えない、doctor での点検

受け入れ条件: 各アダプタに偽のプロバイダ (決まった JSON を返す実行ファイル・HTTP サーバ) を当てたテスト。実際のサービスにはつながない。

## P4-3 入口

- [ ] 行頭 `?` と Ctrl-] の自然言語入力
- [ ] ai why (Alt-W)・ai explain
- [ ] ai why の一次診断を規則で (proposal/06 C)。規則に当たらないときだけプロバイダへ

## P4-4 承認と共有セッション (ux/U7)

- [ ] 承認 ID (1 回 1 コマンド・期限つき・入力が変われば無効)
- [ ] `--serve --attach`: ユーザー専用ソケット (0600) で人の対話セッションにつながる。AI のコマンドは `ai ❯` つきで流れる
- [ ] 履歴の origin = ai

## P4-5 論理クエリ (proposal/06 F)

- [ ] S式の `(?- …)` と MCP / --serve の query
