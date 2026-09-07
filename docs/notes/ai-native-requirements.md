# nshell AI-native 化 要件定義書

> 出典: 2026-09-07 の `/define` セッション（読み取り専用）で策定・確定した要件書。
> この文書は決定事項であり、実装時に再検討しない。再オープンは保守者本人の指示があるときのみ。

## 1. 要約

**要求**: nshell を、単一ユーザ (保守者本人) のための AI native な interactive shell にするための機能/非機能要件を策定し、ユーザ体験を先に詰める。

**Why**: 現在の nshell は「編集器・補完・履歴・ジョブ制御が堅い fish 風 shell」で、AI に関する記述はツリーに一切ない。日常 shell の中で最も時間を失う 3 場面 (コマンドの言い方を思い出す、失敗の原因を読む、複数ステップの雑務を手で回す) にモデルを置き、かつ shell を外部エージェント (Claude Code) にとっての一級の作業面にする。

**期待する結果**: (1) 自然言語を打つと編集バッファにコマンドが載る、(2) 失敗直後に原因と次の一手が出る、(3) タスクを委譲すると shell 内でステップごとに承認しながら進む、(4) 外部エージェントが shell の状態を構造化データで読める。いずれも「キー入力なしに何も実行されない」「モデルが落ちても shell は完全に shell である」を不変条件とする。

## 2. UX の追究

### 2.1 設計原則

| 原則 | 意味 | 根拠 |
|---|---|---|
| 提案は常に編集バッファへ | AI の出力は「入力の続き」であって「実行」ではない。Enter が唯一の実行手段 | 信頼モデルの決定。既存の編集器・ハイライト・補完・undo がそのまま効く |
| 沈黙が既定 | 明示トリガーがない限りモデルは呼ばれない。失敗時も「1 キーで聞ける」だけ | one-shot 3.8s、常駐でも 1.3–1.5s/turn という計測値では、打鍵ごとの ambient 提案は成立しない。**[実測による訂正 2026-09-07]** この 1.3–1.5s/turn は出力を極小（約 91–209 token）にしたプロンプトでのみ成立する値。実運用相当（数 step の shell 設計を要求する 200–600 字プロンプト、出力 3,272–7,726 token）では 30–66s/turn に達し、遅延は出力トークン数にほぼ比例する（NFR-3 参照）。ambient 提案が成立しないという結論は変わらないが、根拠の桁が異なる |
| 消える描画、残る実行 | 説明や進行はプロンプト下の一時パネル。scrollback に残るのは採用した提案と実行したステップだけ | 履歴画面を汚さない。補完メニューと同じ領域を再利用 |
| モデルは事実を見て、秘密は見ない | cwd / git / 直前出力 / exit / 所要時間は送る。環境変数の値と token 形状の文字列は送らない | redaction が現状ゼロなので、要件として明示しないと漏れる |
| 非対応時はただの nshell | `claude` が無い / 未ログイン / rate limit / 落ちた、いずれでも編集・補完・ジョブ制御は無傷 | 単一ユーザでも Nix サンドボックスや別マシンで起きる |

### 2.2 シナリオ A: 自然言語 → コマンド提案

ask モードへは 1 つのコード (chord) で入る。プロンプトが変わるので、今どのモードかは常に見える。

```
~/src/nshell (main) >                                   # 通常
~/src/nshell (main) ask> 直近1週間に触った lisp ファイルを更新順に
                        ┌ thinking… 0.8s ─────────────────────── ⌃C cancel ┐
                        └───────────────────────────────────────────────────┘
```

応答はストリーミングでパネルに流れ、確定すると提案行が **編集バッファに載り、モードが通常に戻る**。パネルには理由と分類だけが残る。

**[実測による訂正 2026-09-07]** 上のモックの「thinking… 0.8s」は実測と矛盾する。0.8s 級が成立するのは出力を極小（約 91–209 token）にした場合のみで、実運用相当プロンプトでは 1 turn の遅延は数秒〜数十秒に及ぶ（最小計測でも duration_ms 中央値 1,600–3,000、実運用相当では p50 30,944）。モックそのものは書き換えず、矛盾であることをここに明示する。正確な実測値は NFR-3 を参照。

```
~/src/nshell (main) > find . -name '*.lisp' -mtime -7 -print0 | xargs -0 ls -t
                      ┌ safe · find + xargs、書き込みなし ─────────────────────┐
                      │ 提案を編集して Enter。⌃G で破棄、M-e で外部エディタ     │
                      └────────────────────────────────────────────────────────┘
```

- 提案は 1 回の undo で取り消せる (バッファ置換は通常の編集として undo スタックに積む)。
- 複数行提案 (`&&` 連鎖やパイプライン) は既存の複数行バッファにそのまま載る (`insert-newline-at-cursor` が `src/presentation/input-state-buffer-ops.lisp` 111 行にある)。
- 分類が `confirm` の提案 (例: `rm -rf`, `git push --force`, `dd`) はバッファに載るが、Enter で実行する前に 1 度だけ確認行が出る。`block` は載らず、理由だけ示す。

**command not found フォールバック**: 通常モードで自然言語を打ってしまったとき。

```
~/src/nshell (main) > 直近で変えたファイルを見せて
nshell: 直近で変えたファイルを見せて: command not found   (⌃A で AI に聞く)
```

`⌃A` 相当の 1 キーでその行をそのまま ask に送る。他のキーでメッセージは消える。

### 2.3 シナリオ B: 失敗の説明と次の一手

非 0 で終わったコマンドの直後、プロンプトに小さな印が出る。何も起きない。

