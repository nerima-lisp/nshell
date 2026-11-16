# 起動・CLI・設定・環境変数

nshell の起動方法と、ユーザーが設定できるものすべて。

残す

19

簡素化

3

削除

1

削除候補

4

追加

4

### 起動モード

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| 対話起動 — TTY を自動判定 | [残す] | そのまま。 |
| -i / --interactive — ラインエディタを強制 | [残す] | そのまま。 |
| -c COMMAND — /bin/sh に委譲 (Lisp 起動前) | [残す] | エディタ等が $SHELL -c を前提にするため維持 (05 の決定事項)。 |
| --command COMMAND ARGS — nshell で 1 回評価、ARGS は $argv | [残す] | --json / --timeout と組み合わせる機械向けの基本形にする。 |
| スクリプト実行 — nshell FILE ARGS | [残す] | そのまま。 |
| stdin からのバッチ — 非 TTY 入力を順に評価 | [残す] | そのまま。非対話時の決定的出力ルールは機械向けモードと NSHELL_AGENT=1 のときだけ適用する (proposal/02)。 |
| -e / --errexit — 失敗で終了 | [残す] | そのまま。 |
| -l / --login と -ilc — /etc/profile・nix-darwin・Home Manager を読む | [残す] | VS Code などの環境解決に必要。 |
| -h / -V — help / version | [残す] | help は spec から生成。 |
| --mcp — stdio MCP サーバ (list_sessions と read_state のみ) | [残す] | ツールを 10 個に拡張 (02・U5)。プロトコルは 2025-06-18 に上げ、list_sessions と read_state は 1 リリースのあいだ非推奨として残す。 |
| --json / --serve / --timeout — なし | [追加] | 機械向けの入口。02 を参照。 |

### 設定ファイル

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| init.lisp — $XDG_CONFIG_HOME/nshell/init.lisp、--config / --no-config | [残す] | そのまま。構文エラーでもプロンプトまで進む挙動も維持。 |
| ~/.nshellrc の無視通知 — 1 行の notice | [削除候補] | v0.8 で通知ごと削除。 |
| シェルフック — :PREEXEC :POSTEXEC :PROMPT :CD :COMMAND-NOT-FOUND | [簡素化] | 5 種は維持。登録は nshell.application:register-shell-hook ではなく nshell.user の add-hook で書けるようにする。 |
| 関数の自動読み込み — functions/NAME.nsh | [残す] | そのまま。 |
| rules.pl — なし | [追加] | ユーザー規則 (診断・提案・追加の confirm) を Prolog で書く (06)。 |
| グリーティング — NSHELL_GREETING (空で無効) | [簡素化] | init.lisp の設定へ移し、既定は無表示に。 |

### 環境変数 (18 個)

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| NSHELL_PROMPT / NSHELL_RIGHT_PROMPT — プロンプト書式 | [残す] | そのまま。 |
| NSHELL_EDITOR — Alt-E の編集コマンド | [残す] | 未設定なら $VISUAL → $EDITOR。 |
| NSHELL_HISTORY_PRIVATE — --private 相当 | [残す] | そのまま。 |
| NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH — auto / narrow / wide | [残す] | 日本語環境に必須。 |
| NSHELL_VI_MODE — vi モード | [残す] | そのまま。初期モードの設定も追加 (07)。 |
| NSHELL_MOUSE_REPORTING — SGR マウス報告 | [削除] | F4 で設定と SGR マウス入力報告の有効化経路を削除する。ESC の後に `[` が遅れて届くと、SGR マウス入力シーケンスの残りが入力欄に文字として入るため。 |
| NSHELL_COMPLETION_HELP_ALLOWLIST — --help 解析の許可リスト | [簡素化] | 補完の作り直しで init.lisp 設定に統合。 |
| NSHELL_GIT_STATUS_DIAGNOSTICS — git 状態のデバッグ出力 | [削除候補] | 開発用。ログ出力レベル 1 つに統合。 |
| NSHELL_NFR06_CANDIDATE_COMPUTE_SIDECAR — 計測用 | [削除候補] | NFR 計測の削除に合わせて削除。 |
| NSHELL_PTY_BOOTSTRAP — Darwin の PTY 起動 (内部) | [残す] | 内部用。ドキュメントで内部と明記。 |
| NSHELL_AI_COMMAND / _DISABLE / _EFFORT / _MODEL / _MAX_STEPS — AI 設定 | [残す] | そのまま。COMMAND は上級者向けに残す (09)。 |
| NSHELL_AI_BUDGET_USD — 表示用の参考額 (制限しない) | [削除候補] | 上限だと誤解されやすい。実際に止める上限にするか削除 (削除を推奨)。 |
| NSHELL_AGENT — なし | [追加] | 非対話の決定的出力を明示的に有効化。 |
| NSHELL_AI_PROVIDER — なし | [追加] | claude-code (既定) / codex / ollama (09)。 |
