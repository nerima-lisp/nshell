# 1つのコアと 3つのフロントエンド

対話・バッチ・機械向けのどれも同じ共通 API を通るので、AI が --serve で得る結果と人間が REPL で見る結果は常に一致します。

FRONTENDS

対話 REPL

ラインエディタ・ハイライト・autosuggest・補完 UI・ai / agent

バッチ

スクリプト・--command・stdin

機械向け

--json・--serve (JSON Lines)・--mcp

⌄

共通 API (どのフロントエンドも同じ入口を通る)

run

評価して結果を返す

explain

AST・効果・危険度

complete

補完候補

initialize / state / history / help / policy / query / read_output

状態・履歴・仕様・規則・事実・出力の続き (U5・U6)

⌄

CORE

Reader

S式と bare-line ショートハンドを同じ AST に

Evaluator

Lisp 評価・位置の規則・値パイプライン・関数・restart (L4)

Executor

プロセス・パイプ・リダイレクト・ジョブ・timeout

Knowledge base

cl-prolog-kit の事実と規則: 危険度・効果・診断・型・補完文法。redaction

⌄

PLATFORM

POSIX spawn / PTY

子プロセス起動と端末

シグナル・ジョブ制御

プロセスグループ

端末 I/O

raw mode・幅計算

永続化

履歴・設定・監査ログ

## ディレクトリ案

4 層 (domain / application / infrastructure / presentation) を機能単位にまとめ直す。

```
packages/
  core/          reader · evaluator · executor · ast · errors
  feature/
    repl/        line editor · highlight · autosuggest · completion UI
    machine/     --json · --serve · --mcp
    builtins/
    completion/
    history/
    assistant/   ai · agent · redaction · providers
                 (claude-code · codex · ollama)
    kb/          知識ベース (cl-prolog-kit) の事実と規則
  platform/      posix spawn · pty · signals · terminal
t/
  unit/  golden/  pty/
AGENTS.md
```

## 依存 toolkit

削減後に不要になる見込み:

cl-dataflow-kit

cl-boundary-kit

pipeline-graph の削除と REPL 境界の簡素化に伴うもの。cl-prolog-kit は知識ベースの中核として残します (06)。残りの 16 個は利用箇所を確認して個別に判断します。
