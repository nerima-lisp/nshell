# 開発・品質・配布

リポジトリの仕組みのすべて。製品より大きくなった計測・契約の層を外します。

残す

9

簡素化

5

削除候補

3

追加

2

### ビルドと配布

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| Nix flake — build / develop / fmt (treefmt) / checks | [残す] | そのまま。 |
| リリースバンドル — x86_64-linux、SHA-256、検証スクリプト | [残す] | そのまま。 |
| Cachix | [残す] | そのまま。 |
| man ページ・MkDocs | [残す] | builtin spec から生成する部分を増やす。 |
| toolkit 依存 18 個 | [簡素化] | dataflow / boundary は不要になる見込み。cl-prolog-kit は中核として残す。残りは個別判断。 |

### テスト

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| nshell/test (cl-weave) — unit / integration / e2e / perf | [残す] | そのまま。 |
| nshell/weave — 補完 Prolog KB 専用スイート | [簡素化] | 知識ベース全体 (危険度・診断・型) の規則テストに広げる。 |
| property-based テスト | [残す] | そのまま。 |
| PTY 統合テスト — CI の Linux ジョブ | [残す] | そのまま。 |
| mutation テスト — スコア 1.0 を要求 | [簡素化] | 対象を parser と expansion に絞る。 |
| 静的チェックと allowlist | [残す] | 層の依存方向の検査を追加。 |
| シナリオコーパス — 200 件超、run-scenarios.py | [簡素化] | 30〜40 本に精選し --json の golden test へ。 |
| カバレッジ — 最低 85% | [残す] | そのまま。 |
| test-fast・golden test — なし | [追加] | 03 を参照。 |

### 計測と契約

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| contracts 層 — L02–L08、C06、E04–E06、WP | [削除候補] | 通常の unit テストへ吸収。 |
| NFR 計測 — measure-nfr-*.py、profile-nfr06、Q05 の VM 試行 | [削除候補] | 起動時間とキー入力遅延のベンチ 2 本に。 |
| 競合ベンチ — benchmark-competitors.pl | [削除候補] | 上の 2 本に統合。 |
| 依存の登録と検査スクリプト — dependency registry / assertions | [簡素化] | flake.lock と静的チェックに寄せる。 |
| AGENTS.md — なし | [追加] | 03 を参照。 |