```
~/src/nshell (main) > nix build .#releaseBundle
error: builder for '/nix/store/…-nshell-bundle.drv' failed with exit code 1;
       last 10 log lines: …
~/src/nshell (main) [1 · ?] >
```

`?` の印に対応するキーを押したときだけ、直前のコマンド、exit、所要時間、リングバッファの出力 (redaction 済み) を送って説明を求める。

```
~/src/nshell (main) [1 · ?] >
  ┌ explain ────────────────────────────────────────────────────────────────┐
  │ patchelf が store path への書き込みを拒否している。bundle 派生の         │
  │ fixup フェーズで permission denied。既知の main の赤 (CI と同じ)。       │
  │                                                                          │
  │ 次の一手:                                                                │
  │   1. nix build .#releaseBundle --rebuild --print-build-logs   [Tab で載せる] │
  │   2. perl scripts/verify-release-bundle.pl result                        │
  └──────────────────────────────────────────────────────────────────────────┘
```

Tab で候補を編集バッファへ。それ以外のキーでパネルは消える。プロンプトの印は次のコマンドで消える。

### 2.4 シナリオ C: エージェントモード

`agent` はコマンドとして起動する。各ステップは「提案 → 承認キー → PTY 下で実行 → 出力をモデルに返す」の 1 サイクルで、承認なしに次へ進まない。

```
~/src/nshell (main) > agent "test-builtins-core の describe 名衝突を直して"
  ┌ agent · step 1/? ───────────────────────────────────────────────────────┐
  │ まず衝突箇所を確認します                                                 │
  │ > grep -n '(describe "builtin-tests"' t/unit/*.lisp                      │
  │   safe                              [Enter 実行 · e 編集 · s 飛ばす · q 中止] │
  └──────────────────────────────────────────────────────────────────────────┘
```

Enter で実行。実行したコマンドと出力は scrollback に確定し、パネルは次のステップに移る。

- `confirm` ステップは Enter を 2 度要求しない。分類表示と承認キーで足りる (承認自体がキー入力)。`block` ステップは実行キーが無効で、`e` で編集するか `s` で飛ばす。
- モデルは shell の外でコマンドを実行できない (`--tools ""` で sidecar のツールを無効化し、実行は常に nshell 側)。**[実測による訂正 2026-09-07]** `--tools ""` だけではこの信頼モデルは成立しない。MCP サーバが個人設定から接続され、モデルは shell の外でツールを実行できる状態になる。`--strict-mcp-config` の追加と起動時検証（`mcp_servers` 空・`tools` 許可リスト）が必須。詳細は FR-009 を参照。
- `q` またはループ外の `⌃C` で中止。中止時点までに実行したものは scrollback に残っているので、何が起きたかは常に読める。
- agent はジョブではない。`jobs` に出ず、`⌃Z` で止まらない。止めるのは `q`。

### 2.5 シナリオ D: 外部エージェントの基盤

Claude Code を隣で動かしているとき、nshell が「何をして、何が出て、今どこにいるか」を読める。

- **transcript**: セッションごとに追記専用の JSONL。1 行 = 1 コマンド (時刻、cwd、コマンド、exit、所要時間、出力の先頭 N 行、redaction 済み)。
- **snapshot**: 各プロンプト描画時に更新される 1 ファイル (cwd、git 状態、ジョブ一覧、直前の exit、環境変数名)。
- **MCP**: `nshell --mcp` という別プロセスが stdio で上記 2 ファイルを配信する。生きている shell への IPC は要らない。Claude Code 側は `--mcp-config` で登録する。
- **history v3**: 通常の履歴も時刻・cwd・exit・所要時間を持つ。`history` の出力と検索がそれを使える。

### 2.6 失敗モードの体験

| 状況 | ユーザが見るもの | shell の状態 |
|---|---|---|
| `claude` が PATH にない | ask に入ると「AI 未接続: claude が見つからない」を 1 行。キーは無効化されず通常モードに戻る | 完全に通常 |
| 未ログイン | 同上 + `claude /login` の案内 | 同上 |
| 応答が遅い | パネルに経過秒と `⌃C cancel`。5 秒以降は「まだ待つ / 諦める」を表示 | 打鍵は受け付ける (ポーリングは 1ms) |
| rate limit | パネルに「rate limit: 再開 hh:mm」。自動リトライしない | 通常 |
| sidecar が死んだ | 次の ask で再 spawn。ステータス行に「再接続」 | 会話文脈は失われる (明示) |
| 提案が間違い | 編集して実行するか ⌃G。誤りは履歴に残らない (実行しなければ記録しない) | 通常 |
| プロンプト下の行が足りない | パネルは端末行数 − プロンプト行数 − 1 を上限に切り詰め、パネル内でスクロール。`v` で scrollback に展開 | 通常 |

### 2.7 モードと遷移

| 状態 | 入口 | 出口 | プロンプト |
|---|---|---|---|
| normal | 起動 | chord, command not found + 1 キー, `agent` | 従来 |
| ask | chord / フォールバック | Enter (送信), ⌃G (破棄) | `ask>` サフィックス |
| ask-waiting | ask で Enter | 応答確定, ⌃C | パネルに経過 |
| proposal | 応答確定 | Enter (実行), ⌃G, 編集開始 (通常編集へ) | 通常 + 分類パネル |
| explain | 失敗後の 1 キー | 任意キー | 通常 + 説明パネル |
| agent-step | `agent` | Enter / e / s / q | 通常 + step パネル |

ask 中は履歴 autosuggestion、abbr 展開、`!!` 系の history expansion をすべて無効にする。ask バッファは自然言語であって shell 行ではない。vi モードでは chord は insert / normal 両方で同じキーに割り当て、ESC 前置 (Alt) は使わない (ESC が normal 入場と衝突する)。

