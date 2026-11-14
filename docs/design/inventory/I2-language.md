# コマンド言語 (S式 / bare-line)

入力の読み方と評価のすべて。S式を正とし、bare-line は入力の近道に絞ります。

残す

22

簡素化

4

削除候補

3

追加

4

### S式

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| ( で始まる入力を S式として読む — ネストした list にも適用 | [残す] | そのまま。 |
| Lisp 形式とコマンドの自動判定 — head が CL の形式に解決すれば Lisp、なければコマンド | [簡素化] | PATH に依らない固定の順序と衝突表で決める。^name で外部コマンドを強制、explain で判定理由を表示 (L2)。 |
| $NAME で変数値を渡す | [残す] | リストは要素ごとに別の引数に (L3)。 |
| ,EXPR で評価値を渡す | [残す] | 変換は 1 つの表で決める: nil は引数なし、リストは ,@ (L3.2)。 |
| 文字列リテラルは展開しない | [残す] | AI が予測しやすい。維持。 |
| 文字列のエスケープ — CL のまま (\n が n になる) | [簡素化] | \n \t \e \u{…} などを使えるようにする (L1.3)。 |
| 値・ストリーム・テスト位置 — 位置で戻り値の意味が変わる | [残す] | ドキュメントに位置ごとの表を追加。 |
| (= (cmd) 0) で終了コード | [簡素化] | (status …) に置き換え、v0.8 は警告 (L4・L7)。 |
| (\| …) と \|& — バイトパイプライン | [残す] | そのまま。 |
| -> — スレッディングマクロ | [残す] | そのまま。 |
| where — (= :key value) のみ対応 | [残す] | 強化: < > /= and or not と文字列一致を追加。 |
| select — キーの射影 | [残す] | 強化: sort-by・take・count を追加。 |
| to-json / from-json / tsv / lines | [残す] | そのまま。--json の出力と同じ変換を使う。 |
| regex-match-p / regex-find / regex-replace | [残す] | そのまま。 |
| split-string / join-strings / replace-string — string builtin と重複 | [残す] | こちらを正とし、string builtin を薄くする。 |
| defun によるシェル関数 — 制御形式の中でも定義可 | [簡素化] | defun は Lisp 関数、語を受け取るコマンドは defcmd (L4.5)。 |
| CL の制御形式 — if / when / let / loop / defmacro | [残す] | そのまま。 |
| set によるシェル変数 | [残す] | そのまま。 |
| command-failed と handler-case | [残す] | エラーコードを condition に持たせる。 |
| 対話時の restart — Ignore and continue | [残す] | そのまま。 |
| 永続 nshell.user パッケージ | [残す] | そのまま。 |
| (?- …) 論理クエリ — なし | [追加] | 履歴・ジョブ・ファイルなどの事実に問い合わせ、レコードで返す (06-F)。 |
| capture・capture-lines・status・run — なし | [追加] | 値の位置でコマンドの結果を得る明示的な形式 (L4)。 |
| defcmd — define-shell-function はあり | [追加] | 語を受け取るコマンドを定義。define-shell-function は別名 (L4)。 |
| (& FORM)・with-env・glob・files・str — なし | [追加] | S式での背景実行・環境変数・glob・ファイル一覧・文字列連結 (L3・L4)。 |

### bare-line

| 機能 — 現状 | 判定 | 方針 |
|---|---|---|
| 単純コマンドとクォート — ' " \ とコメント # | [残す] | そのまま。 |
| 区切り — \| && \|\| ; & 改行 | [残す] | そのまま。 |
| リダイレクト — > >> < 2> 2>> 2>&1 &> &>> 1> 0< >\| <& | [残す] | そのまま。L3.4 にない >\|・<&・0<・1> も残し、L3.4 に追記する。 |
| here-string — <<< | [残す] | 1 行で済むので維持。 |
| here-doc — << <<- | [削除候補] | S式の文字列で代替。v0.8 で削除し、実行前に E_UNSUPPORTED_SYNTAX で拒否する。 |
| 制御構文 — if else for in while case switch begin end | [削除候補] | S式の制御形式に一本化。v0.8 で削除し、実行前に E_UNSUPPORTED_SYNTAX で入力全体を拒否して、同じ意味の S式を示す (L5)。! と not cmd; and cmd2 の形も同じ。 |
| fish 形式の function … end | [削除候補] | defcmd に一本化 (L5.3)。v0.8 で削除し、E_UNSUPPORTED_SYNTAX で拒否する。 |
| 前置代入 — FOO=1 cmd | [残す] | そのまま。 |
