# Claude Code への最初の依頼文

このリポジトリのルートで Claude Code を起動し、下の文をそのまま貼ってください。
2 回目以降は「次は P0-3 をお願いします」のようにタスク ID で頼めば足ります。

---

nshell の v0.8 計画に沿って作業を始めてください。

1. まず AGENTS.md と docs/design/README.md を読み、続けて docs/design/00-overview.md と docs/design/proposal/05-roadmap-and-decisions.md を読んでください。
2. 今回のタスクは docs/design/tasks/P0-foundation.md の P0-1 と P0-2 です。
3. 着手前に計画 (変更するファイル、追加するテスト、確認のコマンド) を見せてください。私が OK したら実装してください。
4. タスクごとにブランチを切り (`p0/p0-1-agents-md`、`p0/p0-2-test-fast`)、Conventional Commits でコミットしてください。
5. 完了したら、該当タスクのチェックボックスを付け、全テストの結果と残った課題を報告してください。

守ること:
- 設計と実装が食い違ったら、黙ってどちらかに合わせず報告してください。設計が曖昧なら推測せずに質問してください。
- テストでは HOME・XDG_CONFIG_HOME・XDG_DATA_HOME・XDG_STATE_HOME・XDG_CACHE_HOME を一時ディレクトリにし、NSHELL_AI_COMMAND=/nonexistent を設定して、私の履歴や設定、AI プロバイダに触れないでください。
- 決定事項 (proposal/05 の表) と設計の文面が食い違って見えたら、実装に入る前に私に確認してください。

---

## 進め方の目安

| 回 | 依頼 |
|---|---|
| 1 | P0-1・P0-2 (上の文) |
| 2 | P0-3 以降の P0 のタスク |
| 3〜 | P1 を 1 タスクずつ。P1-7 (golden / spec テスト) まで終えてから P2 へ |
| 以降 | P2 → `packages/` の再編 → P3 と P4 を並行 → P5 → P6 |

大きなタスク (規模 大) は 1 回の依頼で 1 タスクに絞ると、確認しやすくなります。