## 3. 現状 (2026-09-07 時点の調査結果、file:line は当時のもの)

| 項目 | 事実 | 根拠 |
|---|---|---|
| AI 関連コード | 存在しない | `src` `docs` `packages` `man` の LLM / MCP / assistant grep で 0 件 |
| ネットワーク・JSON 依存 | なし | `nshell.asd` の `:depends-on` と `src` の grep で 0 件 |
| モデル到達手段 | org 内に TLS なし。`claude` 2.1.263 と `codex` はローカルにあり、Ollama はない | cl-http-kit README の boundary 節、`command -v` |
| 単純コマンドの出力 | 実端末を継承、保持なし | `src/infrastructure/acl/syscall-process.lisp` 6–10 行 |
| パイプライン・リダイレクト付きの出力 | 文字列バッファに溜めて終了後に書く | `src/application/execute-pipeline-stage-external.lisp` 129–148 行、`…-external-output.lisp` 11–27 行 |
| exit / 所要時間 | メモリ上にあり prompt が使う。永続化なし | `src/presentation/repl-output-handlers.lisp` 75–96 行、`src/domain/prompting/prompt.lisp` 99–106 行 |
| 履歴形式 | v2、コマンド文字列のみ。複数行対応 | `src/infrastructure/persistence/file-history.lisp` 5, 32–63 行 |
| 設定 | `~/.nshellrc` は実行される script。設定キーの概念なし | `src/infrastructure/persistence/file-config.lisp` 6–25 行、`src/presentation/repl-session-init.lisp` 12–32 行 |
| 秘匿処理 | なし | `redact\|secret\|API_KEY` grep で 0 件 |
| 非同期注入 | SIGINT / SIGWINCH / SIGCHLD の 3 前例、いずれもフラグ + 1ms ポーリング | `src/presentation/repl.lisp` 31–50 行、`src/infrastructure/terminal/input-read.lisp` 144–159 行、`src/infrastructure/acl/signal-acl.lisp` |
| 入力モード | 6 種、`case` 1 箇所で分岐 | `data/presentation/input-state-data.lisp` 12–16 行、`src/presentation/input-state-session.lisp` 47–54 行 |
| プロンプト下領域 | 補完メニューが cursor save/move/restore で描画 | `src/presentation/repl-output-completion.lisp` 7–38 行 |
| PTY ACL | 存在するがテストが nshell 自身を駆動する用途のみ | `src/infrastructure/acl/pty*.lisp`、呼び出し元は `t/` のみ |
| 並行性 | cl-concurrent-kit 依存済み。promise / channel / executor あり | `nshell.asd` 35 行、cl-concurrent-kit README |
| 縦スライス | `packages/feature/command-line` が唯一の前例。feature-registry はトポロジ記述のみで実行時ゲートではない | `packages/core/kernel/src/domain/feature-registry.lisp` |
| 非対話経路 | `-c` と script は `run-repl` と別経路 | `src/main.lisp` 129–138, 165–166 行 |

## 4. 機能要件

タグ: **verified** = 調査で確認、**inferred** = 確認事実からの帰結、**assumed** = ユーザの枠組みのみ。

**FR-001 ask モード** · 必須 (体験の中核) · verified
- chord で `:ask` モードに入り、プロンプトにサフィックスが付く。同じ chord は insert / vi-normal の両方で有効で、既存バインド (`C-a/e/k/u/w/y/_/r/f`, `M-f/b/e`, vi の文字キー) と衝突しない。
- Enter で送信、`⌃G` で破棄して通常へ。
- ask 中は autosuggestion、abbr、history expansion が無効。
- モデルが無効・未接続のとき、1 行の理由を表示して通常に戻る。

**FR-002 コマンド提案の受け取り** · 必須 · verified
- 応答確定時に提案が編集バッファを置換し、通常モードに戻る。置換は 1 回の undo で戻る。
- 提案は AST に変換され分類される。`safe` はそのまま、`confirm` は Enter 時に 1 度の確認、`block` はバッファに載らず理由のみ。
- パース不能な提案はバッファに載らず、「解釈できない提案」として本文をパネルに出す。

**FR-003 command not found フォールバック** · 必須 · verified (単一のトリガ地点: `src/infrastructure/acl/syscall-process-resolution.lisp` 6–35 行)
- exit 127 の直後に 1 キーでその行を ask に送る。他のキーで案内は消え、その行は履歴に残らない。

**FR-004 失敗の説明** · 必須 · verified (exit と所要時間は取得済み) / 出力本文は PTY スパイクの結果に依存 (FR-010)
- 非 0 終了後、プロンプトに印が出る。1 キーで説明を要求。
- 送る文脈: コマンド、exit、所要時間、cwd、git 状態、直前出力 (末尾から上限バイト、redaction 済み)。
- 応答には「次の一手」を最大 3 件、Tab で編集バッファに載せられる。

実装で確定した範囲として、説明要求は既存の実行経路が返した出力本文だけを `last-output` に含め、redaction 後に送る。単純な外部コマンドの端末継承経路など本文を保持していない場合は `last-output` を `nil` のまま送り、exit、所要時間、コマンド、cwd、git 状態、環境変数名で説明を求める。

**FR-005 エージェントモード** · 必須 · inferred
- `agent "<task>"` で開始。各ステップは提案 → 承認 → 実行 → 出力返送。承認キーなしに実行しない。
- キー: Enter 実行、`e` 編集してから実行、`s` 飛ばす、`q` 中止。`block` ステップは Enter 無効。
- 実行したコマンドと出力は scrollback に確定し、history v3 に `agent` 由来の印付きで記録する。
- 途中で対話コマンド (エディタ、SSH) が提案されたら PTY 下で普通に動く (FR-010)。
- 最大ステップ数は設定可能。到達時は停止して理由を出す。

