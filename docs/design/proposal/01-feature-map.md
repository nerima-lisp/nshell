# 機能マップ — 何を残し、何を外すか

判断基準は「毎日の対話で使うか」「AI・スクリプトからの利用に効くか」の 2 つ。どちらにも当てはまらないものを削除候補にしています。下の数字は外す量の目安で、新しく足す機能 (I10) の分は含みません。全項目の判定は「全機能棚卸し」ページ。

残す

そのまま磨く

簡素化

機能を絞る・統合する

削除候補

外す (または別パッケージ)

追加

新しく作る (一覧は I10)

製品コードから外す (目安)

約 4 千行

テスト・スクリプトから外す (目安)

約 3 万行

ビルトイン

55 → 42個

### 言語・パーサ

|   |   |   |
|---|---|---|
| S式コマンド言語 — sexp-reader / scanner 3.6K行 | [残す] | 中核。reader と scanner の重複ロジックは統合し、エラー位置 (行・列) を構造化して返す。 |
| 名前解決・置換・値の変換 — head の判定は PATH に依存 | [簡素化] | PATH に依らない固定の順序、引数の ( ) は置換、値の位置は capture などで明示 (言語仕様 L0〜L7)。 |
| bare-line ショートハンド — tokenizer / parser | [残す] | 単純コマンド・パイプ・リダイレクト・&& \|\| ; & だけを扱う近道として残す (L5)。 |
| bare-line の制御構文・here-doc — control-flow + here-doc 約900行 | [削除候補] | if / for / while / here-doc は S式側にあるので二重実装を解消。bare-line で書かれたら S式の書き方を提示する。 |
| 値パイプライン -> — where / select / to-json ほか | [残す] | AI 対応の土台。ビルトインがレコードを返すよう拡張する (AI 面を参照)。 |
| 履歴展開 — !! !$ !-N !?text? !prefix | [簡素化] | !! と !$ のみ残す。残りは Ctrl-R 検索で代替できる。 |
| alias / abbr — 2つの仕組み | [簡素化] | abbr に一本化し、alias は abbr の互換コマンドとして残す。 |

### ラインエディタ

|   |   |   |
|---|---|---|
| emacs キーバインド・undo・kill ring — input-state reducer | [残す] | 純粋 reducer + 値としての input-state はそのまま。テスト容易性の要。 |
| 履歴 autosuggest・ハイライト・Ctrl-R | [残す] | モダンシェルの基本セット。 |
| Alt-E で外部エディタ | [残す] | 長いコマンドや AI 提案の手直しに使う。 |
| vi モード — 約1,300行 | [残す] | 維持し、fish_vi_key_bindings と同等の体験にする (07 を参照)。 |
| 構造編集 (S式) — 約500行 | [簡素化] | sexp 単位の移動と削除だけ残し、slurp / barf を外す。対応括弧のハイライトを追加。 |
| マウス操作 — 約70行 | [削除候補] | 端末差異が大きく効果が小さい。 |

### 補完

|   |   |   |
|---|---|---|
| Prolog 知識ベース補完 — 3,078行 + cl-prolog-kit | [簡素化] | 表引きだけの使い方をやめ、DCG の文法と型で作り直す。知識ベースは危険度判定や診断にも広げる (06 を参照)。同じ候補を JSON でも返す。 |
| complete -C LINE | [残す] | 候補をそのまま AI / テストから引ける窓口として強化 (--json)。 |

### ビルトイン (55個)

|   |   |   |
|---|---|---|
| string / printf — 約970行 | [簡素化] | Lisp 関数 (string-*, format) を正とし、builtin は薄い互換ラッパにする。 |
| dirs / pushd / popd / prevd / nextd — 約150行 | [簡素化] | cd - と pushd / popd / dirs のみ。prevd / nextd を外す。 |
| pipeline-graph (DOT / Mermaid) — + cl-dataflow-kit | [削除候補] | 必要なら explain --json の AST から外部で描ける。 |
| theme / prompt — builtin + 設定 | [簡素化] | init.lisp の設定に集約。theme は list / use / show、prompt は show / preview だけコマンドで残す。 |
| jobs / fg / bg / wait / disown / kill / bind | [残す] | 対話シェルに必須。 |
| fish 形式のビルトイン — and or not break continue function count contains seq math | [削除候補] | S式と外部コマンドで代替できる。全 55 個の判定は「全機能棚卸し」ページの I4 を参照。 |

### 品質基盤

|   |   |   |
|---|---|---|
| contracts 層 (L02–L08 ほか) — 約2,000行 | [削除候補] | 製品コード内の契約チェックは通常のユニットテストへ吸収。 |
| NFR 計測・ベンチスクリプト — scripts 1.4万行の大半 | [削除候補] | 起動時間とキー入力遅延のベンチ 2 本に絞る。 |
| シナリオ JSON コーパス — 200件超・約2万行 | [簡素化] | 主要 30〜40 本に精選し、--json モードの golden test に移行。 |
| toolkit 依存 18個 | [簡素化] | 上記の削減で dataflow / boundary の 2 つは不要になる見込み。cl-prolog-kit は中核として残す。 |
