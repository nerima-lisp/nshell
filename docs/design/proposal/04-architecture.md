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

4 層 (domain / application / infrastructure / presentation) を機能単位にまとめ直す。どのパッケージも中に `src/<層>/` を持ち、層の向き (domain ← infrastructure ← application ← presentation) の静的チェックは、パスの層名で層を判定する。

再編は P2 の後、P3 と P4 の前に行う。P1 と P4 で新しく書く機械向けのコードは、再編を待たずに最初から `packages/feature/machine/` に、知識ベースは `packages/feature/kb/` に置く。

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

削除対象だった6つのうち未参照の4つはINT-1で削除済みです。

| toolkit | 削除時期と理由 |
|---|---|
| cl-process-kit、cl-vcs-kit、cl-tui-kit、cl-log-kit | INT-1で削除済み。nshellから参照されていなかった |
| cl-dataflow-kitとcl-boundary-kit | P2の削除 (pipeline-graphの削除とREPL境界の簡素化) に合わせて外す |

cl-boundary-kit をイメージから消すため、cl-concurrent-kit と cl-resilience-kit からもこの依存を外します。どちらも時計の用途だけなので、cl-host-kit の時計に置き換えます。

U9の表やステータスラインはcl-tty-kitの上にnshellで作り、文字幅の表を1つに保ちます。Ollamaとの接続にはcl-ollama-kit v3 (cl-http-kit経由)を使い (09)、trustのハッシュにはcl-crypto-kitのSHA-256を使います (08)。cl-prolog-kitは知識ベースの中核として残します (06)。