**FR-006 一時パネル** · 必須 · verified (補完メニューの描画経路)
- プロンプト下に描画、ストリーミング更新、次の無関係なキーで消える。
- 高さ上限 = 端末行数 − プロンプト行数 − 1。超過分はパネル内スクロール。`v` で scrollback に展開。
- 端末リサイズ時に再描画 (SIGWINCH 経路を再利用)。

**FR-007 キャンセル** · 必須 · verified (SIGINT ポーリング経路)
- モデル応答待ち中の `⌃C` はその turn を中止し、sidecar は殺さない。2 秒以内の 2 度目で sidecar を kill して再 spawn。
- agent のステップ実行中の `⌃C` は既存のフォアグラウンド経路と同じく子に届く。ステップは「中断」として記録され、次ステップの提案に進むか `q` を待つ。

**FR-008 文脈と redaction** · 必須 · verified (redaction 不在)
- 環境変数は名前のみ送る。値は送らない。
- コマンド・出力中の token 形状 (`[A-Za-z0-9_-]{20,}` 系の既知プレフィックス: `sk-`, `ghp_`, `AKIA`, `xox`, `Bearer `, PEM ヘッダ) は伏せ字化。
- denylist (path glob とコマンド名) に合致する行は文脈から除外。
- 送信した全ペイロードは監査ログ (JSONL) に残り、`ai log` で読める。

**FR-009 sidecar 管理** · 必須 · verified (stream-json 多 turn を実測)
- 起動は最初のプロンプト描画後、バックグラウンド。shell 起動時間に影響しない。
- 自プロセスグループ。`*foreground-pgid*` に入れず、`*proc-registry*` に登録しない (`jobs` に出ず `⌃Z` で止まらない)。
- `exec` と `exit` で kill。死亡検知時は次の要求で再 spawn。
- 起動時に `claude --version` を記録し、stream-json の期待形式と不一致なら AI 無効化の理由に含める。
- `--tools ""`、`--no-session-persistence`、`--append-system-prompt` で nshell 用システムプロンプトを付与。

**[実測による訂正 2026-09-07]** 起動フラグは上記だけでは不十分。`--tools ""` 単独では `system/init` 行に `tools` 61–84 件・`mcp_servers` 9 件（context7、deepwiki、playwright、claude.ai Gmail、claude.ai Google Calendar 他）が接続されたままになり、2.4 節の信頼モデル「モデルは shell の外でコマンドを実行できない」が成立しない。実測は次のとおり。

| 起動フラグ | `tools` | `mcp_servers` |
|---|---:|---|
| `--tools ''` のみ | 61〜84 件 | 9 件接続（context7, deepwiki, playwright, claude.ai Gmail, claude.ai Google Calendar 他） |
| `+ --strict-mcp-config` | 0 | `[]` |
| `+ --safe-mode` | 0 | `[]` |
| `+ --permission-prompts none` | 61 | 9 件接続 |

実装済みの対処（コミット `9569092`, `d6d5a24`, `3d70597`）:

1. 起動フラグに `--strict-mcp-config` を必須で追加。実測で `tools` と `mcp_servers` をともに空にする最小のフラグは `--strict-mcp-config` であり、採用した。`--safe-mode` でも空になるが、分離以外のカスタマイズも無効にする広い指定のため最小集合としては不採用。
2. `system/init` 行の `tools` と `mcp_servers` を sidecar 起動時に検証し、`mcp_servers` は空を要求、`tools` は `{"StructuredOutput"}` の部分集合のみ許可する明示的な許可リスト。`--json-schema` を使うと `tools` に `StructuredOutput` が入るため、空限定にすると sidecar 自身が拒否される。どちらか一方でも空でなければ AI を有効化しない。
3. 起動フラグに `--effort`（既定 `low`、設定で上書き可）と `--model`（設定時のみ）を追加（コミット `3d70597`）。

**FR-010 PTY 下の出力捕捉** · 必須 (スパイクゲート付き) · verified
- すべてのフォアグラウンド外部コマンドを shell 所有の PTY で実行し、出力を有界リングバッファに tee する。子は TTY を見続ける。
- ウィンドウサイズを子に伝播し、`⌃C` / `⌃Z` / `fg` / `bg` / 対話エディタ / SSH が現行どおり動く。
- **ゲート**: 既存の job-control / PTY テスト (`t/e2e/test-job-control.lisp`, `t/integration/test-job-control.lisp`, `t/integration/test-pty*.lisp`) が再アサートなしで緑、かつ手動で vim / ssh / `sleep 100` + `⌃Z` + `fg` を確認。
- **フォールバック** (ゲート不通過時): 単純コマンドは exit のみ、パイプライン・リダイレクト付きは既存バッファを保持して文脈に使う。FR-004 の出力本文はその範囲に縮む。

**FR-011 history v3** · 必須 · verified
- 各エントリに時刻、cwd、exit、所要時間、由来 (typed / proposal / agent) を持つ。
- v2 ファイルは読み込み時に v3 に昇格し、欠損フィールドは nil。
- `history` と `⌃R` は新フィールドで絞り込める (例: 失敗したものだけ)。

**FR-012 状態エクスポート** · 必須 · inferred
- セッション transcript (JSONL、追記専用) と snapshot (プロンプトごとに上書き) を `$XDG_STATE_HOME/nshell/` に書く。どちらも FR-008 の redaction 後。
- `nshell --mcp` が stdio MCP サーバとして 2 ファイルを配信する。生きている shell とは通信しない。

