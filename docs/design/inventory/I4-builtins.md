# ビルトイン (55 個)

すべてのビルトインの判定。S式や外部コマンドで代わりが利くものは外します。

残す

19

簡素化

7

削除

9

追加

0

### 変数・環境

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| set — -l -g -x -e -q、-o vi / pipefail | [残す] | そのまま。 |
| unset | [残す] | set -e の別名として維持。 |
| export | [残す] | そのまま。 |

### 制御・論理

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| and / or / not — fish 形式 | [削除] | bare-line の && \|\| と S式の and / or / not で足りる。v0.8 で削除し、E_UNSUPPORTED_SYNTAX で拒否する。 |
| break / continue — bare-line ループ用 | [削除] | bare-line の制御構文と一緒に v0.8 で削除。 |
| true / false | [残す] | そのまま。 |
| test / [ — -e -f -d -n -z = != -eq ほか | [残す] | そのまま。使い方の誤りは status 2。 |

### 実行・関数

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| function — fish 形式の定義 | [削除] | defcmd に一本化 (L5.3)。v0.8 で削除。 |
| functions — 定義の一覧・表示 | [残す] | defun・defcmd で定義したものの一覧に。値の位置ではレコード (L4.4)。 |
| eval / source / . | [残す] | そのまま。 |
| builtin / command / exec / exit | [残す] | そのまま。 |

### 文字列・数値

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| echo / read | [残す] | そのまま。 |
| printf — 書式・エスケープ・数値 | [簡素化] | %s %d %f %x と \n \t 程度に絞り、残りは format へ。 |
| string — 11 サブコマンド (collect length lower upper join split replace match repeat sub trim) | [簡素化] | match / replace / split / join / trim の 5 つに絞り、Lisp 関数の薄いラッパにする。 |
| count — 引数や行を数える | [削除] | wc -l と (length …) で代替。 |
| contains | [削除] | (member …) で代替。 |
| seq | [削除] | 外部の seq と (loop …) で代替。 |
| math | [削除] | $((…)) と ,(…) で代替。 |

### ディレクトリ

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| cd / pwd — cd - に対応 | [残す] | そのまま。 |
| pushd / popd | [残す] | そのまま。 |
| dirs | [簡素化] | pushd のスタック表示だけに。 |
| prevd / nextd — 訪問履歴を前後に移動 | [削除] | cd - と Ctrl-R で足りる。 |

### ジョブ

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| jobs / fg / bg / wait / disown / kill — シグナル名対応 | [残す] | jobs は値位置でレコードを返す。 |

### 情報

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| type — builtin / 関数 / 外部の判定 | [残す] | --json を追加。 |
| which | [簡素化] | type -p の別名に。 |
| help | [残す] | --json を追加し、spec から生成。 |
| history — search (--prefix --contains --exact --case-sensitive) / delete / clear / size | [残す] | 値位置でレコード (cwd・status・所要時間を含む) を返す。 |

### 対話設定

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| bind — 一覧・設定・-e・--reset | [残す] | そのまま。 |
| complete — -c -f -l -s -a -d -e、-C LINE | [残す] | -C に --json を追加。 |
| abbr / alias | [簡素化] | 役割を分ける。alias はコマンドの定義、abbr は対話入力での展開だけで、スクリプトでは展開しない (L2.1)。 |
| theme — list / use / set / show / reset | [簡素化] | list / use / show のみ。細かい上書きは init.lisp で。 |
| prompt — show / left / right / preview / reset | [簡素化] | show / preview のみ。設定は init.lisp で。 |

### AI・可視化

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| ai — status / reset / log / set | [残す] | why / explain を追加 (03 を参照)。 |
| agent — 複数ステップの提案と承認 | [残す] | 表示を簡素化。 |
| pipeline-graph — DOT / Mermaid | [削除] | explain --json の AST から外部で描ける。 |
