# シェル内 AI 支援と、AI が開発しやすい構成

## A. シェル内の AI 支援

「聞けば提案してくれるが、勝手には実行しない」を徹底します。

STEP 1

入力

行頭の `? ` (? と空白) に続けて自然言語、または Ctrl-]。`?foo` は glob のまま

›

STEP 2

提案

コマンドを入力欄に挿入。危険度と効果つき

›

STEP 3

人が確認

そのまま Enter か、編集してから Enter

›

STEP 4

実行と記録

結果と status が次の文脈になる

*パネルとキーは U3 と同じ*

```
~/src/nshell main ❯ ? 直近 1 週間で変更された lisp ファイルを数えて
╭ proposal · ● safe · effects: reads git history
│ (| (git log --since=1.week --name-only --format=)
│    (grep "\\.lisp$") (sort -u) (wc -l))
╰ Enter 実行 · Alt-E 編集 · Tab 説明 · Esc 破棄

~/src/nshell main ❯ make tset
make: *** No rule to make target 'tset'.  Stop.
✗ 2  · ai why で原因を調べる (Alt-W)
~/src/nshell main ❯ ai why
  ターゲット名の打ち間違い (規則 diagnose/typo · オフライン)
╭ fix · ● confirm
│ make test
╰ Enter 実行 · Alt-E 編集 · Tab 説明 · Esc 破棄
```

|   |   |   |
|---|---|---|
| [追加] | ? / Ctrl-] で自然言語入力 | 既存の ask モード (Ctrl-]) を拡張。提案は入力欄に入るだけで、実行は常に人の Enter。agent の承認ゲートと同じ原則。 |
| [追加] | ai why | 直前の失敗 (コマンド・status・stderr の末尾) を説明し、修正案を入力欄へ。 |
| [追加] | ai explain | 入力中のコマンドを説明。ローカルの explain (AST・効果・危険度) を先に出し、モデルは補足だけ。F1 のパネルからも呼べる (U4)。 |
| [簡素化] | プロバイダを選べる sidecar | 現在は claude CLI 固定。Claude Code (既定)・Codex・Ollama から選べるようにする (09)。 |
| [残す] | agent TASK | 複数ステップの提案と承認。表示を簡素化し、explain / safety を --serve と共有。 |
| [残す] | redaction・audit・--private | 秘匿化、監査ログ、記録しないモードはそのまま。 |

## B. AI が開発しやすいリポジトリ

エージェントが「どこを触り、どう確かめるか」を迷わない構成にします。

AGENTS.md (CLAUDE.md から参照)

目的、ディレクトリ地図、開発コマンド、層の依存方向、テストの書き方、やってはいけないこと (履歴や設定に触れる検証は隔離 HOME で、など) を 1 枚に。エージェントが使うコマンドは `nix develop -c sbcl --script …` の形で書き、dev shell の alias (test・weave・cov) は対話シェルでしか動かないので人向けとして書く。隔離には HOME と XDG_CONFIG_HOME・XDG_DATA_HOME・XDG_STATE_HOME・XDG_CACHE_HOME の 5 つと NSHELL_AI_COMMAND=/nonexistent を使う。テストの件数のように時間で変わる数は書かない。AGENTS.md だけを読んだエージェントが、ほかの文書を読まずにビルドと全テストを実行できることを受け入れの条件にする。

速いテスト導線

現在の検証は Nix ビルド前提で最大 5 分。unit だけを 30 秒以内で回す test-fast コマンド (nix develop 内で SBCL を直接起動) を用意し、変更→確認のループを短くする。test-fast は `nshell/test-unit` システムとして切り出し、`nshell/test` がそれに依存する形にする (main-test と静的チェックも含める)。30 秒はコンパイル結果がキャッシュ済みのときの時間で、キャッシュなしの時間も併記する。超えたら、測ったうえで重いテストに `:slow` タグを付けて外す。

1 機能 = 1 ディレクトリ

src/ の 4 層と packages/feature/ の混在を、packages/feature/<名前>/ の形に揃える。変更箇所を探す手間が減る。どのパッケージも中に `src/<層>/` を持つ。

golden test

--json の出力をスナップショットとして固定。シナリオ JSON コーパスの後継で、人も AI も差分を読みやすい。

層の依存の検査を保つ

層の向きは domain ← infrastructure ← application ← presentation。静的チェック (`t/unit/test-static-checks.lisp`) は、すでにこの向きに反する参照を失敗にしている。各層が参照してはいけない層を表で持ち、シンボルの属するパッケージかファイルのパスから層を決めて照合する。packages/ を組み直したあとも、パスの層名で同じ検査を続ける。

エラーコードと仕様を 1 か所に

builtin-spec とエラーコード一覧から help --json とドキュメントを生成し、記述の食い違いをなくす。