**FR-013 使用量表示** · 任意 · verified (`--max-budget-usd`、`rate_limit_event`)
- パネルとプロンプトセグメントにセッションの turn 数とトークン数。上限は設定で有効化、既定なし。rate limit は表示のみで自動リトライしない。

**FR-014 非対話経路は AI 無縁** · 必須 · verified
- `-c` と script 実行では sidecar を spawn せず、ask / explain / agent は使えない。`agent` は非対話で呼ばれたら exit 2。

**FR-015 会話の寿命** · 必須 · verified
- shell セッション内で 1 会話。`ai reset` で新規。セッション終了で消える。

## 5. 非機能要件

| ID | 条件 | 検証方法 |
|---|---|---|
| NFR-1 起動 | 最初のプロンプト描画までの時間が AI 導入前と統計的に区別できない | `t/perf/test-startup.lisp` の既存ケースに AI 有効時の同条件ケースを追加 |
| NFR-2 打鍵応答 | モデル待ち中もキー入力の反映が 1 フレーム遅れない | `read-key-event` の 1ms ポーリングに sidecar 読み取りを混ぜない (専用スレッド + セル) ことをテストで固定 |
| NFR-3 turn レイテンシ | ask / explain の p50 を計測して文書化する。目標値は計測後に決める (2026-09-07 の実測: 常駐 turn 1.3–1.5s、one-shot 3.8s、haiku) | 記録フィクスチャでは計れない。手動計測 |
| NFR-4 キャンセル | `⌃C` から 100ms 以内にパネルが「中止」を示す | e2e (PTY で nshell を駆動) |
| NFR-5 リングバッファ | 上限バイト数を設定で持ち、長時間出力で増えないことをアサート。既定値は PTY スパイクで決める | integration |
| NFR-6 オフライン | `claude` 不在で全非 AI 機能が同一に振る舞う | transport boundary を「不在」に差し替えた e2e |
| NFR-7 決定性 | すべての AI テストは記録済み stream-json フィクスチャで走り、ネットワークを触らない | boundary 注入 (cl-boundary-kit の既存パターン) |
| NFR-8 Nix | `claude` を Nix input にしない。ビルドと `nix flake check` は `claude` 不在で緑 | CI (x86_64-linux) |
| NFR-9 監査可能性 | 送信ペイロードは 100% 監査ログに残り、ログにも redaction が適用されている | unit (redaction) + integration (ログ) |
| NFR-10 プライバシー | 環境変数の値、denylist 該当行、token 形状が送信ペイロードに現れない | unit で否定アサート |

**[実測による訂正 2026-09-07: NFR-3]** 上の「常駐 turn 1.3–1.5s」は極小プロンプト（`--effort low`、出力 91–209 token）でのみ成立する値であり、実運用の複雑さのプロンプトでは達成できない。実運用相当プロンプト（`--effort low`、`--json-schema` あり、7 turn）は duration_ms p50 = **30,944**。縛りなしの実運用相当は 37,700 に達する。

| 条件 | 出力トークン | duration_ms p50 |
|---|---:|---:|
| 極小プロンプト（`--effort low`） | 91〜209 | 1,600〜3,000 |
| 実運用相当プロンプト（`--effort low`、`--json-schema` あり、7 turn） | 中央値 3,512 | **30,944** |
| 実運用相当プロンプト（縛りなし） | 3,272〜7,726 | 37,700 |

- ターン遅延は出力トークン数にほぼ線形。Pearson r = 0.9956 (haiku) / 0.9978 (sonnet)。概算で固定約 1 秒 + 約 9ms × 出力トークン（比例項が支配的）。
- `--json-schema` で最終出力を 3 フィールドの JSON に縛っても、そこに至る thinking トークンが支配的で、遅延は縮まない。
- `--effort` の有無による差はこの run では未測定（比較した 2 測定は条件が揃っておらず、差はプロンプト長に由来する）。
- ask モードの現実的な期待値は数秒〜数十秒。

## 6. 技術仕様

### 6.1 決定と根拠

| 決定 | 採用 | 却下した代替 | 影響範囲 |
|---|---|---|---|
| モデル境界 | `claude -p` 常駐 stream-json sidecar | in-image Anthropic API (TLS が org 外、Nix input 追加)、Ollama (未導入、後続の第 2 境界として温存)、両方同時 | infrastructure 新規、依存追加なし |
| 境界の差し替え | cl-boundary-kit 流の注入境界。本番は sidecar、テストは記録フィクスチャ | 直接 `run-program` | すべての AI テストがこれに依存 |
| 安全分類 | shell 内の静的 AST 規則。モデルの risk は表示のみ | モデルに分類させる | domain 新規 + dispatch 1 箇所 (`src/application/execute-pipeline-control.lisp` 234–235 行) |
| 非同期注入 | 4 つ目のポーリングフラグ (concurrent-kit のセル、世代 ID で stale 破棄) | reducer に外から値を push | `src/presentation/repl.lisp` の `read-key-cont` |
| 描画 | 補完メニュー領域を再利用 | scrollback 常時印字、tmux ペイン | presentation |
| 出力捕捉 | shell 所有 PTY + リングバッファ、スパイクゲート付き | 要求時再実行、捕捉なし | infrastructure の raw-mode 契約が変わる。`docs/src/reference/architecture.md` の raw-mode 節と `src/infrastructure/terminal/raw-mode.lisp` の注釈を同じ変更で更新 |
| 配置 | `packages/feature/assistant/src/<DDD>` を基本イメージに常時コンパイル。任意性は実行時 | 別 defsystem で除外可能にする | `nshell.asd` に module 追加 |
| 構文 | AST 契約で中立 | S 式再設計を前提 | 再設計が来たらリーダのみ差し替え |
| MCP | 別プロセスがファイルを配信 | 生きている shell に Unix socket | `src/main.lisp` に `--mcp` 経路 |
| 履歴 | v3 レコード、読み込み時昇格 | 別ファイルに補助情報 | `file-history.lisp` |

