# nshell v0.8 設計

nshell を「必要十分で、人にも AI にも使いやすいシェル」にするための設計一式です。
元は claude.ai のデザインキャンバス (nshell 機能デザイン) で、その全ボードを Markdown にしたものがこのディレクトリです。
キャンバスを直したら、ここも同じ内容に直してください (ここが実装の正)。

## 読む順番

| 順 | ファイル | 内容 |
|---|---|---|
| 1 | [00-overview.md](00-overview.md) | 目的・原則・主な決定 |
| 2 | [proposal/05-roadmap-and-decisions.md](proposal/05-roadmap-and-decisions.md) | フェーズ P0〜P6 と決定事項 |
| 3 | [tasks/](tasks/) | フェーズごとのタスクと受け入れ条件 |
| 4 | 各タスクが参照する章 | 下の一覧 |

## 構成

- `proposal/` — 01 機能マップ、02 機械向けインターフェース、03 シェル内 AI と開発のしやすさ、04 アーキテクチャ、05 ロードマップと決定事項、06 cl-prolog-kit の知識ベース、07 vi モード、08 堅牢さ、09 AI プロバイダ
- `ux/` — U0 原則と「画面 ⇄ JSON フィールド」の対応表、U1〜U4 人間、U5〜U7 AI、U8 さらに上げる、U9 リッチ UI
- `language/` — L0 概要と 12 の決定、L1 字句、L2 名前解決、L3 コマンド形式、L4 値と位置、L5 bare-line、L6 実行とエラー、L7 現状との差分と移行
- `inventory/` — I0 集計、I1〜I9 既存機能すべての判定 (残す / 簡素化 / 削除候補)、I10 新しく足す機能
- `tasks/` — P0〜P6 のタスク
- `conformance/` — 言語の実測データ (下記)

## 決定の状態

| 項目 | 状態 |
|---|---|
| vi モードは残し fish と同等に / cl-prolog-kit は中核に / AI プロバイダは Claude Code (既定)・Codex・Ollama / テレメトリなし | 決定 |
| 言語仕様の 12 の決定、bare-line 制御構文の扱い、-c の委譲、MCP の confirm、破壊的変更の進め方、出力ストア、メッセージの言語 | 仮決定 (推奨で進める) |
| 特に要確認: 衝突表の 6 語、`:kw` を `":kw"` で渡す、glob 不一致をエラーにする | 仮決定 (実装前に作者に確認) |
| 性能予算の目標値 | 未定 (P5 で測ってから) |

## conformance/

- `language-probes-v0.7.0.json` — v0.7.0 (main 083f1603) を SBCL 2.6.9 でビルドし、151 個の入力を実行した結果 (exit / stdout / stderr)。言語仕様はこの実測をもとに書いた
- `run_probes.py` — 同じ入力を任意のビルドで流すスクリプト (`NSHELL_BIN=./result/bin/nshell python3 run_probes.py language-probes-v0.7.0.json out.json`)
- 期待値: `language/L7-diff-and-migration.md` の 7.1 の表が、仕様での結果。P1-7 で `t/spec/` のテストに取り込む

## 用語

- **S式** / **bare-line**: 入力の 2 つの読み方 (L1)
- **Lisp 形式** / **コマンド形式**: S式のリストの 2 種類 (L2)
- **文・条件・値・引数の位置**: コマンドの意味を決める場所 (L4)
- **safe / confirm / block**: 危険度 (proposal/06 A、ux/U7)
- **知識ベース**: cl-prolog-kit の事実と規則 (proposal/06)
