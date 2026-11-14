# AI 機能

既存の AI 機能のすべて。安全の仕組みは残し、入口と接続先を整理します。

残す

12

簡素化

2

削除候補

1

追加

1

### 対話の入口

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| agent TASK — 提案ごとに Enter で承認、e 編集 / s スキップ / q 中止、既定 10 ステップ | [残す] | 表示を簡素化。編集後の再判定も維持。 |
| Ctrl-] ask モード | [簡素化] | 行頭の `? ` と統合 (I5 と同じ)。 |
| ai status / reset / log N | [残す] | そのまま。 |
| ai set effort / model / max-steps | [残す] | ai set provider を追加 (09)。 |
| ai set budget — 表示用の参考額 | [削除候補] | 上限だと誤解されやすい (I1 と同じ)。 |
| ai why / ai explain — なし | [追加] | 03 を参照。 |

### 接続先

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| claude CLI の sidecar — stream-json、ツールなし、MCP なしを起動時に確認 | [簡素化] | claude-code・codex・ollama の 3 アダプタに分ける。既定は claude-code。起動時の確認は維持し、プロバイダごとの検証を足す (09)。 |
| NSHELL_AI_COMMAND — 同じプロトコルの別実行ファイル | [残す] | 上級者向けに残す。通常は NSHELL_AI_PROVIDER (09)。 |

### 安全

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| 危険度の分類 — safe / confirm / block、静的解析 | [残す] | 規則で書き直し (06-A)、--serve・MCP・explain で共有。block は組み込み規則だけが出せる。 |
| redaction — 機密パス・コマンド・環境変数の値を伏せる | [残す] | そのまま。 |
| 送る文脈 — 直前コマンド・status・所要時間・cwd・git・出力末尾・環境変数名 | [残す] | そのまま。 |
| 監査ログ — ai log で表示 | [残す] | そのまま。 |
| transcript と snapshot の保存 — --private で抑止 | [残す] | MCP の read_state が使う (read_state は 1 リリースのあいだ非推奨として残す)。 |
| 使用量の表示 | [残す] | そのまま。 |

### 外部連携

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| --mcp list_sessions / read_state — snapshot と transcript の末尾 | [残す] | run / explain / complete / state / history / help などを追加 (02)。list_sessions と read_state は 1 リリースのあいだ非推奨として残す。 |
| {ai} プロンプトセグメント | [残す] | そのまま。 |