### 6.2 レイヤ配置

- **domain**: 文脈組み立て、redaction、応答パース (テキスト → AST)、安全分類、history v3 レコード、パネル内容の値表現。すべて I/O なし。
- **application**: ask / explain / agent-step / export のユースケース。分類器を dispatch 前に呼ぶ。turn 世代 ID を発行。
- **infrastructure**: sidecar 境界 (spawn、stream-json 読み書き、死活)、PTY ランナーとリングバッファ、監査ログと transcript の永続化、pending セル。
- **presentation**: `:ask` モード、パネル描画、`read-key-cont` の 4 番目の分岐、プロンプトの印とセグメント。

## 7. アーキテクチャ影響

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 900 460" font-family="system-ui, sans-serif" font-size="13">
  <defs>
    <marker id="a" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#444"/></marker>
  </defs>
  <rect x="20" y="20" width="860" height="420" rx="8" fill="#fafafa" stroke="#bbb"/>
  <text x="34" y="42" font-weight="bold">nshell process (SBCL image)</text>
  <rect x="40" y="60" width="260" height="120" rx="6" fill="#e8f0fe" stroke="#4a6fa5"/>
  <text x="52" y="80" font-weight="bold">presentation</text>
  <text x="52" y="100">:ask input mode (new)</text>
  <text x="52" y="118">transient panel (completion-menu region)</text>
  <text x="52" y="136">read-key-cont: 4th polled flag</text>
  <text x="52" y="154">ring-buffer view for scrollback commit</text>
  <rect x="40" y="200" width="260" height="110" rx="6" fill="#e6f4ea" stroke="#3a8a5c"/>
  <text x="52" y="220" font-weight="bold">domain (no I/O)</text>
  <text x="52" y="240">context assembly + redaction</text>
  <text x="52" y="258">response parse -&gt; command-node</text>
  <text x="52" y="276">safety classifier: safe / confirm / block</text>
  <text x="52" y="294">history-v3 record model</text>
  <rect x="340" y="60" width="240" height="120" rx="6" fill="#fff4e5" stroke="#c77d1a"/>
  <text x="352" y="80" font-weight="bold">application</text>
  <text x="352" y="100">ask / explain / agent-step use cases</text>
  <text x="352" y="118">classifier consulted before dispatch</text>
  <text x="352" y="136">(execute-pipeline-control)</text>
  <text x="352" y="154">turn generation id for staleness</text>
  <rect x="340" y="200" width="240" height="110" rx="6" fill="#fde8e8" stroke="#b03a3a"/>
  <text x="352" y="220" font-weight="bold">infrastructure</text>
  <text x="352" y="240">model boundary (swappable)</text>
  <text x="352" y="258">sidecar spawn: own pgid, not a job</text>
  <text x="352" y="276">PTY runner + bounded ring buffer</text>
  <text x="352" y="294">pending-result cell (concurrent-kit)</text>
  <rect x="620" y="60" width="240" height="250" rx="6" fill="#f3f3f3" stroke="#888" stroke-dasharray="6 3"/>
  <text x="632" y="80" font-weight="bold">outside the image</text>
  <rect x="640" y="100" width="200" height="60" rx="4" fill="#fff" stroke="#888"/>
  <text x="652" y="120">claude -p sidecar</text>
  <text x="652" y="138">stream-json in / out</text>
  <text x="652" y="154">spawned once per session</text>
  <rect x="640" y="180" width="200" height="50" rx="4" fill="#fff" stroke="#888"/>
  <text x="652" y="200">foreground child under PTY</text>
  <text x="652" y="218">still sees a TTY</text>
  <rect x="640" y="250" width="200" height="50" rx="4" fill="#fff" stroke="#888"/>
  <text x="652" y="270">external agent (Claude Code)</text>
  <text x="652" y="288">reads exported state / MCP</text>
  <line x1="300" y1="120" x2="340" y2="120" stroke="#444" stroke-width="1.5" marker-end="url(#a)"/>
  <line x1="460" y1="180" x2="460" y2="200" stroke="#444" stroke-width="1.5" marker-end="url(#a)"/>
  <line x1="340" y1="250" x2="300" y2="250" stroke="#444" stroke-width="1.5" marker-end="url(#a)"/>
  <line x1="580" y1="240" x2="640" y2="130" stroke="#444" stroke-width="1.5" marker-end="url(#a)"/>
  <line x1="580" y1="270" x2="640" y2="205" stroke="#444" stroke-width="1.5" marker-end="url(#a)"/>
  <line x1="580" y1="290" x2="640" y2="275" stroke="#444" stroke-width="1.5" marker-end="url(#a)"/>
  <line x1="400" y1="200" x2="200" y2="180" stroke="#4a6fa5" stroke-width="1.5" stroke-dasharray="4 3" marker-end="url(#a)"/>
  <text x="240" y="196" fill="#4a6fa5">flag poll</text>
  <rect x="40" y="340" width="820" height="80" rx="6" fill="#fff" stroke="#bbb"/>
  <text x="52" y="360" font-weight="bold">invariants</text>
  <text x="52" y="380">keystroke remains a pure function of input-state; async results enter only through the polled cell</text>
  <text x="52" y="398">nothing AI-generated executes without a keystroke; classifier runs on the AST, never on the raw string</text>
  <text x="52" y="416">no HTTP, TLS, or JSON dependency added for the model path; the sidecar owns auth, tools, and MCP</text>
