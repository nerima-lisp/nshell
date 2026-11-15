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
| toolkit依存（設計時点で18個） | [簡素化] | INT-1で未参照の4つを先に削除しました。cl-dataflow-kitとcl-boundary-kitをP2で外します (04)。cl-concurrent-kitとcl-resilience-kitからもcl-boundary-kitを外します。cl-prolog-kitは中核として残します。 |

### テスト

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| nshell/test (cl-weave) — unit / integration / e2e / perf | [残す] | そのまま。 |
| nshell/weave — 補完 Prolog KB 専用スイート | [簡素化] | 知識ベース全体 (危険度・診断・型) の規則テストに広げる。 |
| property-based テスト | [残す] | そのまま。 |
| PTY 統合テスト — CI の Linux ジョブ | [残す] | そのまま。 |
| mutation テスト — スコア 1.0 を要求 | [簡素化] | 対象を parser と expansion に絞る。 |
| 静的チェックと allowlist — 層の向き (domain ← infrastructure ← application ← presentation) に反する参照を失敗にする検査を含む | [残す] | そのまま。packages/ の再編後も、パスの層名で層を判定して同じ検査を続ける。 |
| シナリオコーパス — 200 件超、run-scenarios.py | [簡素化] | PTY 中心の 30〜40 本を残し、batch のものは --json の golden test へ移す。それ以外は 1 本ずつ削除の理由を記録する。 |
| カバレッジ — 最低 85% | [残す] | そのまま。 |
| test-fast・golden test — なし | [追加] | 03 を参照。 |

### 計測と契約

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| contracts 層 — L02–L08、C06、E04–E06、WP | [削除候補] | 通常の unit テストへ吸収。 |
| NFR 計測 — measure-nfr-*.py、profile-nfr06、Q05 の NFS VM 試行 | [削除候補] | P0 で作る性能の計測 (08 の 6 項目) に置き換え、置き換えた旧スクリプトだけを消す。fuzz の入力は P5 のために残す。Q05 の NFS VM 専用ジョブと試行は前倒しで外した。2026-11-15 に別々の試行で delayed glob の 3 回目と baseline glob の 1 回目が失敗し、nshell の変更ごとに CI が不安定になっていたためである。遅いストレージ上の補完と glob の応答は自動検証しなくなる。P0-7 の性能比較 (`scripts/perf/`) はキーごとのファイル操作数を計測するが、遅いファイルシステムそのものは模していない。`Q05-git-probe-timeout-does-not-block-input` は対象外である。 |
| 競合ベンチ — benchmark-competitors.pl | [削除候補] | P0 で作る性能の計測に統合。 |
| 依存の登録と検査スクリプト — dependency registry / assertions | [簡素化] | flake.lock と静的チェックに寄せる。 |
| AGENTS.md — なし | [追加] | 03 を参照。 |
