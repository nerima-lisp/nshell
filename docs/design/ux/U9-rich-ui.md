# イマドキのリッチな UI — ブロック・表・パレット

Warp や最近の TUI のように、コマンドと出力を「ブロック」として扱い、表・プレビュー・パレットで目で追いやすくします。ただし端末の中で完結させ、tmux や ssh 越しでも崩れないようにします。

*ブロック表示・インラインの表・ステータスライン*

```
╭─ ~/src/nshell  main  ·  make test                                                               ✓ 0.8s · 14:31
│ ok 812 tests, 0 failures
╰─
╭─ ~/src/nshell  main  ·  cargo build                                         ✗ 101 · 3.2s · ai why で原因を見る
│ error[E0425]: cannot find value `cfg` in this scope
│   --> src/main.rs:42:9   (Ctrl+クリックでエディタへ)
╰─
╭─ ~/src/nshell  main  ·  (-> (files "src") (sort-by :size :desc) (take 4))                     ✓ 0.02s · 4 rows
│ name                              type    size
│ sexp-reader.lisp                  file    86 KB     ████████████████████
│ sexp-evaluator.lisp               file    71 KB     ████████████████▌
│ sexp-scanner.lisp                 file    52 KB     ████████████
│ repl-output-handlers.lisp         file    47 KB     ███████████
╰─

❯ git push origin main

 INSERT  ~/src/nshell   main ↑1 ●  jobs 1  ai cc                                                 utf-8 · 120×36
```

*補完: 右にプレビュー (ブランチなら最近のコミット)*

```
~/src/nshell main ❯ git switch re
╭───────────────────────────────┬────────────────────────
│ ▸ release/0.8                 │ a1f3e2c tidy reader
│   refactor/kb                 │ 9c0d4b1 add DCG rules
│   revert-12                   │ 77e01aa fix escape
│                               │ ↑2 ↓0 vs main
╰ 3 branches · Tab ↓ · → preview
```

*コマンドパレット: すべての操作を 1 か所から*

```
╭ command palette · Alt-P
│ › theme█
│  ▸ theme use nord           switch theme
│    theme use tokyo-night    switch theme
│    theme show               current roles
│    bind: toggle-sudo        Alt-S
╰ commands · history · abbr · keys · settings
```

*AI の回答: Markdown と差分を整形して表示*

```
╭ ai · claude-code · ● streaming
│ The build fails because cfg is declared
│ inside the #[cfg(test)] block only.
│
│ - let x = cfg.value;
│ + let x = Config::load()?.value;
╰ Enter apply via editor · Esc close
```

## 端末の能力を見て使い分ける

| 機能 | 判定 | 使えないとき |
|---|---|---|
| 真の色 (24bit) | COLORTERM | 256 色 → 16 色に落とす |
| OSC 8 ハイパーリンク | 端末の応答 | 下線のみ |
| OSC 133 ブロック境界 | 常に出す (害がない) | — |
| 同期描画 (DEC 2026) | DECRQM | 差分描画のみ |
| 画像 (kitty / iTerm2 / Sixel) | 端末の応答 | Unicode のブロック文字 ▁▂▃▅▇ |
| Nerd Font の記号 | 設定で明示 | 標準 Unicode の記号 |

ui :rich (既定) / :classic (ブロックとステータスラインなし) / :plain (色と罫線なし、スクリーンリーダー向け) で切り替え。--json・--serve・パイプの出力には一切影響しない。

ブロック表示

コマンドと出力を 1 つの塊に。見出しに場所・状態・所要時間・時刻。失敗した塊は赤く、ai why への導線つき。Alt-↑↓ で塊ごとに移動し、出力のコピーや再実行ができる。

OSC 133 で境界を端末にも伝える

インラインの表

値位置のレコードは揃った表に。数値の列には小さな横棒。長い列は省略し、(view) で全体を開ける。

L4.7 の値パイプラインと共通

ステータスライン

画面下に 1 行: vi モード・場所・git・ジョブ・AI プロバイダ・端末サイズ。不要なら消せる。

右プロンプトの情報はここへ寄せられる

プレビューつき補完

候補の右に中身: ファイルは先頭数行、ブランチは最近のコミット、フラグは説明と排他関係。

知識ベース (06-E) から

コマンドパレット

Alt-P で、コマンド・履歴・abbr・キー操作・設定をまとめてあいまい検索。

覚えていない操作もたどり着ける

整形された AI の回答

Markdown の太字・コード・リストと、コマンドやファイルの差分を色つきで表示。ストリーミング中は進行の印だけ。

U3 のパネルと同じキー

クリックできるパスと URL

エラーの file:line はエディタで開ける (OSC 8)。

NSHELL_EDITOR を使う

ちらつかない描画

差分だけを書き、対応端末では同期描画。大きな出力の途中でも入力が乱れない。

キー入力から描画の予算 (08) を守る

画像とグラフ

(view) のグラフや Alt-T のファイルプレビューで画像を表示。使えない端末ではブロック文字。

kitty・iTerm2・Sixel

## リッチにしても守ること

- 情報が増えるのは意味があるときだけ。成功した短いコマンドは 1 行の見出しで終わる。ui :classic は U1 の transient prompt と右プロンプト。
- 装飾は端末の文字と記号だけで作る。ウェブ画面や独自のウィンドウは持たない (tmux・ssh・Emacs でも同じ見た目)。
- スクロールバックをそのまま残す。全画面を占有するのは (view) とパレットだけで、Esc で元に戻る。
- 人が見るブロックの見出しと、AI が受け取るフィールド (status・duration_ms・cwd) は U0 の対応表どおり 1 対 1。