</svg>
```

依存の変更: モデル経路では **なし**。JSON の読み書き (stream-json、transcript、snapshot、監査ログ) に cl-json-kit を追加する。org 内で依存なしの実装で、package-first 方針に合う。

## 8. データ変更

**history v3** (1 レコード、length-framed は v2 を踏襲)

| フィールド | 型 | 備考 |
|---|---|---|
| text | string | 従来 |
| timestamp | universal-time | history-kit entry に既存 |
| exit | integer or nil | 同上 |
| cwd | string | 新規 |
| duration-ms | integer or nil | 新規 |
| origin | typed / proposal / agent | 新規 |

**transcript** (JSONL、1 行 1 コマンド): timestamp, cwd, text, exit, duration-ms, origin, output-head (上限行数、redaction 済み), git (branch, dirty)。

**snapshot** (JSON、上書き): cwd, git, jobs[], last {text, exit, duration-ms}, env-names[], session-id, ai {connected, turns, tokens}。

**監査ログ** (JSONL): 送信ペイロード全文 (redaction 後) と応答の要約。

**設定**: `~/.nshellrc` は script のままなので、AI 設定は `ai set <key> <value>` builtin と環境変数 (`NSHELL_AI_COMMAND`、`NSHELL_AI_MODEL`、`NSHELL_AI_DISABLE`) で持ち、`ai set` は `.nshellrc` に追記可能な行として出力する。設定キー: command, model, max-steps, ring-bytes, panel-max-rows, denylist, budget, language。

## 9. インターフェース変更

| 面 | 変更 |
|---|---|
| キー | ask chord (実装者が未使用キーから選ぶ。候補: `C-Space`、`C-]`、`C-^`。Alt 系は不可)、command-not-found フォールバックの 1 キー、失敗後の explain キー、提案パネルの Tab / ⌃G / v、agent の Enter / e / s / q |
| builtin | `agent "<task>"`、`ai` (status / reset / log / set) |
| CLI | `nshell --mcp` |
| prompt | 失敗印セグメント、AI 状態セグメント (接続、turn、tokens) |
| ファイル | `$XDG_STATE_HOME/nshell/{transcript-<session>.jsonl, snapshot.json, ai-audit.jsonl}` |
| sidecar プロトコル | stdin: `{"type":"user","message":{"role":"user","content":…}}` 1 行 1 turn。stdout: `system init`、`assistant`、`rate_limit_event`、`result` の行。`result` の `duration_ms` は turn 単位、`duration_api_ms` は累積 |

## 10. 制約

- **検証環境**: この端末の SBCL は特定のエラー通知でデッドロックし、フルスイートをローカルで回せない。CI は x86_64-linux のみ。PTY スパイクの既存テストは CI か、`nix run .#test` が通るときのローカルで判定する。
- **Nix**: `claude` は Nix 管理外。`NSHELL_AI_COMMAND` で実行ファイルを指定でき、不在時は FR-009 の無効化経路。
- **公開リポジトリ**: 監査ログ・transcript・snapshot をコミット対象にしない (`.gitignore` ではなく state dir に置く)。ホスト名や home path を含む出力は redaction の対象外なので、外部共有は利用者責任。
- **端末マトリクス**: 一時パネルは tmux (tmux-256color) と素の端末で検証。Emacs `term`/`eat` は Phase 1 の範囲外。
- **raw-mode 契約**: PTY 化は「実端末を子に渡す」設計を置き換える。`docs/src/reference/architecture.md` と `raw-mode.lisp` の記述更新は同一変更に含める。
- **org 方針**: 新規外部依存は cl-json-kit のみ。TLS を持ち込まない。
- **git 操作**: 既定ブランチ (main) には直接入れない。

## 11. テスト要件

| 対象 | 観測可能な受け入れ条件 | 層 / 使う support |
|---|---|---|
| 安全分類 | `rm -rf /`, `git push --force`, `dd of=/dev/…`, `curl … \| sh` が confirm または block、`ls`, `git status`, `grep` が safe。パイプラインは最悪ステージの分類 | unit、AST フィクスチャのみ、モデル不要 |
| redaction | 環境変数の値、`ghp_…`、PEM、denylist path が送信ペイロードと監査ログに現れない | unit、否定アサート |
| ask モード | chord → サフィックス表示 → Enter で送信 → 記録フィクスチャの応答でバッファ置換 → undo で戻る | unit (`t/support/input-state*.lisp`) + e2e (`t/support/repl.lisp` の `with-repl-input-state`, `with-stable-repl-prompt`) |
| フォールバック | exit 127 の直後に 1 キーで ask に入り、他キーで案内が消え履歴に残らない | e2e |
| explain | 非 0 後の印、1 キーでパネル、Tab で候補がバッファへ、任意キーで消える | integration (`capture-process-output-event`) + e2e |
| agent | 3 ステップのフィクスチャで、承認なしに次へ進まない、`s` で飛ぶ、`q` で残りが走らない、`block` で Enter 無効 | integration (状態機械) + e2e |
| キャンセル | 待機中 `⌃C` で 100ms 以内に中止表示、sidecar 生存。2 度目で再 spawn | e2e (PTY で nshell 駆動) |
| sidecar 不在 | `NSHELL_AI_COMMAND=/nonexistent` で全非 AI テストが同結果 | 既存 e2e を環境変数付きで再実行 |
| PTY スパイク | 既存 job-control / PTY テストが緑。`sleep 100` + `⌃Z` + `fg`、vim、ssh を手動 | e2e / integration 既存 + 手動チェックリスト |
| リングバッファ | 100MB 出力後もサイズが上限以下 | integration |
| history v3 | v2 ファイルの読み込みで欠損 nil、書き戻しで v3、`⌃R` の失敗絞り込み | integration (`t/integration/test-file-history.lisp` 拡張) |
| エクスポート | プロンプト後に snapshot が cwd と exit を反映、transcript に 1 行追記、`nshell --mcp` が両方を返す | integration + e2e |
| 起動 | AI 有効時も `t/perf/test-startup.lisp` の予算内 | perf |
| 非対話 | `-c 'agent x'` が exit 2、sidecar が spawn されない | e2e (`t/e2e/test-smoke-script.lisp` 拡張) |

## 12. 未解決事項

**none**。計測して決める値 (NFR-3 の目標、NFR-5 の既定バイト数、structured output の採否) は Phase 1 のタスクとして扱う。

## 13. タスク分解

依存関係: P0 → P1 (P1-a と P1-b は並列可) → P2 → P3 → P4。P1-b の結果で FR-004 / FR-010 の範囲が確定する。

**P0 基盤 (すべての後続が依存)**
1. `packages/feature/assistant/` スライスの骨格と `nshell.asd` の module 追加。`t/integration/test-package-topology.lisp` に登録。
2. モデル境界 (infrastructure): sidecar spawn (自 pgid、非登録)、stream-json 読み書きスレッド、pending セル + 世代 ID、死活と再 spawn。テストは記録フィクスチャ境界。cl-json-kit を依存に追加。
3. `read-key-cont` の 4 番目の分岐 (`src/presentation/repl.lisp`) と、一時パネルの描画/消去 (`repl-output-completion.lisp` の save/move/restore を一般化)。
4. 安全分類器 (domain) と dispatch 前の呼び出し (`execute-pipeline-control.lisp` 234–235 行)。
5. redaction と文脈組み立て (domain)、監査ログ (infrastructure)。

**P1-a ask と提案 (P0 に依存)**
6. `:ask` モード: `data/presentation/input-state-data.lisp` の型、`input-state-session.lisp` の分岐、専用 reducer、プロンプトサフィックス。ask 中の autosuggestion / abbr / history expansion 無効化。
7. 提案の受け取り: バッファ置換 (undo 可)、分類表示、confirm の確認行、block の拒否。
8. command-not-found フォールバック (`syscall-process-resolution.lisp` 6–35 行、`manage-job.lisp` 37 行)。
9. NFR-3 の計測: 常駐 turn の p50、`--json-schema` を常駐セッションで測り採否を決める。

**P1-b PTY スパイク (P0 の 1 のみに依存、P1-a と並列)**
10. PTY ランナー: `pty-spawn` (`src/infrastructure/acl/pty-spawn.lisp` 47 行) を子コマンド実行に転用、ウィンドウサイズ伝播、シグナル転送、リングバッファ tee。
11. ゲート判定: 既存テスト + 手動チェックリスト。通過なら `%spawn-terminal-command` 経路を置換し raw-mode 文書を更新。不通過ならフォールバック経路に切り替え、FR-004 の範囲を縮小して記録。

P1-b 判定: PTY ランナーの ACL 単体・統合テストと、`printf` および停止・再開の直接スモークは通過したが、子コマンド経路のゲートは不通過だった。`e2e-external-job-stop-bg-fg-interrupt` は `PTY job condition timed out; output: ""` で単独再現し、tmux 手動確認でも `sleep 100` に Ctrl-Z を送った後にプロンプトへ戻らず、`fg` と Ctrl-C の後にだけプロンプトへ戻った。Vim は起動・終了できた。SSH は `localhost:22` に接続先がなく判定不能だった。したがって `%spawn-terminal-command` は既存の SBCL プロセス経路に戻し、P1-b のフォールバック範囲を「単純コマンドは従来経路、パイプラインとリダイレクトも従来のバッファ経路」とする。PTY ACL とリングバッファの検証コードは、再試行時の基礎として残す。

**P2 explain と history (P1-a、P1-b に依存)**
12. history v3 (`file-history.lisp`、読み込み昇格、`⌃R` 絞り込み)。
13. 失敗印セグメント (`src/domain/prompting/prompt.lisp` のセグメント追加) と explain 要求、Tab で候補投入。

**P3 agent (P1-a、P2 に依存)**
14. `agent` builtin と step 状態機械 (application)、パネルの step 表示、Enter / e / s / q、最大ステップ、中止。
15. `ai` builtin (status / reset / log / set) と使用量セグメント。

**P4 外部基盤 (P2 に依存)**
16. transcript と snapshot の書き出し (プロンプト境界のフック、`render-prompt-cont` 付近)。
17. `nshell --mcp` (`src/main.lisp` の cl-cli 定義に追加、stdio MCP、2 ファイル配信)。
18. ドキュメント: README の位置づけ、man の KEY BINDINGS / BUILTINS / ENVIRONMENT、`docs/src/reference/architecture.md` の raw-mode 節と AI 節、`public-readiness.md` の行追加。

## 14. 実装で前提にしてはいけないこと

- `feature-registry` は実行時ゲートではない。任意性は実行時の sidecar 不在で表現する。
- モデルの risk タグを安全ゲートに使わない。
- 単純コマンドの出力が今バッファされていると仮定しない (端末継承)。
- `claude --bare` は認証を読まないので高速化に使えない。
- Serena のシンボル操作はこのリポジトリで効かない (言語検出が perl)。Grep / Read で進める。
- ローカルの SBCL はエラー通知 (`check-type` / 引数個数不一致 / 未知キーワード) でデッドロックしうる。緑の判定は CI か `nix run .#test` で。
